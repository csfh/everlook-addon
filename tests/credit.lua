-- Kill credit: progress that moves right after a death the player caused credits that creature, and nothing else does.
return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)
	local function load()
		local counted = {}
		local Everlook
		Everlook = {
			public = function(value) if value ~= "hidden" then return value end end,
			world = { count = function(bucket, row)
				local copy = {}
				for key, value in pairs(row) do copy[key] = value end
				counted[#counted + 1] = { bucket = bucket, row = copy }
			end },
			drops = {},
		}
		local state = { now = 100, progress = { 3 }, kind = "monster", log = { { questID = 176 } } }
		local env = setmetatable({
			GetTime = function() return state.now end,
			C_QuestLog = {
				GetNumQuestLogEntries = function() return #state.log end,
				GetInfo = function(index) return state.log[index] end,
				GetQuestObjectives = function(quest_id)
					local list = {}
					for index, fulfilled in ipairs(state.progress) do list[index] = { type = state.kind, numFulfilled = fulfilled } end
					return list
				end,
			},
		}, { __index = _G })
		env._G = env
		local chunk = assert(loadfile(source("credit")))
		setfenv(chunk, env)
		chunk("Everlook", Everlook)
		return Everlook, state, counted, env
	end

	local addon, state, counted = load()
	addon.credit.update()
	check("the first look at a quest credits nothing", #counted == 0)
	addon.drops.last_kill = { npcId = 448, at = 100, used = false }
	state.now, state.progress = 101, { 4 }
	addon.credit.update()
	check("progress right after the player's kill credits that creature for that objective", #counted == 1 and counted[1].bucket == "questCredits"
		and counted[1].row.questId == 176 and counted[1].row.objective == 1 and counted[1].row.npcId == 448 and counted[1].row.credits == 1)
	state.progress = { 5 }
	addon.credit.update()
	check("the same kill credits only once", #counted == 1)

	addon.drops.last_kill = { npcId = 449, at = 101, used = false }
	state.now, state.progress = 106, { 6 }
	addon.credit.update()
	check("progress more than three seconds after the kill credits nothing", #counted == 1)

	addon.drops.last_kill = { npcId = 450, at = 106, used = false }
	state.now, state.progress = 107, { 6 }
	addon.credit.update()
	check("progress that did not move credits nothing", #counted == 1)
	state.progress = { 5 }
	addon.credit.update()
	addon.drops.last_kill = { npcId = 451, at = 107, used = false }
	state.progress = { 5 }
	addon.credit.update()
	check("progress that fell credits nothing", #counted == 1)

	state.kind = "item"
	addon.drops.last_kill = { npcId = 452, at = 107, used = false }
	state.progress = { 6 }
	addon.credit.update()
	check("an objective that is not a kill credits nothing", #counted == 1)
	state.kind = "monster"

	addon.drops.last_kill = nil
	state.progress = { 7 }
	addon.credit.update()
	check("progress with no kill at all credits nothing", #counted == 1)

	-- A quest that left the log and came back is looked at first.
	local again, again_state, again_counted = load()
	again.credit.update()
	again_state.log = {}
	again.credit.update()
	again_state.log = { { questID = 176 } }
	again_state.progress = { 5 }
	again.drops.last_kill = { npcId = 448, at = 100, used = false }
	again_state.now = 101
	again.credit.update()
	check("a quest taken again is not credited on its first look", #again_counted == 0)

	local bare, _, bare_counted, bare_env = load()
	bare_env.C_QuestLog = nil
	bare.drops.last_kill = { npcId = 448, at = 100, used = false }
	local ok = pcall(bare.credit.update)
	check("a client without the quest log functions raises nothing and credits nothing", ok and #bare_counted == 0)
end
