local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "quest_interface"
local originals = {}

-- QuestInfo.lua already sets the full description with SetText. 12.0.0 never
-- reads instantQuestText, so this module only changes the text size.
local function update_fonts(enabled)
	if InCombatLockdown and InCombatLockdown() then return end
	for _, name in ipairs({ "QuestInfoDescriptionText", "QuestInfoObjectivesText", "QuestInfoRewardText", "QuestProgressText" }) do
		local object = _G[name]
		if object and object.GetFont and object.SetFont then
			if enabled and not originals[object] then originals[object] = { object:GetFont() } end
			local original = originals[object]
			local path, _, flags = object:GetFont()
			if path and (enabled or original) then
				object:SetFont(path, enabled and module.get(id, "text_size") or original[2], flags)
				if not enabled then originals[object] = nil end
			end
		end
	end
end

local function apply(enabled)
	update_fonts(enabled)
end

module.register({
	addon = addon_name, page = "quests", order = 20,
	id = id, name = "Quest interface", description = "Sets the quest description, objectives, reward, and progress text to the size you choose, and waits while you are in combat. The quest tracker stays as it is, and turning this off puts the previous sizes back once you are out of combat.",
	options = {
		text_size = { name = "Quest text size", default = 16, min = 12, max = 24, step = 1, unit = " pt", description = "Sets the quest description, objectives, reward, and progress text to this many points, from 12 to 24. The quest tracker stays as it is, the change waits until combat ends, and this number does nothing until Quest interface is on." },
	},
	apply = apply, out_of_combat = true,
	events = { "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "ADDON_LOADED" },
	on_event = function() update_fonts(true) end,
})
