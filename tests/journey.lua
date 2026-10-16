-- The journey: when it records, what it keeps, and what it hands to the app.
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

	local function load(db)
		db = db or {}
		local Everlook = { say = function() end }
		local env = setmetatable({ EverlookDB = db }, { __index = _G })
		env._G = env
		local world = { guid = GUID, name = "Thrall", realm = "Nordanaar", class = 7, race = "Orc", faction = "Horde", level = 38, map = 1411, now = 1760000000, signed = true, asked = true, blocked = nil }
		local frames, pending, serialized, shown = {}, {}, {}, {}
		env.UnitGUID = function() return world.guid end
		env.UnitName = function() return world.name end
		env.GetRealmName = function() return world.realm end
		env.UnitClass = function() return "Shaman", "SHAMAN", world.class end
		env.UnitRace = function() return "Orc", world.race end
		env.UnitFactionGroup = function() return world.faction end
		env.UnitLevel = function() return world.level end
		env.C_Map = { GetBestMapForUnit = function() return world.map end }
		env.time = function() return world.now end
		env.GetTime = function() return world.now end
		env.CreateFrame = function()
			local frame = { events = {} }
			function frame:RegisterEvent(event) self.events[event] = true end
			function frame:UnregisterEvent(event) self.events[event] = nil end
			function frame:SetScript(_, fn) self.script = fn end
			frames[#frames + 1] = frame
			return frame
		end
		env.C_Timer = { After = function(_, fn) pending[#pending + 1] = fn end }
		env.C_EncodingUtil = {
			SerializeCBOR = function(value)
				serialized[#serialized + 1] = deep_copy(value)
				return "cbor:" .. #serialized
			end,
			EncodeBase64 = function(text) return text end,
		}
		env.StaticPopupDialogs = {}
		env.StaticPopup_Show = function(which) shown[#shown + 1] = which end
		Everlook.config = {
			credentials = function()
				if world.signed then return "secret", "0123456789abcdef" end
			end,
			asked = function() return world.asked end,
		}
		Everlook.consent = { blocked = function() return world.blocked end }
		Everlook.hash = { hmac_sha256 = function(key, message) return key .. "|" .. message end }
		local chunk = assert(loadfile(source("journey")))
		setfenv(chunk, env)
		chunk("Everlook", Everlook)
		local session = { Everlook = Everlook, db = db, world = world, env = env, pending = pending, serialized = serialized, shown = shown, frames = frames }
		function session.fire(event, ...)
			for _, frame in ipairs(frames) do
				if frame.events[event] and frame.script then frame.script(frame, event, ...) end
			end
		end
		function session.decode(chunk_row)
			local at = tonumber(chunk_row.payload:match("^2r%.cbor:(%d+)$"))
			return at and serialized[at]
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
		return session
	end

	-- A journey that is on, standing nowhere, so turning it on notes no zone of its own.
	local function on()
		local s = load()
		local map = s.world.map
		s.world.map = nil
		s.Everlook.journey.set_enabled(true)
		s.world.map = map
		return s
	end

	local function listening(session)
		local count = 0
		for _, frame in ipairs(session.frames) do
			for _ in pairs(frame.events) do count = count + 1 end
		end
		return count
	end

	-- A removed quest is decided a moment later, so a turn-in that arrives just after it still counts as completing.
	local function settle(session)
		local waiting = session.pending
		for index = 1, #waiting do waiting[index]() end
		for index = #waiting, 1, -1 do waiting[index] = nil end
	end

	-- The gate: nothing is recorded until the player has said yes to the journey.
	local s = load()
	s.world.map = nil
	s.Everlook.journey.note("met", 823)
	s.fire("QUEST_ACCEPTED", 1, 783)
	check("journey records nothing before the player says yes", s.db.qol == nil and s.db.journey == nil)
	check("and listens to nothing", listening(s) == 0)
	s.Everlook.journey.set_enabled(false)
	s.Everlook.journey.note("met", 823)
	check("journey records nothing after the player says no", select(2, s.character()) == nil or #select(2, s.character()).pending == 0)
	check("and still listens to nothing", listening(s) == 0)
	s.Everlook.journey.set_enabled(true)
	check("it listens once the player says yes", listening(s) == 6)
	s.Everlook.journey.note("met", 823)
	local _, state = s.character()
	check("journey records once the player says yes", state and #state.pending == 1)
	s.Everlook.journey.set_enabled(false)
	check("it stops listening when the player says no", listening(s) == 0)

	-- Turning it on notes the zone the character stands in, and so does each login once it is on.
	s = load()
	s.Everlook.journey.set_enabled(true)
	_, state = s.character()
	check("turning the journey on notes the zone the character is in", state and #state.pending == 1 and state.pending[1][2] == 5 and state.pending[1][3] == 1411)
	s = load({ journey = { enabled = true } })
	check("a saved yes is not listening until the player is in the world", listening(s) == 0)
	s.Everlook.journey.start()
	_, state = s.character()
	check("starting a session with a saved yes listens and notes the zone", listening(s) == 6 and state and #state.pending == 1 and state.pending[1][3] == 1411)

	-- A creature or zone counts once, however often it is seen.
	s = on()
	s.Everlook.journey.note("met", 823)
	s.Everlook.journey.note("met", 823)
	s.Everlook.journey.note("met", 824)
	s.Everlook.journey.note("zone", 1411)
	s.Everlook.journey.note("zone", 1411)
	_, state = s.character()
	check("a creature met twice is one row", #state.pending == 3)
	check("a row holds its sequence, kind, id, map, level and time", (function()
		local row = state.pending[1]
		return row[1] == 1 and row[2] == 4 and row[3] == 823 and row[4] == 1411 and row[5] == 38 and row[6] == 1760000000
	end)())
	check("the sequence only rises", state.pending[2][1] == 2 and state.pending[3][1] == 3 and state.seq == 3)
	check("a zone is kind 5", state.pending[3][2] == 5 and state.pending[3][3] == 1411)

	-- A row writes 0 where the game did not say, since a Lua array cannot hold nil.
	s = on()
	s.world.map = nil
	s.world.level = nil
	s.Everlook.journey.note("met", 900)
	_, state = s.character()
	check("an unknown map and level are 0", state.pending[1][4] == 0 and state.pending[1][5] == 0)

	-- A quest is taken, completed or given up, and may be taken again after it is given up.
	s = on()
	s.fire("QUEST_ACCEPTED", 1, 783)
	s.fire("QUEST_ACCEPTED", 1, 783)
	_, state = s.character()
	check("QUEST_ACCEPTED records the quest id, once while it is held", #state.pending == 1 and state.pending[1][2] == 1 and state.pending[1][3] == 783)
	s.fire("QUEST_ACCEPTED", 783)
	check("a mainline QUEST_ACCEPTED with only the quest id works too", #state.pending == 1)
	s.fire("QUEST_REMOVED", 783)
	settle(s)
	check("QUEST_REMOVED for a held quest is giving it up", #state.pending == 2 and state.pending[2][2] == 3 and state.pending[2][3] == 783)
	s.fire("QUEST_REMOVED", 783)
	settle(s)
	check("giving up a quest that is not held records nothing", #state.pending == 2)
	s.fire("QUEST_ACCEPTED", 783)
	check("a quest taken again after it was given up is recorded again", #state.pending == 3 and state.pending[3][2] == 1)

	s = on()
	s.fire("QUEST_ACCEPTED", 5)
	s.fire("QUEST_TURNED_IN", 5)
	s.fire("QUEST_REMOVED", 5)
	settle(s)
	_, state = s.character()
	check("turning a quest in is completing it, and the removal after it is not giving up", #state.pending == 2 and state.pending[2][2] == 2 and state.pending[2][3] == 5)
	s.fire("QUEST_TURNED_IN", 5)
	check("completing the same quest again records nothing", #state.pending == 2)

	s = on()
	s.fire("QUEST_ACCEPTED", 6)
	s.world.now = s.world.now + 60
	s.fire("QUEST_TURNED_IN", 6)
	s.world.now = s.world.now + 600
	s.fire("QUEST_REMOVED", 6)
	settle(s)
	_, state = s.character()
	check("a removal long after a turn-in is not giving up either, since the quest was completed", #state.pending == 2)

	s = on()
	s.fire("QUEST_ACCEPTED", 7)
	s.fire("QUEST_REMOVED", 7)
	s.fire("QUEST_TURNED_IN", 7)
	settle(s)
	_, state = s.character()
	check("a removal that arrives before its turn-in is not giving up", #state.pending == 2 and state.pending[2][2] == 2)

	-- Zones come from the game's own zone events.
	s = on()
	s.world.map = 1412
	s.fire("ZONE_CHANGED_NEW_AREA")
	s.fire("ZONE_CHANGED_NEW_AREA")
	_, state = s.character()
	check("ZONE_CHANGED_NEW_AREA records the zone the character stands in", #state.pending == 1 and state.pending[1][2] == 5 and state.pending[1][3] == 1412 and state.pending[1][4] == 1412)
	s.world.map = nil
	s.fire("ZONE_CHANGED_NEW_AREA")
	check("a zone the game cannot name records nothing", #state.pending == 1)

	-- Ids that are not ids are ignored.
	s = on()
	s.Everlook.journey.note("met", 0)
	s.Everlook.journey.note("met", -4)
	s.Everlook.journey.note("met", 2 ^ 31)
	s.Everlook.journey.note("met", "823")
	s.Everlook.journey.note("met", nil)
	s.Everlook.journey.note("unknown_kind", 823)
	check("an id that is not a positive integer is ignored, and so is a kind that does not exist", select(2, s.character()) == nil or #select(2, s.character()).pending == 0)

	-- The caps: creatures stop first, then everything.
	s = on()
	s.Everlook.journey.note("met", 1)
	token, state = s.character()
	state.met = 20000
	state.rows = 20000
	s.Everlook.journey.note("met", 2)
	check("past 20,000 rows no more creatures are added", #state.pending == 1)
	s.fire("QUEST_ACCEPTED", 9)
	check("quests and zones still are", #state.pending == 2)
	state.rows = 25000
	s.fire("QUEST_ACCEPTED", 10)
	check("past 25,000 rows nothing is", #state.pending == 2)

	-- Sealing: at logout the pending rows become signed chunks of at most 500.
	s = on()
	for id = 1, 1200 do s.Everlook.journey.note("met", id) end
	token, state = s.character()
	check("the token is 16 hex characters and not the GUID", type(token) == "string" and token:match("^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil and token ~= GUID)
	s.fire("PLAYER_LOGOUT")
	local chunks = s.chunks()
	check("1,200 rows seal into three chunks", #chunks == 3 and #state.pending == 0)
	check("a chunk says its first and last sequence", chunks[1].from == 1 and chunks[1].to == 500 and chunks[2].from == 501 and chunks[2].to == 1000 and chunks[3].from == 1001 and chunks[3].to == 1200)
	local document = s.decode(chunks[1])
	check("a chunk carries version 1, the token, the profile and its rows", document and document.v == 1 and document.t == token and #document.r == 500 and document.r[1][1] == 1 and document.r[500][1] == 500)
	check("the profile holds the name, realm, class, race, faction and level", document.p.name == "Thrall" and document.p.realm == "Nordanaar" and document.p.class == 7 and document.p.race == "Orc" and document.p.faction == "Horde" and document.p.level == 38)
	check("a chunk is signed over the token, range and payload", chunks[1].signature == "secret|j1;" .. token .. ";1;500;" .. chunks[1].payload)
	check("the signer is the account's", s.db.journey.signer == "0123456789abcdef" and s.db.journey.v == 1)

	-- No GUID, name or realm outside the signed payload, and no GUID anywhere that goes to the app.
	check("no GUID is anywhere in the table the app reads", not contains(s.db.journey, GUID))
	check("no GUID is in what was signed", not contains(s.serialized, GUID))
	check("the name and realm are only inside the signed payload, never in the table the app reads", not contains(s.db.journey, "Thrall") and not contains(s.db.journey, "Nordanaar"))
	check("the GUID stays on this machine, outside the uploaded table", s.db.qol.journey.tokens[GUID] == token)

	-- Without a token from the app nothing can be signed, so nothing is sealed and nothing is lost.
	s = on()
	s.world.signed = false
	s.Everlook.journey.note("met", 1)
	s.fire("PLAYER_LOGOUT")
	token, state = s.character()
	check("rows wait while the account has no signing token", #state.pending == 1 and #s.chunks() == 0)
	s.world.signed = true
	s.Everlook.journey.note("met", 2)
	s.fire("PLAYER_LOGOUT")
	check("and are sealed once it has one", #state.pending == 0 and #s.chunks() == 1 and s.chunks()[1].from == 1 and s.chunks()[1].to == 2)

	-- A later session seals a new chunk after the old ones, and the sequence goes on from where it was.
	s.Everlook.journey.note("met", 3)
	s.fire("PLAYER_LOGOUT")
	check("a new session adds a chunk, and the sequence continues", #s.chunks() == 2 and s.chunks()[2].from == 3 and s.chunks()[2].to == 3)
	local seen_again = #state.pending
	s.Everlook.journey.note("met", 3)
	check("what an earlier session recorded is not recorded again", #state.pending == seen_again)

	-- Two characters on one account are two tokens.
	s = on()
	s.Everlook.journey.note("met", 1)
	local first_token = s.character()
	s.world.guid = "Player-1234-0FEDCBA0"
	s.world.name = "Jaina"
	s.Everlook.journey.note("met", 1)
	local tokens = s.db.qol.journey.tokens
	check("each character has its own token and its own rows", tokens[GUID] == first_token and tokens["Player-1234-0FEDCBA0"] ~= nil and tokens["Player-1234-0FEDCBA0"] ~= first_token)

	-- Turning it off stops recording and removes what has not gone to the app, but the sequence is never reset.
	s = on()
	s.Everlook.journey.note("met", 1)
	s.Everlook.journey.note("met", 2)
	s.fire("PLAYER_LOGOUT")
	s.Everlook.journey.note("met", 3)
	token, state = s.character()
	s.Everlook.journey.set_enabled(false)
	check("turning the journey off removes chunks waiting for the app and rows waiting to be sealed", (s.db.journey.characters == nil or next(s.db.journey.characters) == nil) and #state.pending == 0)
	check("it records that the player said no", s.db.journey.enabled == false and s.Everlook.journey.enabled() == false)
	s.Everlook.journey.set_enabled(true)
	s.Everlook.journey.note("met", 4)
	check("turned on again, the sequence goes on and never repeats a number the site has seen", state.pending[1][1] == 4)

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
end
