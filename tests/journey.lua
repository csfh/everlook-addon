-- The journey: when it records, how it is kept in the saved file, and what it hands to the app.
return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)
	local GUID = "Player-1234-0ABCDEF0"

	local function deep_copy(value)
		if type(value) ~= "table" then return value end
		local copy = {}
		for key, item in pairs(value) do copy[key] = deep_copy(item) end
		return copy
	end

	-- Every string anywhere in a table, so a test can ask whether a value leaked into it.
	local function contains(value, needle)
		if type(value) == "string" then return value:find(needle, 1, true) ~= nil end
		if type(value) ~= "table" then return false end
		for key, item in pairs(value) do
			if contains(key, needle) or contains(item, needle) then return true end
		end
		return false
	end

	-- How many table entries the saved file would hold: what the game's loader has to count.
	local function entries(value)
		if type(value) ~= "table" then return 0 end
		local count = 0
		for _, item in pairs(value) do count = count + 1 + entries(item) end
		return count
	end

	-- What was encoded, shared by every session in this file so a later session can read an earlier one's strings.
	local blobs = {}

	-- Options: raw (no deflate), no_encoding (a client that cannot encode).
	local function load(db, options)
		options = options or {}
		db = db or {}
		local Everlook = { say = function() end }
		local env = setmetatable({ EverlookDB = db }, { __index = _G })
		env._G = env
		local world = { guid = GUID, name = "Thrall", realm = "Nordanaar", class = 7, race = "Orc", faction = "Horde", level = 38, map = 1411, now = 1760000000, signed = true, asked = true, blocked = nil, clock = 0, tick = 0, stream_steps = 1 }
		local frames, pending, shown = {}, {}, {}
		env.UnitGUID = function() return world.guid end
		env.UnitName = function() return world.name end
		env.GetRealmName = function() return world.realm end
		env.UnitClass = function() return "Shaman", "SHAMAN", world.class end
		env.UnitRace = function() return "Orc", world.race end
		env.UnitFactionGroup = function() return world.faction end
		env.UnitLevel = function() return world.level end
		env.C_Map = {
			GetBestMapForUnit = function() return world.map end,
			-- A spot is a normalized position, as the game gives it, or nothing where the game does not say.
			GetPlayerMapPosition = function()
				if world.spot then
					return { GetXY = function() return world.spot.x, world.spot.y end }
				end
			end,
		}
		-- The areas the character has uncovered at its spot, the first the most specific.
		env.C_MapExplorationInfo = { GetExploredAreaIDsAtPosition = function() return world.areas end }
		env.time = function() return world.now end
		env.GetServerTime = function() return world.server_now or world.now end
		env.debugprofilestop = function()
			world.clock = world.clock + world.tick
			return world.clock
		end
		env.CreateFrame = function()
			local frame = { events = {} }
			function frame:RegisterEvent(event) self.events[event] = true end
			function frame:UnregisterEvent(event) self.events[event] = nil end
			function frame:SetScript(_, fn) self.script = fn end
			frames[#frames + 1] = frame
			return frame
		end
		env.C_Timer = { After = function(_, fn) pending[#pending + 1] = fn end }
		env.StaticPopupDialogs = {}
		env.StaticPopup_Show = function(which) shown[#shown + 1] = which end
		if options.no_encoding then
			env.C_EncodingUtil = false
		else
			env.C_EncodingUtil = {
				SerializeCBOR = function(value)
					blobs[#blobs + 1] = deep_copy(value)
					return "cbor:" .. #blobs
				end,
				DeserializeCBOR = function(text)
					return deep_copy(blobs[tonumber(text:match("cbor:(%d+)$"))])
				end,
				EncodeBase64 = function(text) return text end,
				DecodeBase64 = function(text) return text end,
			}
			if not options.raw then
				-- Deflate drops the first letter, so the compressed path is shorter and is taken.
				env.C_EncodingUtil.CompressString = function(text) return text:sub(2) end
				env.C_EncodingUtil.DecompressString = function(text) return "c" .. text end
			end
		end
		local woken, task = 0, nil
		Everlook.sched = { task = function(_, opts) task = opts; return { wake = function() woken = woken + 1 end } end }
		Everlook.config = {
			credentials = function()
				if world.signed then return world.secret or "secret", world.signer or "0123456789abcdef" end
			end,
			asked = function() return world.asked end,
		}
		Everlook.consent = { blocked = function() return world.blocked end }
		Everlook.hash = {
			hmac_key = function(secret) return { secret = secret } end,
			-- A stream that takes as many steps as the test says, so a chunk can be half signed.
			hmac_stream = function(pads, message)
				local stream = { taken = 0 }
				function stream:step() self.taken = self.taken + 1; return self.taken >= world.stream_steps end
				function stream:hex() return pads.secret .. "|" .. message end
				return stream
			end,
		}
		for _, name in ipairs({ "journey", "journey_page" }) do
			local chunk = assert(loadfile(source(name)))
			setfenv(chunk, env)
			chunk("Everlook", Everlook)
		end
		local session = { Everlook = Everlook, db = db, world = world, env = env, pending = pending, blobs = blobs, shown = shown, frames = frames, step = task.step }
		function session.woken() return woken end
		function session.fire(event, ...)
			for _, frame in ipairs(frames) do
				if frame.events[event] and frame.script then frame.script(frame, event, ...) end
			end
		end
		function session.decode(chunk_row)
			return deep_copy(blobs[tonumber(chunk_row.payload:match("bor:(%d+)$"))])
		end
		function session.character()
			local token = db.qol and db.qol.journey and db.qol.journey.tokens and db.qol.journey.tokens[GUID]
			return token, token and db.qol.journey.state[token]
		end
		function session.chunks()
			local token = session.character()
			local character = token and db.journey and db.journey.characters and db.journey.characters[token]
			return character and character.chunks or {}
		end
		-- Every row the character has recorded, after the saved file would be written.
		function session.rows()
			session.fire("PLAYER_LOGOUT")
			local all = {}
			for _, chunk_row in ipairs(session.chunks()) do
				for _, row in ipairs(session.decode(chunk_row).r) do all[#all + 1] = row end
			end
			return all
		end
		function session.listening()
			local count = 0
			for _, frame in ipairs(frames) do
				for _ in pairs(frame.events) do count = count + 1 end
			end
			return count
		end
		-- Runs what waited on a timer, as the game would a moment later.
		function session.settle()
			for index = 1, #pending do pending[index]() end
			for index = #pending, 1, -1 do pending[index] = nil end
		end
		return session
	end

	-- A journey that is on, standing nowhere, so turning it on notes no zone of its own.
	local function on(db, options)
		local s = load(db, options)
		local map = s.world.map
		s.world.map = nil
		s.Everlook.journey.set_enabled(true)
		s.world.map = map
		return s
	end

	-- The gate: nothing is recorded, and nothing listened to, until the player has said yes.
	local s = load()
	s.world.map = nil
	s.Everlook.journey.note("met", 823)
	s.fire("QUEST_ACCEPTED", 1, 783)
	check("journey records nothing before the player says yes", s.db.qol == nil and s.db.journey == nil)
	check("and listens to nothing", s.listening() == 0)
	s.Everlook.journey.set_enabled(false)
	s.Everlook.journey.note("met", 823)
	check("journey records nothing after the player says no", #s.chunks() == 0 and select(2, s.character()) == nil)
	check("and still listens to nothing", s.listening() == 0)
	s.Everlook.journey.set_enabled(true)
	check("it listens once the player says yes", s.listening() == 8)
	s.Everlook.journey.note("met", 823)
	check("journey records once the player says yes", #s.rows() == 1)
	s.Everlook.journey.set_enabled(false)
	check("it stops listening when the player says no", s.listening() == 0)

	-- Turning it on notes the zone the character stands in, and so does each login once it is on.
	s = load()
	s.Everlook.journey.set_enabled(true)
	check("turning the journey on notes the zone the character is in", (function()
		local zone_rows = s.rows()
		return #zone_rows == 1 and zone_rows[1][2] == 5 and zone_rows[1][3] == 1411
	end)())
	s = load({ journey = { enabled = true } })
	check("a saved yes is not listening until the player is in the world", s.listening() == 0)
	s.Everlook.journey.start()
	check("starting a session with a saved yes listens and notes the zone", s.listening() == 8 and #s.rows() == 1 and s.woken() >= 1)

	-- A row holds its sequence, kind, id, map, level and time.
	s = on()
	s.world.map = 1411
	s.Everlook.journey.note("met", 823)
	s.Everlook.journey.note("met", 823)
	s.Everlook.journey.note("met", 824)
	s.Everlook.journey.note("zone", 1411)
	s.Everlook.journey.note("zone", 1411)
	local rows = s.rows()
	check("a creature or zone met again is not a new row", #rows == 3)
	check("a row holds its sequence, kind, id, map, level and time", rows[1][1] == 1 and rows[1][2] == 4 and rows[1][3] == 823 and rows[1][4] == 1411 and rows[1][5] == 38 and rows[1][6] == 1760000000)
	check("the sequence only rises", rows[2][1] == 2 and rows[3][1] == 3 and select(2, s.character()).seq == 3)
	check("a zone is kind 5", rows[3][2] == 5 and rows[3][3] == 1411)

	-- A row writes 0 where the game did not say, since a Lua array cannot hold nil.
	s = on()
	s.world.map = nil
	s.world.level = nil
	s.Everlook.journey.note("met", 900)
	check("an unknown map and level are 0", (function() local row = s.rows()[1]; return row[4] == 0 and row[5] == 0 end)())

	-- Rows carry the server's time, not the machine's clock.
	s = on()
	s.world.server_now = 1760000000
	s.world.now = 1760000000 + 3 * 86400
	s.Everlook.journey.note("met", 77)
	check("a row is stamped with the server time, so a wrong PC clock does not get a chunk refused", s.rows()[1][6] == 1760000000)

	-- A quest is taken, completed or given up, and may be taken again after it is given up.
	s = on()
	s.fire("QUEST_ACCEPTED", 1, 783)
	s.fire("QUEST_ACCEPTED", 1, 783)
	s.fire("QUEST_ACCEPTED", 783)
	local _, state = s.character()
	check("QUEST_ACCEPTED records the quest once while it is held, with a quest id alone or after a log index", #s.rows() == 1 and state.counts.started == 1)
	s.fire("QUEST_REMOVED", 783)
	s.settle()
	check("QUEST_REMOVED for a held quest is giving it up", #s.rows() == 2 and s.rows()[2][2] == 3 and state.counts.started == 0 and state.counts.abandoned == 1)
	s.fire("QUEST_REMOVED", 783)
	s.settle()
	check("giving up a quest that is not held records nothing", #s.rows() == 2)
	s.fire("QUEST_ACCEPTED", 783)
	check("a quest taken again after it was given up is in progress again, by the same rule as the site", #s.rows() == 3 and state.counts.started == 1 and state.counts.abandoned == 0)
	s.fire("QUEST_TURNED_IN", 783)
	s.fire("QUEST_REMOVED", 783)
	s.settle()
	check("turning a quest in completes it, and the removal after it is not giving up", #s.rows() == 4 and s.rows()[4][2] == 2 and state.counts.completed == 1 and state.counts.started == 0)
	s.fire("QUEST_TURNED_IN", 783)
	check("completing the same quest again records nothing", #s.rows() == 4)
	s.fire("QUEST_ACCEPTED", 783)
	s.fire("QUEST_REMOVED", 783)
	s.settle()
	check("a completed quest stays completed when it is taken and given up again", state.counts.completed == 1 and state.counts.started == 0 and state.counts.abandoned == 0)

	s = on()
	s.fire("QUEST_ACCEPTED", 6)
	s.world.now = s.world.now + 60
	s.fire("QUEST_TURNED_IN", 6)
	s.world.now = s.world.now + 600
	s.fire("QUEST_REMOVED", 6)
	s.settle()
	check("a removal long after a turn-in is not giving up either", #s.rows() == 2)
	s = on()
	s.fire("QUEST_ACCEPTED", 7)
	s.fire("QUEST_REMOVED", 7)
	s.fire("QUEST_TURNED_IN", 7)
	s.settle()
	check("a removal that arrives before its turn-in is not giving up", #s.rows() == 2 and s.rows()[2][2] == 2)

	-- Zones come from the game's own zone events.
	s = on()
	s.world.map = 1412
	s.fire("ZONE_CHANGED_NEW_AREA")
	s.fire("ZONE_CHANGED_NEW_AREA")
	rows = s.rows()
	check("ZONE_CHANGED_NEW_AREA records the zone the character stands in", #rows == 1 and rows[1][2] == 5 and rows[1][3] == 1412 and rows[1][4] == 1412)
	s.world.map = nil
	s.fire("ZONE_CHANGED_NEW_AREA")
	check("a zone the game cannot name records nothing", #s.rows() == 1)

	-- Ids that are not ids are ignored.
	s = on()
	for _, bad in ipairs({ 0, -4, 2 ^ 31, "823" }) do s.Everlook.journey.note("met", bad) end
	s.Everlook.journey.note("met", nil)
	s.Everlook.journey.note("unknown_kind", 823)
	check("an id that is not a positive integer is ignored, and so is a kind that does not exist", #s.chunks() == 0 and select(2, s.character()) == nil)

	-- The caps: creatures stop first, then everything.
	s = on()
	s.Everlook.journey.note("met", 1)
	local token
	token, state = s.character()
	state.met_rows, state.rows = 20000, 20000
	s.Everlook.journey.note("met", 2)
	check("past 20,000 rows no more creatures are added", #s.rows() == 1)
	s.fire("QUEST_ACCEPTED", 9)
	check("quests and zones still are", #s.rows() == 2)
	state.rows = 25000
	s.fire("QUEST_ACCEPTED", 10)
	check("past 25,000 rows nothing is", #s.rows() == 2)

	-- Sharding by sequence: a chunk is full at the end of its range, packed on the spot.
	s = on()
	for id = 1, 499 do s.Everlook.journey.note("met", id) end
	check("a chunk is not packed before it is full", #s.chunks() == 0)
	s.Everlook.journey.note("met", 500)
	check("the 500th row packs the chunk, and wakes the signer", #s.chunks() == 1 and s.chunks()[1].from == 1 and s.chunks()[1].to == 500 and s.woken() >= 1)
	for id = 501, 1200 do s.Everlook.journey.note("met", id) end
	check("the second chunk fills at 1000", #s.chunks() == 2 and s.chunks()[2].from == 501 and s.chunks()[2].to == 1000)
	rows = s.rows()
	local chunks = s.chunks()
	token = s.character()
	check("at logout the rows left are packed into the open chunk", #chunks == 3 and chunks[3].from == 1001 and chunks[3].to == 1200 and #rows == 1200)
	local document = s.decode(chunks[1])
	check("a chunk carries version 1, the token, the profile and at most 500 rows", document.v == 1 and document.t == token and #document.r == 500 and document.r[1][1] == 1 and document.r[500][1] == 500)
	check("the profile holds the name, realm, class, race, faction and level", document.p.name == "Thrall" and document.p.realm == "Nordanaar" and document.p.class == 7 and document.p.race == "Orc" and document.p.faction == "Horde" and document.p.level == 38)
	check("the token is 16 hex characters and not the GUID", type(token) == "string" and token:match("^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil and token ~= GUID)

	-- The open chunk is packed in place, so a session adds rows to it and not a chunk of its own.
	local db = {}
	s = on(db)
	for id = 1, 100 do s.Everlook.journey.note("met", id) end
	s.fire("PLAYER_LOGOUT")
	check("a short session leaves one chunk", #s.chunks() == 1 and s.chunks()[1].from == 1 and s.chunks()[1].to == 100)
	local first_payload = s.chunks()[1].payload
	s = load(db)
	s.world.map = nil
	s.Everlook.journey.start()
	s.Everlook.journey.note("met", 5)
	for id = 101, 150 do s.Everlook.journey.note("met", id) end
	rows = s.rows()
	check("a creature met in an earlier session is not a new row", #rows == 150)
	check("the next session grows the same chunk instead of adding one", #s.chunks() == 1 and s.chunks()[1].from == 1 and s.chunks()[1].to == 150 and s.chunks()[1].payload ~= first_payload)
	check("and its signature covers what is there now", s.chunks()[1].signature == "secret|j1;" .. s.character() .. ";1;150;" .. s.chunks()[1].payload)

	-- The sequence goes on after the journey is turned off and on, and a chunk is full at the end of its range.
	s = on()
	for id = 1, 10 do s.Everlook.journey.note("met", id) end
	local _, kept = s.character()
	s.fire("PLAYER_LOGOUT")
	s.Everlook.journey.set_enabled(false)
	check("turning it off removes the chunks, the pages and the counts", s.db.journey.characters == nil and next(kept.pages) == nil and kept.counts.met == 0)
	check("and keeps the sequence, which the site has seen", kept.seq == 10)
	s.world.map = nil
	s.Everlook.journey.set_enabled(true)
	for id = 1, 600 do s.Everlook.journey.note("met", id) end
	s.fire("PLAYER_LOGOUT")
	chunks = s.chunks()
	check("the first chunk after it starts partway through its range and is full at the range end", #chunks == 2 and chunks[1].from == 11 and chunks[1].to == 500)
	check("and the next begins at the next range", chunks[2].from == 501 and chunks[2].to == 610)
	check("a creature met again after the wipe counts again, once", kept.counts.met == 600)
	s.Everlook.journey.set_enabled(false)
	s.Everlook.journey.set_enabled(true)
	s.fire("QUEST_ACCEPTED", 5)
	s.Everlook.journey.set_enabled(false)
	s.Everlook.journey.set_enabled(true)
	s.fire("QUEST_ACCEPTED", 5)
	check("the counts are wiped with the pages, so a quest is not counted twice", kept.counts.started == 1)

	-- Pages: what has been recorded is a few strings, read when touched, and never a big table.
	s = on()
	for id = 1, 3000 do s.Everlook.journey.note("met", id) end
	s.fire("PLAYER_LOGOUT")
	token, state = s.character()
	check("3,000 creatures are a handful of page strings, not thousands of entries", (function()
		local count = 0
		for key, value in pairs(state.pages) do
			count = count + 1
			if type(value) ~= "string" or value:sub(1, 2) ~= "j1" or not key:match("^m:%d+$") then return false end
		end
		return count == 3
	end)())
	check("nothing in the saved file grows with the ids", state.seen == nil and state.last == nil and state.pending == nil and entries(s.db.qol) < 40)
	check("the journey keeps its own pages, apart from the world data's", s.db.pages == nil and s.db.pageCounts == nil)

	-- Only a few pages are read at a time, and a page that goes is saved first.
	s = on()
	for page = 0, 11 do s.Everlook.journey.note("met", 1 + page * 1024) end
	check("at most 8 pages are read at a time", s.Everlook.journey.loaded() <= 8)
	s.Everlook.journey.note("met", 1)
	check("a page that was evicted is read back, so what it held is still remembered", #s.rows() == 12)

	-- Signing: strictly in order, a few blocks at a time, and only while there is something to sign.
	s = on()
	for id = 1, 1100 do s.Everlook.journey.note("met", id) end
	s.fire("PLAYER_LOGOUT")
	token = s.character()
	chunks = s.chunks()
	check("at logout every chunk is signed over its token, range and payload", #chunks == 3 and chunks[1].signature == "secret|j1;" .. token .. ";1;500;" .. chunks[1].payload and chunks[3].signature == "secret|j1;" .. token .. ";1001;1100;" .. chunks[3].payload)
	check("the signer is the account's", s.db.journey.signer == "0123456789abcdef" and s.db.journey.v == 1)
	check("with nothing left to sign the signer stops", s.step(0) == false)

	local function signed_prefix(list)
		local gap = false
		for _, chunk_row in ipairs(list) do
			if not chunk_row.signature then gap = true elseif gap then return false end
		end
		return true
	end
	s.world.secret, s.world.signer = "second-secret", "fedcba9876543210"
	check("a new token is noticed by the signer, which takes every signature away at once", s.step(0) == true and s.db.journey.signer == "fedcba9876543210")
	chunks = s.chunks()
	check("and signs the first chunk first", chunks[1].signature == "second-secret|j1;" .. token .. ";1;500;" .. chunks[1].payload and chunks[2].signature == nil and chunks[3].signature == nil)
	check("so what is signed is always an unbroken run from the start", signed_prefix(chunks))
	s.step(0)
	check("then the next", s.chunks()[2].signature ~= nil and s.chunks()[3].signature == nil and signed_prefix(s.chunks()))
	s.step(0)
	check("and the last, and then it rests", s.chunks()[3].signature ~= nil and s.step(0) == false)

	s.world.stream_steps = 3
	for _, chunk_row in ipairs(s.chunks()) do chunk_row.signature = nil end
	s.step(0)
	check("a chunk takes several steps, and is not signed until the last", s.chunks()[1].signature == nil)
	s.step(0)
	s.step(0)
	check("and is signed on the third", s.chunks()[1].signature ~= nil and s.chunks()[2].signature == nil)

	-- Without the account's token nothing can be signed, and the signer sleeps instead of spinning.
	s = on()
	s.world.signed = false
	for id = 1, 600 do s.Everlook.journey.note("met", id) end
	check("while there is no token the signer sleeps", s.step(0) == 10)
	s.fire("PLAYER_LOGOUT")
	check("the chunks wait, unsigned, and the app does not see them as ready", #s.chunks() == 2 and s.chunks()[1].signature == nil and s.chunks()[2].signature == nil)
	s.world.signed = true
	s.step(0)
	check("they are signed once there is one, in order", s.chunks()[1].signature ~= nil and s.chunks()[2].signature == nil)
	s = on()
	s.world.signed = false
	check("with nothing to sign and no token the signer rests", s.step(0) == false)

	-- The logout budget: a short one, and what is left is signed next session.
	s = on()
	for id = 1, 1500 do s.Everlook.journey.note("met", id) end
	s.world.tick = 60
	s.fire("PLAYER_LOGOUT")
	check("at logout only what fits in the budget is signed", s.chunks()[1].signature ~= nil and s.chunks()[2].signature ~= nil and s.chunks()[3].signature == nil)
	s.world.tick = 0
	s.step(0)
	check("and the rest is signed in the background", s.chunks()[3].signature ~= nil)

	-- Packing again drops the signature, since it no longer covers what is there.
	s = on()
	for id = 1, 100 do s.Everlook.journey.note("met", id) end
	s.fire("PLAYER_LOGOUT")
	local signed_before = s.chunks()[1].signature
	for id = 101, 110 do s.Everlook.journey.note("met", id) end
	s.fire("PLAYER_LOGOUT")
	check("a chunk packed again is signed again over what is in it", #s.chunks() == 1 and s.chunks()[1].signature ~= signed_before and s.chunks()[1].signature == "secret|j1;" .. s.character() .. ";1;110;" .. s.chunks()[1].payload)

	-- Nothing about the character leaves in the clear, and the GUID never leaves its own table.
	s = on()
	for id = 1, 50 do s.Everlook.journey.note("met", id) end
	s.fire("PLAYER_LOGOUT")
	check("no GUID is anywhere in the table the app reads", not contains(s.db.journey, GUID))
	check("no GUID is in anything that was encoded", not contains(blobs, GUID))
	check("the name and realm are only inside the packed chunks, never in the table the app reads", not contains(s.db.journey, "Thrall") and not contains(s.db.journey, "Nordanaar"))
	check("the GUID stays on this machine, outside the uploaded table", s.db.qol.journey.tokens[GUID] == s.character())

	-- Both ways of encoding work, and a client that cannot encode keeps nothing.
	s = on(nil, { raw = true })
	s.Everlook.journey.note("met", 1)
	check("without deflate a chunk and a page are written raw", #s.rows() == 1 and s.chunks()[1].payload:sub(1, 3) == "2r." and select(2, s.character()).pages["m:0"]:sub(1, 4) == "j1r.")
	s = on()
	s.Everlook.journey.note("met", 1)
	s.fire("PLAYER_LOGOUT")
	check("with deflate they are written deflated", s.chunks()[1].payload:sub(1, 3) == "2c." and select(2, s.character()).pages["m:0"]:sub(1, 4) == "j1c.")
	s = load(nil, { no_encoding = true })
	s.Everlook.journey.set_enabled(true)
	s.Everlook.journey.note("met", 1)
	check("a client that cannot encode records nothing", s.Everlook.journey.available() == false and #s.chunks() == 0 and select(2, s.character()) == nil)

	-- What the settings page shows.
	s = on()
	s.fire("QUEST_ACCEPTED", 1)
	s.fire("QUEST_ACCEPTED", 2)
	s.fire("QUEST_TURNED_IN", 2)
	s.Everlook.journey.note("met", 10)
	s.Everlook.journey.note("zone", 1411, 1411)
	local summary = s.Everlook.journey.summary()
	check("the summary counts quests, creatures and zones", summary.enabled and summary.available and summary.counts.completed == 1 and summary.counts.started == 1 and summary.counts.met == 1 and summary.counts.zones == 1 and summary.rows == 5)
	check("and says what is waiting to be packed and signed", summary.open == 5 and summary.token == true and summary.signed == 0 and summary.waiting == 0)
	s.fire("PLAYER_LOGOUT")
	summary = s.Everlook.journey.summary()
	check("after logout the open chunk is signed", summary.signed == 1 and summary.waiting == 0)
	s.world.signed = false
	check("and the summary says when there is no token", s.Everlook.journey.summary().token == false)
	check("a journey that is off has a summary too", load().Everlook.journey.summary().enabled == false)

	-- The page's words, from the summary.
	s = on()
	s.fire("QUEST_ACCEPTED", 1)
	s.Everlook.journey.note("met", 10)
	s.Everlook.journey.note("met", 11)
	local lines = s.Everlook.journey.lines(s.Everlook.journey.summary())
	check("the page says whose journey it is, and lists the counts", lines.status == "On for Thrall of Nordanaar." and lines.counts[2].label == "Quests in progress" and lines.counts[2].value == "1" and lines.counts[4].value == "2")
	check("it says how much is recorded and what is waiting to be signed", lines.recorded == "3 things recorded, without where you stood." and lines.signing[2] == "1 chunk is waiting to be signed, at logout and in the background.")
	check("and that it is signed with the token", lines.signing[#lines.signing] == "Signed with your Everlook token.")
	s.world.signed = false
	check("or that the token is missing", s.Everlook.journey.lines(s.Everlook.journey.summary()).signing[#s.Everlook.journey.lines(s.Everlook.journey.summary()).signing] == "Place the token in the Everlook app, and the journey is signed.")
	check("an off journey says how to turn it on", load().Everlook.journey.lines({ available = true, enabled = false }).status:find("Keep a journey", 1, true) ~= nil)
	check("a client that cannot encode says so", load().Everlook.journey.lines({ available = false }).status == "This game client cannot keep a journey.")

	-- Two characters on one account are two tokens.
	s = on()
	s.Everlook.journey.note("met", 1)
	local first_token = s.character()
	s.world.guid = "Player-1234-0FEDCBA0"
	s.world.name = "Jaina"
	s.Everlook.journey.note("met", 1)
	local tokens = s.db.qol.journey.tokens
	check("each character has its own token and its own pages", tokens[GUID] == first_token and tokens["Player-1234-0FEDCBA0"] ~= nil and tokens["Player-1234-0FEDCBA0"] ~= first_token)

	-- The question: asked after the world question, once, never over another dialog, and only the player's answer counts.
	s = load()
	s.world.asked = false
	s.Everlook.journey.start()
	check("the journey question waits for the world-data question to be answered", #s.shown == 0)
	s.pending[1]()
	check("it is not asked while the world-data question is open either", #s.shown == 0)
	s.world.asked = true
	s.world.blocked = "combat"
	s.pending[2]()
	check("it is not asked in combat", #s.shown == 0)
	s.world.blocked = nil
	s.pending[3]()
	check("it is asked at the next quiet moment", #s.shown == 1 and s.shown[1] == "EVERLOOK_JOURNEY")
	local dialog = s.env.StaticPopupDialogs.EVERLOOK_JOURNEY
	check("the question says a name is sent and who can see it", dialog.text:find("name, realm", 1, true) and dialog.text:find("members", 1, true))
	dialog.OnCancel(nil, nil, "override")
	check("a dialog something else closes is not an answer", s.Everlook.journey.enabled() == false and s.db.journey == nil)
	dialog.OnAccept()
	check("Accept turns the journey on", s.Everlook.journey.enabled() == true)
	s.Everlook.journey.set_enabled(false)
	dialog.OnCancel(nil, nil, "clicked")
	check("Escape and No turn it off for good", s.db.journey.enabled == false)
	s = load()
	s.Everlook.journey.set_enabled(false)
	s.Everlook.journey.start()
	check("it is never asked again once answered", #s.pending == 0 and #s.shown == 0)
	s = load(nil, { no_encoding = true })
	s.Everlook.journey.start()
	s.pending[1]()
	check("it is not asked on a client that could not keep the answer", #s.shown == 0)

	-- Areas: the game's own list of what the character has uncovered, recorded once ever, as kind 6.
	s = on()
	s.world.map = 1411
	s.world.spot = { x = 0.5, y = 0.5 }
	s.world.areas = { 17, 4 }
	s.fire("ZONE_CHANGED")
	s.fire("ZONE_CHANGED_INDOORS")
	rows = s.rows()
	check("a subzone change records the most specific area uncovered at the spot, once", #rows == 1 and rows[1][2] == 6 and rows[1][3] == 17 and rows[1][4] == 1411)
	s.world.areas = { 18 }
	s.fire("ZONE_CHANGED")
	check("another area is another row, and both are counted", #s.rows() == 2 and select(2, s.character()).counts.areas == 2)
	s.world.areas = nil
	s.fire("ZONE_CHANGED")
	s.world.areas = {}
	s.fire("ZONE_CHANGED")
	s.world.areas = { 0 }
	s.fire("ZONE_CHANGED")
	check("a spot with no area, or an id that is no id, records nothing", #s.rows() == 2)
	s = on()
	s.world.map = 1411
	s.world.spot = { x = 0.5, y = 0.5 }
	s.world.areas = { 17 }
	s.fire("PLAYER_ENTERING_WORLD")
	check("entering the world notes the area as well as the zone", (function()
		local entered = s.rows()
		return #entered == 2 and entered[1][2] == 5 and entered[2][2] == 6
	end)())
	s = load({ journey = { enabled = true } })
	s.world.spot = { x = 0.5, y = 0.5 }
	s.world.areas = { 17 }
	s.Everlook.journey.start()
	check("starting a session notes the area the character stands in", #s.rows() == 2)

	-- Positions are their own yes. Without it a row is the six numbers it always was.
	s = on()
	s.world.map = 1411
	s.world.spot = { x = 0.4731, y = 0.6004 }
	s.Everlook.journey.note("met", 823)
	check("without a yes to positions a row carries no spot", #s.rows()[1] == 6 and s.Everlook.journey.positions() == false)
	s = on()
	s.world.map = 1411
	s.world.spot = { x = 0.4731, y = 0.6004 }
	s.Everlook.journey.set_positions(true)
	s.Everlook.journey.note("met", 823)
	check("with a yes a row ends with x and y in tenths of a percent of the map", (function()
		local row = s.rows()[1]
		return #row == 8 and row[7] == 473 and row[8] == 600
	end)())
	s.world.spot = nil
	s.Everlook.journey.note("met", 824)
	s.world.spot = { x = 1.4, y = 0.5 }
	s.Everlook.journey.note("met", 825)
	s.world.spot = { x = 0, y = 0.5 }
	s.Everlook.journey.note("met", 826)
	check("where the game gives no spot, or one off the map, the row says 0 and 0 together", (function()
		local rows_now = s.rows()
		return #rows_now == 4 and rows_now[2][7] == 0 and rows_now[2][8] == 0 and rows_now[3][7] == 0 and rows_now[3][8] == 0 and rows_now[4][7] == 0 and rows_now[4][8] == 0
	end)())
	s.Everlook.journey.set_positions(false)
	s.world.spot = { x = 0.5, y = 0.5 }
	s.Everlook.journey.note("met", 827)
	check("turning it off stops new spots and keeps the rows already written", (function()
		local rows_now = s.rows()
		return #rows_now == 5 and #rows_now[5] == 6 and rows_now[1][7] == 473
	end)())

	-- The question about positions: asked once after the journey is on, to a new yes and to an old one.
	s = load({ journey = { enabled = true } })
	s.Everlook.journey.start()
	check("a player who said yes to the journey before positions existed is asked about them", #s.pending == 1)
	s.pending[1]()
	check("it is the positions dialog, and says where on the map and who sees it", #s.shown == 1 and s.shown[1] == "EVERLOOK_JOURNEY_POSITIONS" and s.env.StaticPopupDialogs.EVERLOOK_JOURNEY_POSITIONS.text:find("where on the map", 1, true) and s.env.StaticPopupDialogs.EVERLOOK_JOURNEY_POSITIONS.text:find("whoever you let see", 1, true))
	local positions_dialog = s.env.StaticPopupDialogs.EVERLOOK_JOURNEY_POSITIONS
	positions_dialog.OnCancel(nil, nil, "override")
	check("a dialog something else closes is not an answer", s.Everlook.journey.positions_asked() == false)
	positions_dialog.OnAccept()
	check("Accept turns positions on", s.Everlook.journey.positions() == true and s.Everlook.journey.positions_asked() == true)
	positions_dialog.OnCancel(nil, nil, "clicked")
	check("No turns them off for good", s.db.journey.positions == false and s.Everlook.journey.positions_asked() == true)
	s = load({ journey = { enabled = true, positions = false } })
	s.Everlook.journey.start()
	check("it is never asked again once answered", #s.pending == 0)
	s = load({ journey = { enabled = false } })
	s.Everlook.journey.start()
	check("and not asked while the journey is off", #s.pending == 0)
	s = load()
	s.Everlook.journey.start()
	s.pending[1]()
	s.pending[1]()
	s.env.StaticPopupDialogs.EVERLOOK_JOURNEY.OnAccept()
	s.world.blocked = nil
	check("saying yes to the journey schedules the question about positions", #s.pending >= 1)
	s.settle()
	check("and it is asked", s.shown[#s.shown] == "EVERLOOK_JOURNEY_POSITIONS")
	s.world.blocked = true
	local blocked = load({ journey = { enabled = true } })
	blocked.world.blocked = true
	blocked.Everlook.journey.start()
	blocked.pending[1]()
	check("it is not asked over another dialog", #blocked.shown == 0)

	-- The page says whether spots are kept, and counts the areas.
	check("the journey page counts places discovered and says whether where you stood is kept", (function()
		local page_lines = s.Everlook.journey.lines({ available = true, enabled = true, positions = true, counts = { areas = 3 }, rows = 3, profile = { name = "Thrall", realm = "Nordanaar" } })
		local counted = false
		for _, entry in ipairs(page_lines.counts) do
			if entry.label == "Places discovered" and entry.value == "3" then counted = true end
		end
		return counted and page_lines.recorded:find("with where you stood", 1, true) ~= nil
	end)())
end
