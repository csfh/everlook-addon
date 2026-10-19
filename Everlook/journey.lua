local _, Everlook = ...

Everlook.journey = {}

-- A character's journey: the quests it takes, completes or gives up, the zones it
-- finds and the creatures it meets. It is the one place a character name leaves
-- the game, so it has its own question, separate from recording world data, and
-- it records nothing until the player has said yes.
--
-- The saved file holds strings, never big tables, as the world data does, and for
-- the same reason: a long journey must not make the file too large to load.
--
--   EverlookDB.qol.journey (stays on this machine)
--     tokens[guid]  the character's token
--     state[token]  small numbers and counts, and `pages`: what has been recorded,
--                   in pages of ids, each one an encoded string, read when touched
--   EverlookDB.journey (what the app reads)
--     characters[token].chunks  rows sharded by sequence number, 500 to a chunk,
--                   each packed and signed on its own
--
-- Chunks are signed strictly in order, a few blocks a frame, so the app can send
-- the unbroken run of signed chunks and stop at the first one that is not ready.
-- See docs/contracts.md, "Journey". These pages are not the world data's
-- (pages.lua): their names hold a token, and a dirty one must not queue a world segment.

local ACCEPTED, COMPLETED, ABANDONED, MET, ZONE, AREA = 1, 2, 3, 4, 5, 6
local KINDS = {
	quest_accepted = ACCEPTED,
	quest_completed = COMPLETED,
	quest_abandoned = ABANDONED,
	met = MET,
	zone = ZONE,
	area = AREA,
}

-- A chunk covers one range of sequence numbers. It is full when it reaches the end of its range.
local RANGE = 500
local MET_CAP = 20000
local ROW_CAP = 25000
local MAX_ID = 2147483647

-- A page holds the ids in one span, and at most this many pages are read at a time.
local SPAN = 1024
local MAX_LOADED = 8

-- A gap is a stretch the addon can see the journey did not record. At most this many are kept, the oldest dropped.
local GAPS_KEPT = 12

-- The game fires QUEST_REMOVED for a turn-in as well as for giving a quest up, and
-- not always in the same order as QUEST_TURNED_IN, so a removal is decided a moment later.
local REMOVAL_WAIT = 2

-- Signing runs a few blocks at a time, as the world manifest does. At logout it gets a short
-- budget, well under what the world data spends, and whatever is left is signed next session.
local HASH_BLOCKS = 6
local LOGOUT_MS = 100
local NO_TOKEN_SLEEP = 10

-- The journey question comes after the world-data question, which settles at 6 seconds.
local SETTLE = 14
local RETRY = 8
local TRIES = 10
local DIALOG = "EVERLOOK_JOURNEY"
local TEXT = "Everlook can also keep a journey for each character you play: the quests it takes, the zones and places it finds and the creatures it meets, with the character's name, realm, class, race and level. If you are signed in to the Everlook app, the app sends it to everlook.ing, where other signed-in members can see it unless you choose otherwise. You choose how each character is shown, and who sees it, on everlook.ing.\n\nKeep a journey for your characters?\n\nYou can change this at any time: type /everlook and turn Keep a journey on or off. Turning it off removes what has not been sent yet. What the site already holds you can delete in your settings on everlook.ing."

-- Where a character stood is its own question, asked once after the journey is on, because a position is
-- more than the journey says: it marks where on the map each thing happened.
local POSITIONS_DIALOG = "EVERLOOK_JOURNEY_POSITIONS"
local POSITIONS_TEXT = "Everlook can also keep where on the map your character stood for each thing in the journey, as a spot accurate to a tenth of a percent of the map. everlook.ing uses it to show where you have been on your journey page, to whoever you let see the journey.\n\nKeep where your characters stood?\n\nYou can change this at any time: type /everlook and turn Keep where I stood on or off. Turning it off stops new spots being kept. Spots already in the journey waiting to be sent are still sent, and what the site already holds you can delete in your settings on everlook.ing."

local function plain(value)
	return not (issecretvalue and issecretvalue(value))
end

local function clock()
	if type(debugprofilestop) == "function" then
		return debugprofilestop()
	end
end

local function saved()
	_G.EverlookDB = _G.EverlookDB or {}
	return _G.EverlookDB
