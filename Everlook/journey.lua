local _, Everlook = ...

Everlook.journey = {}

-- A character's journey: the quests it takes, completes or gives up, the zones it
-- finds and the creatures it meets. It is the one place a character name leaves
-- the game, so it has its own question, separate from recording world data, and
-- it records nothing until the player has said yes.
--
-- Rows are kept in EverlookDB.qol.journey, which the app never reads, and are
-- sealed at logout into signed chunks in EverlookDB.journey, which it does. A
-- chunk holds the character's token, never its GUID; the GUID-to-token map and
-- the record of what has been seen stay in the first table. See
-- docs/contracts.md, "Journey".

local ACCEPTED, COMPLETED, ABANDONED, MET, ZONE = 1, 2, 3, 4, 5
local KINDS = {
	quest_accepted = ACCEPTED,
	quest_completed = COMPLETED,
	quest_abandoned = ABANDONED,
	met = MET,
	zone = ZONE,
}

local CHUNK_ROWS = 500
local MET_CAP = 20000
local ROW_CAP = 25000
local MAX_ID = 2147483647
local KEY_SPAN = 4294967296

-- The game fires QUEST_REMOVED for a turn-in as well as for giving a quest up, and
-- not always in the same order as QUEST_TURNED_IN, so a removal is decided a moment later.
local REMOVAL_WAIT = 2

-- The journey question comes after the world-data question, which settles at 6 seconds.
local SETTLE = 14
local RETRY = 8
local TRIES = 10
local DIALOG = "EVERLOOK_JOURNEY"
local TEXT = "Everlook can also keep a journey for each character you play: the quests it takes, the zones it finds and the creatures it meets, with the character's name, realm, class, race and level. If you are signed in to the Everlook app, the app sends it to everlook.ing, where other signed-in members can see it unless you choose otherwise. You choose how each character is shown, and who sees it, on everlook.ing.\n\nKeep a journey for your characters?\n\nYou can change this at any time: type /everlook and turn Keep a journey on or off. Turning it off removes what has not been sent yet. What the site already holds you can delete in your settings on everlook.ing."

local function plain(value)
	return not (issecretvalue and issecretvalue(value))
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

-- What stays on this machine: the GUID-to-token map, and for each character the
-- rows waiting to be sealed and what it has already recorded.
local function private()
	local db = saved()
	db.qol = db.qol or {}
	db.qol.journey = db.qol.journey or { tokens = {}, state = {} }
	return db.qol.journey
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
	return string.format("%016x", (time and time() or 0) % 0xFFFFFFFF)
end

-- The token and rows of the character playing now, made the first time it records.
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
		state = { seq = 0, rows = 0, met = 0, seen = {}, last = {}, pending = {} }
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
	return {
		name = name,
		realm = realm,
		class = number_or_zero(class, 1, 100) > 0 and class or nil,
		race = type(race) == "string" and plain(race) and race:match("^%a+$") and race or nil,
		faction = faction,
		level = number_or_zero(type(UnitLevel) == "function" and UnitLevel("player") or nil, 1, 255) > 0 and UnitLevel("player") or nil,
	}
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

-- Records one thing. A creature or zone counts once ever, and a quest by where it
-- stands: taken once while it is held, completed once, given up only while held.
function Everlook.journey.note(name, id, map)
	if not Everlook.journey.enabled() then
		return
	end
	local kind = KINDS[name]
	if not kind or type(id) ~= "number" or not plain(id) or id ~= math.floor(id) or id < 1 or id > MAX_ID then
		return
	end
	local _, state = current()
	if not state or state.rows >= ROW_CAP then
		return
	end
	if kind == MET or kind == ZONE then
		local key = kind * KEY_SPAN + id
		if state.seen[key] or (kind == MET and state.met >= MET_CAP) then
			return
		end
		state.seen[key] = true
		if kind == MET then
			state.met = state.met + 1
		end
	else
		local last = state.last[id]
		if (kind == ACCEPTED and last == ACCEPTED) or (kind == COMPLETED and last == COMPLETED) or (kind == ABANDONED and last ~= ACCEPTED) then
			return
		end
		state.last[id] = kind
	end
	state.seq = state.seq + 1
	state.rows = state.rows + 1
	state.pending[#state.pending + 1] = {
		state.seq,
		kind,
		id,
		map or map_here(),
		level_here(),
		now(),
	}
