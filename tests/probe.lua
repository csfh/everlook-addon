-- /everlook probe: it reads what exists, listens for deaths and keeps what an event carried by type only.
return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)
	local function load(extra)
		local said = {}
		local Everlook = { say = function(line) said[#said + 1] = line end }
		local env = setmetatable({ EverlookDB = {}, GetBuildInfo = function() return "1.60.1", "70374" end }, { __index = _G })
		env._G = env
		for key, value in pairs(extra or {}) do env[key] = value end
		local chunk = assert(loadfile(source("probe")))
		setfenv(chunk, env)
		chunk("Everlook", Everlook)
		return Everlook, env, said
	end

	local addon = load({ C_Map = { GetMapRectOnMap = function() end }, GetQuestLogRewardXP = function() return 40, 120 end,
		C_QuestLog = { IsQuestFlaggedCompleted = function() return false end } })
	local facts = table.concat(addon.probe.facts(), "\n")
	check("present functions are reported, absent ones too", facts:find("C_Map.GetMapRectOnMap: present", 1, true) and facts:find("CanLootUnit: missing", 1, true))
	check("a harmless call reports the types it returns", facts:find("IsQuestFlaggedCompleted(1): boolean false", 1, true) and facts:find("GetQuestLogRewardXP(1): number, number", 1, true))
	local plain = load({ issecretvalue = function(value) return value == "secret" end })
	check("an event is described by the type of what came with it, secret or not", plain.probe.describe("UNIT_DIED", "Creature-0-1") == "UNIT_DIED string"
		and plain.probe.describe("UNIT_DIED", "secret") == "UNIT_DIED secret" and plain.probe.describe("PARTY_KILL", nil) == "PARTY_KILL nil")

	local offered = load({ UnitLevel = function() return 12 end, C_GossipInfo = { GetAvailableQuests = function() return { { questID = 5, questLevel = 14 }, { questID = 6, questLevel = 9 } } end },
		C_QuestLog = { IsQuestFlaggedCompleted = function(id) return id == 6 end } })
	check("a giver's window is described by counts and levels, with no title or id", offered.probe.offers() == "offers: 2 available, highest level 14, player level 12, 1 of them flagged completed")
	check("a client with no offer list says so", load().probe.offers() == "offers: no list on this client")

	local handler, registered, unregistered, env_finish
	local running, env, said = load({
		CreateFrame = function() return {
			RegisterEvent = function(_, event) if event == "PARTY_KILL" then error("unknown event") end registered = (registered or 0) + 1 end,
			SetScript = function(_, _, fn) handler = fn end,
			UnregisterAllEvents = function() unregistered = true end,
		} end,
		C_Timer = { After = function(_, fn) env_finish = fn end },
	})
	running.probe.run()
	handler(nil, "UNIT_DIED", "Creature-0-1")
	handler(nil, "UNIT_DIED", "Creature-0-2")
	local report = table.concat(said, "\n")
	check("a refused event is said, an accepted one too", report:find("Register UNIT_DIED: accepted", 1, true) and report:find("Register PARTY_KILL: refused", 1, true))
	env_finish()
	check("the answer is saved with the types and counts, and the listener stops", unregistered and env.EverlookDB.probe.events[1] == "UNIT_DIED string x2" and env.EverlookDB.probe.build == "70374")
	check("the saved answer holds no GUID", not tostring(env.EverlookDB.probe.events[1]):find("Creature", 1, true))
end