end

-- The table the app uploads. Only what is read here is made, so a player who never says yes has none.
local function uploaded()
	local db = saved()
	db.journey = db.journey or { v = 1 }
	return db.journey
end

local function private()
	local db = saved()
	db.qol = db.qol or {}
	db.qol.journey = db.qol.journey or { tokens = {}, state = {} }
	return db.qol.journey
end

-- Whether this client can encode what the journey saves. Without it nothing is recorded.
function Everlook.journey.available()
	local encoding = C_EncodingUtil
	return type(encoding) == "table"
		and type(encoding.SerializeCBOR) == "function"
		and type(encoding.DeserializeCBOR) == "function"
		and type(encoding.EncodeBase64) == "function"
		and type(encoding.DecodeBase64) == "function"
end

function Everlook.journey.enabled()
	local db = _G.EverlookDB
	return type(db) == "table" and type(db.journey) == "table" and db.journey.enabled == true
end

-- Whether the player has answered, either way.
function Everlook.journey.asked()
	local db = _G.EverlookDB
	return type(db) == "table" and type(db.journey) == "table" and db.journey.enabled ~= nil
end

-- Whether the player has said yes to keeping where each thing happened.
function Everlook.journey.positions()
	local db = _G.EverlookDB
	return type(db) == "table" and type(db.journey) == "table" and db.journey.positions == true
end

-- Whether the player has answered the question about positions, either way.
function Everlook.journey.positions_asked()
	local db = _G.EverlookDB
	return type(db) == "table" and type(db.journey) == "table" and db.journey.positions ~= nil
end

-- Encoding. A value becomes CBOR, then base64, deflated when that is shorter. The prefix
-- says which, and says whose: "j1" is the journey's own pages, "2" a chunk for the site.
local function deflate_method()
	return Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate or 0
end

local function wrap(prefix, value)
	local encoding = C_EncodingUtil
	local cbor = encoding.SerializeCBOR(value, { ignoreSerializationErrors = true })
	local mode, body = "r", cbor
	if encoding.CompressString then
		local level = Enum and Enum.CompressionLevel and Enum.CompressionLevel.Default or 0
		local deflated = encoding.CompressString(cbor, deflate_method(), level)
		if type(deflated) == "string" and #deflated < #cbor then
			mode, body = "c", deflated
		end
	end
	return prefix .. mode .. "." .. encoding.EncodeBase64(body)
end

local function unwrap(prefix, text)
	if type(text) ~= "string" then
		return nil
	end
	local mode, body = text:match("^" .. prefix .. "([rc])%.(.*)$")
	if not mode then
		return nil
	end
	local encoding = C_EncodingUtil
	local binary = encoding.DecodeBase64(body)
	if type(binary) ~= "string" then
		return nil
	end
	if mode == "c" then
		if not encoding.DecompressString then
			return nil
		end
		binary = encoding.DecompressString(binary, deflate_method())
		if type(binary) ~= "string" then
			return nil
		end
	end
	local value = encoding.DeserializeCBOR(binary)
	return type(value) == "table" and value or nil
end

-- Pages: what has been recorded, as ids in spans, so a long journey is a few strings and not
-- thousands of table entries. A page is read when first touched, at most MAX_LOADED are kept,
-- and the least recently used goes first, saved if it changed. Spaces: m creatures met, z zones
-- found, q quests (the last thing done, and 4 more once completed).
local pages = {}
local page_count = 0
local page_clock = 0

local function flush_page(entry)
	if entry.dirty then
		entry.state.pages[entry.key] = next(entry.data) ~= nil and wrap("j1", entry.data) or nil
		entry.dirty = false
	end
end

local function make_room()
	while page_count >= MAX_LOADED do
		local oldest, handle
		for key, entry in pairs(pages) do
			if not oldest or entry.used < oldest.used then
				oldest, handle = entry, key
			end
		end
		if not oldest then
			return
		end
		flush_page(oldest)
		pages[handle] = nil
		page_count = page_count - 1
	end
end

