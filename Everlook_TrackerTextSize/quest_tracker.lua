local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "quest_tracker"
local previous = {}
local hooked = {}
local applying = false

-- SetTextSize updates the objective and header fonts without writing the
-- shared Edit Mode layout. Headers use two points more than objective lines.
local function text_setting()
	local settings = Enum and Enum.EditModeObjectiveTrackerSetting
	if type(settings) ~= "table" or type(settings.TextSize) ~= "number" then return end
	return settings.TextSize
end

local function text_size()
	local value = module.get(id, "text_size")
	if type(value) ~= "number" then value = 16 end
	if value < 12 then value = 12 end
	if value > 20 then value = 20 end
	return math.floor(value)
end

local function writable(frame, setting)
	if type(ObjectiveTrackerManager) ~= "table" or type(ObjectiveTrackerManager.SetTextSize) ~= "function" then return false end
	if type(frame) ~= "table" then return false end
	if type(frame.IsInitialized) ~= "function" or not frame:IsInitialized() then return false end
	if type(frame.HasSetting) ~= "function" or not frame:HasSetting(setting) then return false end
	local kind = type(ObjectiveTrackerLineFont)
	if kind ~= "table" and kind ~= "userdata" then return false end
	if type(ObjectiveTrackerLineFont.GetFont) ~= "function" then return false end
	return true
end

local function update_frame(frame, enabled)
	if applying or type(InCombatLockdown) ~= "function" or InCombatLockdown() then return end
	local setting = text_setting()
	if not setting or not writable(frame, setting) then return end
	local _, current = ObjectiveTrackerLineFont:GetFont()
	if type(current) ~= "number" then return end
	local state = previous[frame]
	if not enabled then
		if not state then return end
		previous[frame] = nil
		if current ~= state.applied then return end
		applying = true
		ObjectiveTrackerManager:SetTextSize(state.value)
		applying = false
		return
	end
	-- SetTextSize cannot restore a font size outside its supported range.
	if current < 12 or current > 20 then return end
	if not state then state = { value = current }; previous[frame] = state
	elseif current ~= state.applied then state.value = current end
	state.applied = text_size()
	applying = true
	ObjectiveTrackerManager:SetTextSize(state.applied)
	applying = false
end

local function hook_frame(frame)
	if type(frame) ~= "table" or hooked[frame] or type(hooksecurefunc) ~= "function" then return end
	if type(frame.UpdateSystem) ~= "function" or type(frame.UpdateSystemSettingTextSize) ~= "function" then return end
	local function refresh() update_frame(frame, module.enabled(id)) end
	hooksecurefunc(frame, "UpdateSystem", refresh)
	hooksecurefunc(frame, "UpdateSystemSettingTextSize", refresh)
	hooked[frame] = true
end

local function apply(enabled)
	local frame = ObjectiveTrackerFrame
	hook_frame(frame)
	update_frame(frame, enabled)
	if not enabled then
		for owned in pairs(previous) do update_frame(owned, false) end
	end
end

module.register({
	addon = addon_name, page = "quests", order = 30,
	id = id,
	name = "Quest tracker",
	description = "Sets the quest tracker objectives to the size on Objective size, from 12 to 20, and keeps the headers two points larger. The change waits until combat ends, the Edit Mode layout stays as it is, a tracker that is missing, not initialized, has no text-size setting, or is already outside that range is left alone, the size does nothing until this is on, and turning this off puts back the size it last took over while the tracker still shows this size.",
	options = {
		text_size = { name = "Objective size", default = 16, min = 12, max = 20, step = 1, description = "Sets the quest tracker objective lines to this many points, from 12 to 20, and the headers stay two points larger. The change waits until combat ends, the Edit Mode layout stays as it is, a tracker that is missing, not initialized, has no text-size setting, or is already outside this size range is left alone, and this number does nothing until Quest tracker is on." },
	},
	apply = apply,
	out_of_combat = true,
	events = { "PLAYER_ENTERING_WORLD" },
	on_event = function() apply(module.enabled(id)) end,
})

if CreateFrame then
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("ADDON_LOADED")
	watcher:SetScript("OnEvent", function(_, _, name)
		if name == "Blizzard_ObjectiveTracker" then apply(module.enabled(id)) end
	end)
end
