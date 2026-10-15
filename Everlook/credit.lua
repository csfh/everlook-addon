local _, Everlook = ...

Everlook.credit = {}

-- Which creatures a kill objective counts a death of. When the progress of a "kill" objective moves within a few
-- seconds of a death the player surely caused (see drops.lua), that creature is credited for that objective, as one
-- count. Some objectives are completed by several creatures, which no table says. Progress that moves with no such
-- death, or that moved on the first look, credits nothing, and a death the client hides is never here at all.
local WINDOW = 3
local MONSTER = "monster"

local seen = {}
local row = { credits = 1 }

local function clock()
	return type(GetTime) == "function" and Everlook.public(GetTime()) or nil
end

-- Called when the quest log changes.
function Everlook.credit.update()
	if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo and C_QuestLog.GetQuestObjectives) then return end
	local kill, now = Everlook.drops and Everlook.drops.last_kill, clock()
	local recent = kill and not kill.used and now and kill.at and now - kill.at <= WINDOW
	local credited, live = false, {}
	for index = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(index)
		local quest_id = type(info) == "table" and not info.isHeader and Everlook.public(info.questID) or nil
		local objectives = type(quest_id) == "number" and C_QuestLog.GetQuestObjectives(quest_id) or nil
		if type(objectives) == "table" then
			live[quest_id] = true
			local counts = seen[quest_id]
			if not counts then counts = {}; seen[quest_id] = counts end
			for objective_index, objective in ipairs(objectives) do
				if type(objective) == "table" and Everlook.public(objective.type) == MONSTER then
					local fulfilled = Everlook.public(objective.numFulfilled)
					if type(fulfilled) == "number" then
						local before = counts[objective_index]
						counts[objective_index] = fulfilled
						if recent and before and fulfilled > before then
							row.questId, row.objective, row.npcId = quest_id, objective_index, kill.npcId
							Everlook.world.count("questCredits", row)
							credited = true
						end
					end
				end
			end
		end
	end
	if credited then kill.used = true end
	-- A quest that leaves the log is forgotten, so a quest taken again is looked at first, not credited.
	for quest_id in pairs(seen) do
		if not live[quest_id] then seen[quest_id] = nil end
	end
end