local function page_for(token, state, space, id)
	local key = space .. ":" .. math.floor(id / SPAN)
	local handle = token .. "|" .. key
	local entry = pages[handle]
	page_clock = page_clock + 1
	if not entry then
		make_room()
		entry = { state = state, key = key, data = unwrap("j1", state.pages[key]) or {}, used = 0 }
		pages[handle] = entry
		page_count = page_count + 1
	end
	entry.used = page_clock
	return entry
end

local function flush_pages()
	for _, entry in pairs(pages) do
		flush_page(entry)
	end
end

-- Drops every page of one character without saving them, for when what they remember is wiped.
local function drop_pages(state)
	for handle, entry in pairs(pages) do
		if entry.state == state then
			pages[handle] = nil
			page_count = page_count - 1
		end
	end
end

function Everlook.journey.loaded()
	return page_count
end

local function fresh_counts()
	return { completed = 0, started = 0, abandoned = 0, met = 0, zones = 0, areas = 0 }
end

-- The server's time, not this machine's clock, which the site would refuse if it ran a day ahead.
local function now()
	if type(GetServerTime) == "function" then
		local server = GetServerTime()
		if type(server) == "number" and plain(server) then
			return server
		end
	end
	return type(time) == "function" and time() or 0
end

local function player_guid()
	local guid = type(UnitGUID) == "function" and UnitGUID("player") or nil
	if type(guid) ~= "string" or guid == "" or not plain(guid) then
		return nil
	end
	return guid
end

local function unique_token(tokens)
	local taken = {}
	for _, token in pairs(tokens) do
		taken[token] = true
	end
	for _ = 1, 20 do
		local token = string.format("%04x%04x%04x%04x", math.random(0, 0xFFFF), math.random(0, 0xFFFF), math.random(0, 0xFFFF), math.random(0, 0xFFFF))
		if not taken[token] then
			return token
		end
	end
	return string.format("%016x", now() % 0xFFFFFFFF)
end

-- The token and numbers of the character playing now, made the first time it records.
local function current()
	local guid = player_guid()
	if not guid then
		return nil
	end
	local store = private()
	local token = store.tokens[guid]
	if not token then
		token = unique_token(store.tokens)
		store.tokens[guid] = token
	end
	local state = store.state[token]
	if not state then
		state = { seq = 0, rows = 0, met_rows = 0, counts = fresh_counts(), pages = {} }
		store.state[token] = state
	end
	return token, state
end

local function number_or_zero(value, low, high)
	if type(value) == "number" and plain(value) and value >= low and value <= high then
		return math.floor(value)
	end
	return 0
end

local function map_here()
	if type(C_Map) ~= "table" or type(C_Map.GetBestMapForUnit) ~= "function" then
		return 0
	end
	return number_or_zero(C_Map.GetBestMapForUnit("player"), 1, MAX_ID)
end

local function level_here()
	return number_or_zero(type(UnitLevel) == "function" and UnitLevel("player") or nil, 1, 255)
end

-- Where on the map the player stands, in tenths of a percent of its width and height (1 to 1000), or 0 and 0
-- where the game does not say, as it does not inside an instance. Only read when the player has said yes.
local function spot_here(map)
	if map < 1 or type(C_Map) ~= "table" or type(C_Map.GetPlayerMapPosition) ~= "function" then
		return 0, 0
	end
	local ok, position = pcall(C_Map.GetPlayerMapPosition, map, "player")
	if not ok or type(position) ~= "table" then
		return 0, 0
	end
	local x, y
	if type(position.GetXY) == "function" then
		x, y = position:GetXY()
	else
		x, y = position.x, position.y
	end
	if type(x) ~= "number" or type(y) ~= "number" or not plain(x) or not plain(y) then
		return 0, 0
	end
	local tx, ty = math.floor(x * 1000 + 0.5), math.floor(y * 1000 + 0.5)
	if tx < 1 or tx > 1000 or ty < 1 or ty > 1000 then
		return 0, 0
	end
	return tx, ty
end

-- How many quests the game lists as done. It counts more than the journey can: the game also lists quests that
-- finish by themselves, such as ones that track a place visited, so a difference is reported as what the game
-- lists and never as quests the journey missed.
local function completed_count()
	local reader = type(C_QuestLog) == "table" and C_QuestLog.GetAllCompletedQuestIDs
	if type(reader) ~= "function" then
		return nil
	end
	local ok, ids = pcall(reader)
	if ok and type(ids) == "table" then
		return #ids
	end
