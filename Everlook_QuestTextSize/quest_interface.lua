local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "quest_interface"
local originals = {}

-- QuestInfo.lua already sets the full description with SetText. The public 12.0.0 interface never
-- reads instantQuestText, so on its own this module only changes the text size. The "at once" option
-- sets that variable for a client whose interface does read it, and does nothing on one without it.
local INSTANT = "instantQuestText"
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

-- The value from before the option was turned on is kept in the saved variables, not in this session: after a
-- reload the game already holds what this set, and putting that back would never undo it.
local function update_instant(enabled)
	if type(GetCVar) ~= "function" or type(SetCVar) ~= "function" then return end
	EverlookDB = EverlookDB or {}
	if not (enabled and module.get(id, "instant_text")) then
		if EverlookDB.instantTextBefore ~= nil then
			SetCVar(INSTANT, EverlookDB.instantTextBefore)
			EverlookDB.instantTextBefore = nil
		end
		return
	end
	local current = GetCVar(INSTANT)
	if type(current) ~= "string" or (issecretvalue and issecretvalue(current)) then return end
	if EverlookDB.instantTextBefore == nil then EverlookDB.instantTextBefore = current end
	SetCVar(INSTANT, "1")
end

local function apply(enabled)
	update_fonts(enabled)
	update_instant(enabled)
end

module.register({
	addon = addon_name, page = "quests", order = 20,
	id = id, name = "Quest interface", description = "Sets the quest description, objectives, reward, and progress text to the size you choose, and waits while you are in combat. The quest tracker stays as it is, and turning this off puts the previous sizes back once you are out of combat.",
	options = {
		text_size = { name = "Quest text size", default = 16, min = 12, max = 24, step = 1, unit = " pt", description = "Sets the quest description, objectives, reward, and progress text to this many points, from 12 to 24. The quest tracker stays as it is, the change waits until combat ends, and this number does nothing until Quest interface is on." },
		instant_text = { name = "Show quest text at once", default = false, description = "Turns on the game's own setting that shows a quest's text whole instead of a few letters at a time, on a client that has it. On a client without it nothing happens, the text size stays on its own option, turning this off puts back the value the game had before this was turned on, and this does nothing until Quest interface is on." },
	},
	apply = apply, out_of_combat = true,
	events = { "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "ADDON_LOADED" },
	on_event = function() update_fonts(true) end,
})
