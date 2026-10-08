local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "quest_levels"
local original
local hooked = false

Everlook.quest_levels = {}

function Everlook.quest_levels.decorate(title, level)
	if issecretvalue and issecretvalue(title) then
		return title
	end
	if type(title) ~= "string" or type(level) ~= "number" then
		return title
	end
	return "[" .. math.floor(level) .. "] " .. title
end

local function level_for(quest_id)
	local row = Everlook.world and Everlook.world.row and Everlook.world.row("quests", quest_id)
	if type(row) == "table" and type(row.level) == "number" then
		return row.level
	end
	if C_QuestLog and C_QuestLog.GetQuestDifficultyLevel then
		return C_QuestLog.GetQuestDifficultyLevel(quest_id)
	end
end

local function apply(enabled)
	if not C_QuestLog or type(C_QuestLog.GetTitleForQuestID) ~= "function" then
		return
	end
	if not enabled then
		if hooked and original then
			C_QuestLog.GetTitleForQuestID = original
			original = nil
			hooked = false
		end
		return
	end
	if hooked then
		return
	end
	original = C_QuestLog.GetTitleForQuestID
	C_QuestLog.GetTitleForQuestID = function(quest_id)
		local title = original(quest_id)
		if not module.enabled(id) then
			return title
		end
		return Everlook.quest_levels.decorate(title, level_for(quest_id))
	end
	hooked = true
end

module.register({
	addon = addon_name, page = "quests", order = 10,
	id = id,
	name = "Quest levels",
	description = "Puts the level in brackets in front of a quest title wherever the game asks for that quest by its id, using a level you have recorded when there is one and the game's own level otherwise. A title the client hides, a title already on screen, or a quest with no level stays as it is, nothing happens when the client has no such lookup, and turning this off puts the game's titles back.",
	apply = apply,
})