end

-- Where the character stands now, to compare with the next time. Fields the game does not give are left out.
local function mark_now()
	local level = level_here()
	return { at = now(), level = level > 0 and level or nil, done = completed_count() }
end

local function add_gap(state, gap)
	state.gaps = state.gaps or {}
	state.gaps[#state.gaps + 1] = gap
	while #state.gaps > GAPS_KEPT do
		table.remove(state.gaps, 1)
	end
end

-- Looks for a stretch the journey did not record, and only reports one it has firm evidence for: the player
-- turned the journey off and on again, or the character gained levels while the addon was not there to see
-- it (a level does not change while logged out). A rise in the game's own list of finished quests is not
-- evidence, because the game finishes some by itself; it is reported only inside a stretch that is one.
-- A journey that already had rows before this existed gets a mark and no claim about what came before; only a
-- brand-new journey is given a baseline.
local function watch(state)
	local here = mark_now()
	local mark = state.mark
	if not mark then
		if state.seq == 0 and state.baseline == nil then
			state.baseline = { at = here.at, level = here.level, done = here.done }
		end
	else
		local gained = (here.level or 0) - (mark.level or 0)
		local listed = (here.done and mark.done and here.done > mark.done) and here.done - mark.done or nil
		if state.off_at then
			add_gap(state, { k = 1, f = state.off_at, t = here.at, l = gained > 0 and gained or nil, d = listed })
		elseif gained > 0 then
			add_gap(state, { k = 2, f = mark.at, t = here.at, l = gained, d = listed })
		end
	end
	state.off_at = nil
	state.mark = here
end

-- The journey is full: from now it adds nothing new. Said once.
local function record_cap(state)
	if not state.capped then
		state.capped = true
		add_gap(state, { k = 3, f = now() })
	end
end

-- What a chunk says about its character. Nothing is made without a name and a realm.
local function profile()
	local name = type(UnitName) == "function" and UnitName("player") or nil
	local realm = type(GetRealmName) == "function" and GetRealmName() or nil
	if type(name) ~= "string" or name == "" or type(realm) ~= "string" or realm == "" or not plain(name) or not plain(realm) then
		return nil
	end
	local class
	if type(UnitClass) == "function" then
		class = select(3, UnitClass("player"))
	end
	local race
	if type(UnitRace) == "function" then
		race = select(2, UnitRace("player"))
	end
	local faction = type(UnitFactionGroup) == "function" and UnitFactionGroup("player") or nil
	if faction ~= "Alliance" and faction ~= "Horde" and faction ~= "Neutral" then
		faction = nil
	end
	local level = level_here()
	return {
		name = name,
		realm = realm,
		class = number_or_zero(class, 1, 100) > 0 and class or nil,
		race = type(race) == "string" and plain(race) and race:match("^%a+$") and race or nil,
		faction = faction,
		level = level > 0 and level or nil,
	}
end

-- Chunks. The rows of a chunk are kept in memory while it is open, and packed when it fills
-- and at logout. A packed chunk is { from, to, payload }, and gets a `signature` when its turn comes.
local session = {}
local task

local function wake()
	if task then
		task.wake()
	end
end

local function range_end(from)
	return math.ceil(from / RANGE) * RANGE
end

local function character_for(token)
	local journey = uploaded()
	journey.characters = journey.characters or {}
	journey.characters[token] = journey.characters[token] or { chunks = {} }
	return journey.characters[token]
end

-- The rows of the open chunk, read from the last packed chunk the first time they are wanted
-- in a session, when that chunk still has room.
local function open_for(token)
	local cache = session[token]
	if cache then
		return cache
	end
	cache = { rows = {} }
	session[token] = cache
	local db = _G.EverlookDB
	local character = db and db.journey and db.journey.characters and db.journey.characters[token]
	local last = character and character.chunks[#character.chunks]
	if last and last.to < range_end(last.from) then
		local document = unwrap("2", last.payload)
		if document and type(document.r) == "table" and #document.r > 0 then
			cache.rows = document.r
		end
	end
	return cache
end

local function pack(token, about, rows)
	return wrap("2", { v = 1, t = token, p = about, r = rows })
end

-- Packs the open chunk in place, so a session adds rows to it and not a chunk of its own. Its
-- signature goes, since it no longer covers what is there.
local function pack_open(token, state, cache)
	local rows = cache.rows
	if #rows == 0 or not state.profile then
		return false
	end
	local chunks = character_for(token).chunks
	local from, to = rows[1][1], rows[#rows][1]
	local entry = chunks[#chunks]
	if not entry or entry.from ~= from then
		entry = {}
		chunks[#chunks + 1] = entry
	end
	-- A fresh table each time: the profile is read again at logout, and the baseline and gaps are not part of it.
	local about = {}
	for key, value in pairs(state.profile) do
		about[key] = value
	end
	about.base = state.baseline
	about.gaps = state.gaps and #state.gaps > 0 and state.gaps or nil
	entry.from, entry.to, entry.payload, entry.signature = from, to, pack(token, about, rows), nil
	cache.dirty = false
	return true
end

local function append_row(token, state, row)
	local cache = open_for(token)
	cache.rows[#cache.rows + 1] = row
	cache.dirty = true
	if row[1] >= range_end(cache.rows[1][1]) and pack_open(token, state, cache) then
		cache.rows = {}
		wake()
	end
end

-- Where a character stands with a quest: completed, in progress or given up.
local function progress(value)
	local completed = value >= 4
	local last = completed and value - 4 or value
	if completed then
		return "completed"
	end
	if last == ACCEPTED then
		return "started"
	end
	if last == ABANDONED then
		return "abandoned"
	end
end

-- Records one thing. A creature or zone counts once ever, and a quest by where it
-- stands: taken once while it is held, completed once, given up only while it is held.
function Everlook.journey.note(name, id, map)
	if not Everlook.journey.enabled() or not Everlook.journey.available() then
		return
	end
	local kind = KINDS[name]
	if not kind or type(id) ~= "number" or not plain(id) or id ~= math.floor(id) or id < 1 or id > MAX_ID then
		return
	end
	local token, state = current()
	if not state then
		return
	end
	if state.rows >= ROW_CAP then
		record_cap(state)
		return
	end
	state.profile = state.profile or profile()
	if not state.profile then
		return
	end
	local counts = state.counts
	if kind == MET or kind == ZONE or kind == AREA then
		local space = kind == MET and "m" or (kind == ZONE and "z" or "a")
		local entry = page_for(token, state, space, id)
		if entry.data[id] then
			return
		end
		if kind == MET and state.met_rows >= MET_CAP then
			record_cap(state)
			return
		end
		entry.data[id] = 1
		entry.dirty = true
		if kind == MET then
			state.met_rows = state.met_rows + 1
			counts.met = counts.met + 1
		elseif kind == ZONE then
			counts.zones = counts.zones + 1
		else
			counts.areas = (counts.areas or 0) + 1
		end
	else
		local entry = page_for(token, state, "q", id)
		local value = entry.data[id] or 0
		local completed = value >= 4
		local last = completed and value - 4 or value
		if (kind == ACCEPTED and last == ACCEPTED) or (kind == COMPLETED and last == COMPLETED) or (kind == ABANDONED and last ~= ACCEPTED) then
			return
		end
		local after = kind + ((completed or kind == COMPLETED) and 4 or 0)
		local before_state, after_state = progress(value), progress(after)
		if before_state then
			counts[before_state] = counts[before_state] - 1
		end
		if after_state then
			counts[after_state] = counts[after_state] + 1
		end
		entry.data[id] = after
		entry.dirty = true
	end
	state.seq = state.seq + 1
	state.rows = state.rows + 1
	local where = map or map_here()
	local row = { state.seq, kind, id, where, level_here(), now() }
	-- A spot is kept only after the player has said yes to it, and is whole or missing: both numbers, or 0 and 0.
	if Everlook.journey.positions() then
		row[7], row[8] = spot_here(where)
	end
	append_row(token, state, row)
end

local function note_zone()
	local map = map_here()
	if map > 0 then
		Everlook.journey.note("zone", map, map)
	end
end

-- The area the player stands in, by the game's own list of what the character has uncovered at this spot. An area is
-- recorded once ever, like a zone.
local function note_area()
	local map = map_here()
	local reader = type(C_MapExplorationInfo) == "table" and C_MapExplorationInfo.GetExploredAreaIDsAtPosition
	if map < 1 or type(reader) ~= "function" or type(C_Map) ~= "table" or type(C_Map.GetPlayerMapPosition) ~= "function" then
		return
	end
	local ok, position = pcall(C_Map.GetPlayerMapPosition, map, "player")
	if not ok or type(position) ~= "table" then
		return
	end
	local found, ids = pcall(reader, map, position)
	if not found or type(ids) ~= "table" then
		return
	end
	local area = ids[1]
	if type(area) == "number" and plain(area) and area >= 1 then
		Everlook.journey.note("area", area, map)
	end
end

local function note_removal(id)
	local function decide()
		if C_QuestLog and type(C_QuestLog.IsQuestFlaggedCompleted) == "function" and C_QuestLog.IsQuestFlaggedCompleted(id) then
			return
		end
		Everlook.journey.note("quest_abandoned", id)
	end
	if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
		C_Timer.After(REMOVAL_WAIT, decide)
	else
		decide()
	end
end

-- Signing. The signature covers the token, the range and the payload, and is made with the
-- account's token a few blocks at a time. It goes in order, one character's chunks after
-- one another, so the app can send the unbroken run that is signed and stop at the first
-- chunk that is not ready, and no chunk is skipped over.
local pads, pads_secret
local job

local function pads_for(secret)
	if pads_secret ~= secret then
		pads, pads_secret = Everlook.hash.hmac_key(secret), secret
	end
	return pads
end

local function first_unsigned()
	local db = _G.EverlookDB
	local characters = db and db.journey and db.journey.characters
	if type(characters) ~= "table" then
		return nil
	end
	for token, character in pairs(characters) do
		for _, chunk in ipairs(character.chunks) do
			if not chunk.signature then
				return token, chunk
			end
		end
	end
end

-- A new token signs every chunk again, so each loses its signature until its turn comes
-- and none is sent under the old one, where the site would turn it away for good.
local function ensure_signer(signer)
	local journey = _G.EverlookDB and _G.EverlookDB.journey
	if type(journey) ~= "table" or journey.signer == signer then
		return
	end
	for _, character in pairs(journey.characters or {}) do
		for _, chunk in ipairs(character.chunks) do
			chunk.signature = nil
		end
	end
	journey.signer = signer
	job = nil
end

local function sign_step(limit)
	if not Everlook.journey.enabled() then
		job = nil
		return false
	end
	local secret, signer
	if Everlook.config and type(Everlook.config.credentials) == "function" then
		secret, signer = Everlook.config.credentials()
	end
	-- A new token is noticed first: it is what leaves the chunks unsigned.
	if secret and _G.EverlookDB.journey.signer ~= signer then
		ensure_signer(signer)
	end
	local token, chunk = first_unsigned()
	if not chunk then
		job = nil
		return false
	end
	if not secret then
		return NO_TOKEN_SLEEP
	end
	local began = clock()
	repeat
		if not job or job.chunk ~= chunk or job.payload ~= chunk.payload then
			job = {
				chunk = chunk,
				payload = chunk.payload,
				stream = Everlook.hash.hmac_stream(pads_for(secret), string.format("j1;%s;%d;%d;%s", token, chunk.from, chunk.to, chunk.payload)),
			}
		end
		if job.stream:step(HASH_BLOCKS) then
			chunk.signature = job.stream:hex()
			job = nil
			token, chunk = first_unsigned()
			if not chunk then
				return false
			end
		end
	until not began or clock() - began >= (limit or 0)
	return true
end

-- At logout, packs what the session recorded and signs as much as the budget allows. What is
-- left is signed in the background next session.
function Everlook.journey.seal()
	if not Everlook.journey.enabled() or not Everlook.journey.available() then
		return
	end
	local store = private()
	local playing = player_guid() and store.tokens[player_guid()]
	for token, state in pairs(store.state) do
		if token == playing then
			state.profile = profile() or state.profile
			-- Where the character stood when it left, so the next login can tell what changed while the addon was away.
			if Everlook.journey.enabled() then
				state.mark = mark_now()
			end
		end
		local cache = session[token]
		if cache and cache.dirty then
			pack_open(token, state, cache)
		end
	end
	flush_pages()
	if not Everlook.config or type(Everlook.config.credentials) ~= "function" then
		return
	end
	local began = clock()
	while sign_step(LOGOUT_MS) == true do
		if began and clock() - began >= LOGOUT_MS then
			break
		end
	end
end

-- What the settings page shows: the counts of the character playing now, and where signing stands.
function Everlook.journey.summary()
	local summary = { available = Everlook.journey.available(), enabled = Everlook.journey.enabled(), positions = Everlook.journey.positions() }
	local guid = player_guid()
	local token = guid and _G.EverlookDB and _G.EverlookDB.qol and _G.EverlookDB.qol.journey and _G.EverlookDB.qol.journey.tokens[guid]
	local state = token and _G.EverlookDB.qol.journey.state[token]
	if state then
		summary.counts, summary.rows, summary.profile = state.counts, state.rows, state.profile
		summary.baseline, summary.gaps = state.baseline, state.gaps
	end
	local signed, waiting = 0, 0
	local characters = _G.EverlookDB and _G.EverlookDB.journey and _G.EverlookDB.journey.characters
	local character = token and characters and characters[token]
	for _, chunk in ipairs(character and character.chunks or {}) do
		if chunk.signature then
			signed = signed + 1
		else
			waiting = waiting + 1
		end
	end
	summary.signed, summary.waiting = signed, waiting
	summary.open = token and session[token] and #session[token].rows or 0
	summary.token = Everlook.config and type(Everlook.config.credentials) == "function" and Everlook.config.credentials() ~= nil
	return summary
end

-- The question about positions is asked after the journey's yes, so the journey's dialog needs to reach it.
local ask_positions

local function define()
	StaticPopupDialogs[DIALOG] = {
		text = TEXT,
		button1 = "Keep a journey",
		button2 = "Don't keep one",
		OnAccept = function()
			Everlook.journey.set_enabled(true)
			if Everlook.say then
				Everlook.say("The journey is on. Turn it off with /everlook.")
			end
			if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
				C_Timer.After(RETRY, function()
					ask_positions(TRIES)
				end)
			end
		end,
		OnCancel = function(_, _, reason)
			-- "override" is the game closing it for something else, not the player's answer.
			if reason == "clicked" or reason == nil then
				Everlook.journey.set_enabled(false)
				if Everlook.say then
					Everlook.say("The journey is off. Turn it on with /everlook.")
				end
			end
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
end

local function define_positions()
	StaticPopupDialogs[POSITIONS_DIALOG] = {
		text = POSITIONS_TEXT,
		button1 = "Keep where I stood",
		button2 = "Don't keep it",
		OnAccept = function()
			Everlook.journey.set_positions(true)
			if Everlook.say then
				Everlook.say("Keeping where you stood is on. Turn it off with /everlook.")
			end
		end,
		OnCancel = function(_, _, reason)
			-- "override" is the game closing it for something else, not the player's answer.
			if reason == "clicked" or reason == nil then
				Everlook.journey.set_positions(false)
				if Everlook.say then
					Everlook.say("Keeping where you stood is off. Turn it on with /everlook.")
				end
			end
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
end

-- Asked once, after the journey is on, and never over another dialog, in combat or in a cinematic. A player who
-- said yes to the journey before positions existed is asked too: their yes did not cover where they stood.
ask_positions = function(tries)
	if not Everlook.journey.enabled() or Everlook.journey.positions_asked() then
		return
	end
	local ready = Everlook.journey.available() and Everlook.consent and not Everlook.consent.blocked()
	if ready then
		define_positions()
		StaticPopup_Show(POSITIONS_DIALOG)
		return
	end
	if tries > 1 and type(C_Timer) == "table" and type(C_Timer.After) == "function" then
		C_Timer.After(RETRY, function()
			ask_positions(tries - 1)
		end)
	end
end

-- Asked once, only after the world-data question has been answered, and never
-- over another dialog, in combat or in a cinematic.
local function ask(tries)
	if Everlook.journey.asked() then
		return
	end
	local ready = Everlook.journey.available() and Everlook.config and Everlook.config.asked() and Everlook.consent and not Everlook.consent.blocked()
	if ready then
		define()
		StaticPopup_Show(DIALOG)
		return
	end
	if tries > 1 and type(C_Timer) == "table" and type(C_Timer.After) == "function" then
		C_Timer.After(RETRY, function()
			ask(tries - 1)
		end)
	end
end

-- The journey listens to nothing until the player has said yes, and stops when they say no.
local EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "PLAYER_LEVEL_UP", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "PLAYER_LOGOUT" }
local frame = CreateFrame("Frame")
local listening = false

local function listen(on)
	if on == listening then
		return
	end
	listening = on
	for _, event in ipairs(EVENTS) do
		if on then
			frame:RegisterEvent(event)
		else
			frame:UnregisterEvent(event)
		end
	end
end

frame:SetScript("OnEvent", function(_, event, first, second)
	if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
		note_zone()
		note_area()
	elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
		note_area()
	elseif event == "PLAYER_LEVEL_UP" then
		-- Keep the mark current, so a level gained with the addon here is never mistaken for one it did not see.
		local guid = player_guid()
		local store = private()
		local state = guid and store.tokens[guid] and store.state[store.tokens[guid]]
		if state and state.mark then
			local level = number_or_zero(first, 1, 255)
			state.mark.level = level > 0 and level or level_here()
		end
	elseif event == "QUEST_ACCEPTED" then
		-- Retail sends the quest id alone, older clients the log index and then the id.
		Everlook.journey.note("quest_accepted", type(second) == "number" and second or first)
	elseif event == "QUEST_TURNED_IN" then
		Everlook.journey.note("quest_completed", first)
	elseif event == "QUEST_REMOVED" then
		if type(first) == "number" and plain(first) then
			note_removal(first)
		end
	elseif event == "PLAYER_LOGOUT" then
		Everlook.journey.seal()
	end
end)

-- Signing is a task of the scheduler, and sleeps until there is something to sign.
if Everlook.sched and Everlook.sched.task then
	task = Everlook.sched.task("journey", { step = sign_step })
end

-- Called once the player is in the world: listens if the journey is on, asks if it has not been answered.
function Everlook.journey.start()
	if Everlook.journey.enabled() then
		listen(true)
		local state
		if Everlook.journey.available() then
			local _
			_, state = current()
		end
		if state then
			watch(state)
		end
		note_zone()
		note_area()
		wake()
	end
	if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then
		return
	end
	if Everlook.journey.asked() then
		if Everlook.journey.enabled() and not Everlook.journey.positions_asked() then
			C_Timer.After(SETTLE, function()
				ask_positions(TRIES)
			end)
		end
		return
	end
	C_Timer.After(SETTLE, function()
		ask(TRIES)
	end)
end

-- Turning it off stops recording and removes what has not gone to the app. The
-- sequence numbers stay, since the site has seen them and a lower one would never be sent.
function Everlook.journey.set_enabled(on)
	local journey = uploaded()
	local was = journey.enabled == true
	journey.enabled = on and true or false
	if not on and was then
		-- Where the character stood when the journey stopped, so turning it on again can say what changed in between.
		local guid = player_guid()
		local store = private()
		local state = guid and store.tokens[guid] and store.state[store.tokens[guid]]
		if state then
			state.mark = mark_now()
			state.off_at = state.mark.at
		end
	end
	if not on then
		journey.characters = nil
		job = nil
		local store = saved().qol and saved().qol.journey
		for token, state in pairs(store and store.state or {}) do
			drop_pages(state)
			state.pages = {}
			state.counts = fresh_counts()
			session[token] = nil
		end
	end
	listen(on and true or false)
	if on then
		local state
		if Everlook.journey.available() then
			local _
			_, state = current()
		end
		if state then
			watch(state)
		end
		note_zone()
		note_area()
	end
end

-- Keeping where each thing happened is a yes or a no of its own. Off, new rows carry no spot; the rows already
-- waiting to be sent keep theirs, which the question says.
function Everlook.journey.set_positions(on)
	uploaded().positions = on and true or false
end
