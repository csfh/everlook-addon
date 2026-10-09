local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "swing_timers"
local names = { "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame" }
local previous = {}
local hooked = {}
local applying = false

-- UpdateSystemSettingScale applies the displayed percent with SetScale.
-- Apply that visual scale without writing shared Edit Mode settings or
-- setting maps: those writes taint the manager and its protected UI.
local function scale_setting()
	local settings = Enum and Enum.EditModeSwingTimerSetting
	if type(settings) ~= "table" or type(settings.Scale) ~= "number" then return end
	return settings.Scale
end

local function percent()
	local fraction = module.get(id, "scale")
	if type(fraction) ~= "number" then fraction = 0.5 end
	if fraction < 0.5 then fraction = 0.5 end
	if fraction > 1 then fraction = 1 end
	return math.floor(fraction * 100 + 0.5)
end

local function each_frame(callback)
	for index = 1, #names do
		local frame = _G[names[index]]
		if type(frame) == "table" then callback(frame) end
	end
end

local function writable(frame, setting)
	if type(frame.IsInitialized) ~= "function" or not frame:IsInitialized() then return false end
	if type(frame.HasSetting) ~= "function" or not frame:HasSetting(setting) then return false end
	if type(frame.GetScale) ~= "function" or type(frame.SetScale) ~= "function" then return false end
	return true
end

local function update_frame(frame, enabled)
	if applying or type(InCombatLockdown) ~= "function" or InCombatLockdown() then return end
	local setting = scale_setting()
	if not setting or not writable(frame, setting) then return end
	local current = frame:GetScale()
	if type(current) ~= "number" then return end
	local state = previous[frame]
	if not enabled then
		if not state then return end
		previous[frame] = nil
		if current ~= state.applied then return end
		applying = true
		frame:SetScale(state.value)
		applying = false
		return
	end
	-- A layout or slider change becomes the baseline to restore on disable.
	if not state then state = { value = current }; previous[frame] = state
	elseif current ~= state.applied then state.value = current end
	applying = true
	frame:SetScale(percent() / 100)
	state.applied = frame:GetScale()
	applying = false
end

local function hook_frame(frame)
	if hooked[frame] or type(hooksecurefunc) ~= "function" then return end
	if type(frame.UpdateSystem) ~= "function" or type(frame.UpdateSystemSettingScale) ~= "function" then return end
	local function refresh() update_frame(frame, module.enabled(id)) end
	hooksecurefunc(frame, "UpdateSystem", refresh)
	hooksecurefunc(frame, "UpdateSystemSettingScale", refresh)
	hooked[frame] = true
end

local function apply(enabled)
	each_frame(function(frame)
		hook_frame(frame)
		update_frame(frame, enabled)
	end)
	if not enabled then
		for frame in pairs(previous) do update_frame(frame, false) end
	end
end

module.register({
	addon = addon_name, page = "interface", order = 50,
	id = id,
	name = "Swing timers",
	description = "Sets the main hand, off hand, and ranged swing timers to the size on Timer scale, and leaves Edit Mode's saved size alone. The change waits until combat ends, a bar that is not initialized or has no scale setting is left alone, and turning this off puts back the size it last took over when the bar still shows this size.",
	options = {
		scale = { name = "Timer scale", default = 0.5, min = 0.5, max = 1, step = 0.1, percent = true, description = "Sets the main hand, off hand, and ranged bars from 50% to 100% of full size, in steps of 10%, and leaves Edit Mode's saved size alone. The change waits until combat ends, a bar that is not initialized or has no scale setting is left alone, and this number does nothing until Swing timers is on." },
	},
	apply = apply,
	out_of_combat = true,
	events = { "PLAYER_ENTERING_WORLD" }, on_event = function() apply(module.enabled(id)) end,
})

if CreateFrame then
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("ADDON_LOADED")
	watcher:SetScript("OnEvent", function(_, _, name)
		if name == "Blizzard_SwingTimer" then apply(module.enabled(id)) end
	end)
end
