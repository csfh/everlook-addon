-- Offer counts: a giver's window against the quests it could have held for this player.
return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)
	local function load()
		local counted = {}
		local Everlook
		Everlook = {
			world = { usable = function(value) return value ~= "hidden" end, count = function(bucket, row)
				local copy = {}
				for key, value in pairs(row) do copy[key] = value end
				counted[#counted + 1] = { bucket = bucket, row = copy }
			end },
			npcs = { creature_id = function(guid) return type(guid) == "string" and tonumber(guid:match("^Creature%-0%-1%-0%-2%-(%d+)")) or nil end },
		}
		local state = {
			now = 100, guid = "Creature-0-1-0-2-197-abc", level = 12, class = 8, race = 1,
			done = {}, on = {}, available = { { questID = 54 } },
			givers = { { quest = 54, level = 1, before = {} }, { quest = 176, level = 9, before = { 54 } }, { quest = 300, level = 30, before = {} } },
			loads = 0,
		}
		Everlook.data_pack = function() state.loads = state.loads + 1; return { givers = function(npc) if npc == 197 then return state.givers end end } end
		local env = setmetatable({
			GetTime = function() return state.now end,
			UnitGUID = function(unit) if unit == "npc" then return state.guid end end,
			UnitLevel = function() return state.level end,
			UnitClass = function() return "Mage", "MAGE", state.class end,
			UnitRace = function() return "Human", "Human", state.race end,
			C_GossipInfo = { GetAvailableQuests = function() return state.available end },
			C_QuestLog = {
				IsQuestFlaggedCompleted = function(id) return state.done[id] == true end,
				IsOnQuest = function(id) return state.on[id] == true end,
			},
		}, { __index = _G })
		env._G = env
		local chunk = assert(loadfile(source("offers")))
		setfenv(chunk, env)
		chunk("Everlook", Everlook)
		return Everlook, state, counted, env
	end

	local addon, state, counted = load()
	addon.offers.window()

	local by = {}
	for _, item in ipairs(counted) do by[item.row.questId] = item.row end
	check("a quest on offer is counted as opened and offered, with the class, race and level band", by[54] and by[54].opens == 1 and by[54].offered == 1
		and by[54].classId == 8 and by[54].raceId == 1 and by[54].band == 2 and counted[1].bucket == "offers")
	check("a quest whose first step is not done is not counted", by[176] == nil)
	check("a quest above the player's level is not counted", by[300] == nil)

	state.now, state.done = 200, { [54] = true }
	addon.offers.window()
	local second = {}
	for index = 2, #counted do second[counted[index].row.questId] = counted[index].row end
	check("with the first step done, a quest the window did not hold is counted as opened and not offered", second[176] and second[176].opens == 1 and second[176].offered == 0)
	check("a quest already done is not counted", second[54] == nil)

	check("a quest already in the log is not counted", (function()
		local a, s, c = load()
		s.on = { [54] = true }
		a.offers.window()
		return #c == 0
	end)())

	state.now = 210
	local before = #counted
	addon.offers.window()
	check("the same giver again within a minute is not counted again", #counted == before)
	state.now = 300
	addon.offers.window()
	check("and is counted after a minute", #counted > before)

	local function none(label, setup)
		local a, s, c, e = load()
		setup(a, s, e)
		a.offers.window()
		check(label, #c == 0)
	end
	none("a creature the pack does not know gives nothing to count", function(_, s) s.guid = "Creature-0-1-0-2-999-abc" end)
	none("a window with no creature counts nothing", function(_, s) s.guid = nil end)
	none("a hidden id counts nothing", function(_, s) s.guid = "hidden" end)
	none("a client that cannot say what is done counts nothing", function(_, _, e) e.C_QuestLog.IsQuestFlaggedCompleted = nil end)
	none("a class the client hides counts nothing", function(_, _, e) e.UnitClass = function() return "x", "y", "hidden" end end)
	none("a client without the offer list counts nothing", function(_, _, e) e.C_GossipInfo = nil end)
	none("no pack counts nothing", function(a) a.data_pack = function() return nil end end)
end