end

local function note_zone()
	local map = map_here()
	if map > 0 then
		Everlook.journey.note("zone", map, map)
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

-- Serializes a chunk's document the way a world segment is: CBOR, then base64,
-- deflated when that is shorter.
local function pack(token, about, rows)
	local cbor = C_EncodingUtil.SerializeCBOR({ v = 1, t = token, p = about, r = rows }, { ignoreSerializationErrors = true })
	local payload = "2r." .. C_EncodingUtil.EncodeBase64(cbor)
	if C_EncodingUtil.CompressString then
		local method = Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate or 0
		local level = Enum and Enum.CompressionLevel and Enum.CompressionLevel.Default or 0
		local deflated = C_EncodingUtil.CompressString(cbor, method, level)
		if type(deflated) == "string" then
			local smaller = "2c." .. C_EncodingUtil.EncodeBase64(deflated)
			if #smaller < #payload then
				payload = smaller
			end
		end
	end
	return payload
end

local function sign(secret, token, from, to, payload)
	return Everlook.hash.hmac_sha256(secret, string.format("j1;%s;%d;%d;%s", token, from, to, payload))
end

-- A chunk's signature covers its token, range and payload, not the secret, so a new
-- token can sign again what is already stored, as the world manifest is signed again.
-- Without this, chunks sealed under an earlier secret would never verify.
local function resign(secret, signer)
	local journey = _G.EverlookDB and _G.EverlookDB.journey
	if type(journey) ~= "table" or journey.signer == signer or type(journey.characters) ~= "table" then
		return
	end
	for token, character in pairs(journey.characters) do
		for _, chunk in ipairs(character.chunks) do
			chunk.signature = sign(secret, token, chunk.from, chunk.to, chunk.payload)
		end
	end
	journey.signer = signer
end

local function seal_character(token, state, secret)
	local journey = uploaded()
	journey.characters = journey.characters or {}
	local character = journey.characters[token] or { chunks = {} }
	journey.characters[token] = character
	local rows = state.pending
	for first = 1, #rows, CHUNK_ROWS do
		local group = {}
		for index = first, math.min(first + CHUNK_ROWS - 1, #rows) do
			group[#group + 1] = rows[index]
		end
		local from, to = group[1][1], group[#group][1]
		local payload = pack(token, state.profile, group)
		character.chunks[#character.chunks + 1] = {
			from = from,
			to = to,
			payload = payload,
			signature = sign(secret, token, from, to, payload),
		}
	end
	state.pending = {}
end

-- At logout, signs what the session recorded. Without the token the app places
-- there is nothing to sign with, so the rows wait for the next logout.
function Everlook.journey.seal()
	if not Everlook.journey.enabled() or not Everlook.config or type(Everlook.config.credentials) ~= "function" then
		return
	end
	local secret, signer = Everlook.config.credentials()
	if not secret or type(C_EncodingUtil) ~= "table" or type(C_EncodingUtil.SerializeCBOR) ~= "function" or type(C_EncodingUtil.EncodeBase64) ~= "function" then
		return
	end
	resign(secret, signer)
	local store = private()
	local playing = player_guid() and store.tokens[player_guid()]
	for token, state in pairs(store.state) do
		if token == playing then
			state.profile = profile() or state.profile
		end
		if #state.pending > 0 and state.profile then
			seal_character(token, state, secret)
			uploaded().signer = signer
			uploaded().v = 1
		end
	end
end

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

-- Asked once, only after the world-data question has been answered, and never
-- over another dialog, in combat or in a cinematic.
local function ask(tries)
	if Everlook.journey.asked() then
		return
	end
	local ready = Everlook.config and Everlook.config.asked() and Everlook.consent and not Everlook.consent.blocked()
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
local EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "PLAYER_LOGOUT" }
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

-- Called once the player is in the world: listens if the journey is on, asks if it has not been answered.
function Everlook.journey.start()
	if Everlook.journey.enabled() then
		listen(true)
		note_zone()
	end
	if Everlook.journey.asked() or type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then
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
	journey.enabled = on and true or false
	if not on then
		journey.characters = nil
		local db = saved()
		local store = db.qol and db.qol.journey
		if store then
			for _, state in pairs(store.state) do
				state.pending = {}
				state.seen = {}
				state.last = {}
			end
		end
	end
	listen(on and true or false)
	if on then
		note_zone()
	end
end
