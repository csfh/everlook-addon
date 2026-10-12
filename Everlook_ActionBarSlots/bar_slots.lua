local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local layouts = Everlook.bar_layouts
local id = "action_bar_slots"

-- The game already has this setting: Always Show Buttons, per bar, in Edit Mode. A preset
-- layout cannot be changed, so this keeps a layout named Everlook Slots with it turned off on the
-- two bars above the main bar and switches to it. Everything goes through C_EditMode as
-- plain data. No Blizzard frame is called, hooked or written to.

-- The settings are one for the account, but the layout in use belongs to a character, and a
-- character layout exists for the one that made it. So what to switch back to is kept per
-- character.
local function records(key)
	local data = EverlookDB and EverlookDB.qol and EverlookDB.qol[id]
	if not data then return nil end
	if type(data[key]) ~= "table" then data[key] = {} end
	local guid = type(UnitGUID) == "function" and UnitGUID("player") or nil
	if type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then return nil end
	return data[key], guid
end

-- What the layout calls need, or nothing when this client lacks one or the moment is wrong.
local function ready()
	if type(C_EditMode) ~= "table" or type(C_EditMode.GetLayouts) ~= "function" or type(C_EditMode.SaveLayouts) ~= "function"
		or type(C_EditMode.OnLayoutAdded) ~= "function" or type(C_EditMode.SetActiveLayout) ~= "function"
		or type(C_EditMode.IsValidLayoutName) ~= "function" then return nil end
	if type(InCombatLockdown) ~= "function" or InCombatLockdown() then return nil end
	local manager = EditModeManagerFrame
	if type(manager) ~= "table" or type(manager.IsEditModeActive) ~= "function" or manager:IsEditModeActive() then return nil end
	local presets = type(EditModePresetLayoutManager) == "table" and EditModePresetLayoutManager.GetCopyOfPresetLayouts
	if type(presets) ~= "function" then return nil end
	local c = layouts.constants()
	local info = C_EditMode.GetLayouts()
	if not c or type(info) ~= "table" then return nil end
	return c, info, EditModePresetLayoutManager:GetCopyOfPresetLayouts()
end

local function switch_on()
	local all, guid = records("switched")
	if not all or all[guid] then return end
	local c, info, presets = ready()
	if not c then return end
	local result = layouts.prepare(info, presets, c)
	if not result then return end
	if result.created and C_EditMode.IsValidLayoutName(layouts.NAME) ~= true then return end
	if result.created or result.changed then C_EditMode.SaveLayouts(info) end
	-- Written first: the switch below makes the game send EDIT_MODE_LAYOUTS_UPDATED while it
	-- runs, which comes back here.
	all[guid] = result.previous or { stay = true }
	if result.created then
		C_EditMode.OnLayoutAdded(result.index, true, false)
	elseif result.changed or info.activeLayout ~= result.index then
		C_EditMode.SetActiveLayout(result.index)
	end
end

local function switch_off()
	local all, guid = records("switched")
	if not all or not all[guid] then return end
	local c, info, presets = ready()
	if not c then return end
	local previous = all[guid]
	all[guid] = nil
	-- Only when the player is still on the layout this made. A layout they chose stays.
	local ours = layouts.ours(info, presets)
	if not ours or info.activeLayout ~= ours then return end
	local target = layouts.find(info, presets, previous)
	if target then C_EditMode.SetActiveLayout(target) end
end

-- Action Bar 2 and 3 are switched on in the game's settings, Gameplay, Action Bars. The calls
-- are the ones that page makes: GetActionBarToggles gives a boolean for each of Action Bar 2
-- to 8 in turn, and SetActionBarToggles takes them all back. The game says its values are
-- wrong until the client has them from the server, so nothing is read or written for a few
-- seconds after login, and every value is passed back as it was read.
local TOGGLES = { 1, 2 }
local toggles_retry = false
local apply
local SETTLE = 5
local loaded_at = type(GetTime) == "function" and GetTime() or nil

local function toggles()
	if type(GetActionBarToggles) ~= "function" or type(SetActionBarToggles) ~= "function" or type(GetTime) ~= "function" or not loaded_at then return nil end
	if type(InCombatLockdown) ~= "function" or InCombatLockdown() then return nil end
	if GetTime() - loaded_at < SETTLE then
		if type(C_Timer) == "table" and type(C_Timer.After) == "function" and not toggles_retry then
			toggles_retry = true
			C_Timer.After(SETTLE, function()
				toggles_retry = false
				apply(module.enabled(id))
			end)
		end
		return nil
	end
	local values = { GetActionBarToggles() }
	for _, index in ipairs(TOGGLES) do
		if type(values[index]) ~= "boolean" then return nil end
	end
	return values
end

local function bars(enabled)
	local all, guid = records("bars_on")
	if not all then return end
	if enabled then
		local values = toggles()
		if not values then return end
		local turned = {}
		for _, index in ipairs(TOGGLES) do
			if values[index] == false then values[index], turned[index] = true, true end
		end
		if next(turned) == nil then return end
		-- Written first, as with the layout.
		all[guid] = turned
		SetActionBarToggles(unpack(values, 1, 7))
	elseif all[guid] then
		local values = toggles()
		if not values then return end
		local turned = all[guid]
		all[guid] = nil
		local changed = false
		for _, index in ipairs(TOGGLES) do
			if turned[index] and values[index] == true then values[index], changed = false, true end
		end
		if changed then SetActionBarToggles(unpack(values, 1, 7)) end
	end
end

apply = function(enabled)
	if enabled then switch_on() else switch_off() end
	bars(enabled)
end

module.register({
	addon = addon_name, page = "interface", order = 40,
	id = id, name = "Action bar slots",
	description = "Hides the empty slots on the two action bars above the main bar, until you drag something or open the spellbook. It uses the game's own Always Show Buttons setting from Edit Mode: it keeps a layout named Everlook Slots, a copy of the layout you use, with that setting off on Action Bar 2 and 3, and switches to it. A layout you named Everlook yourself is not touched. It also turns on Action Bar 2 and 3 under Settings, Gameplay, Action Bars when they are off, a few seconds after login at the earliest, because the bars do not exist otherwise. It waits for combat to end and for Edit Mode to be closed. Turning this off switches back to the layout you came from, if you are still on Everlook Slots, and turns off only the bars it turned on. That layout stays, and another specialization keeps the layout it has.",
	apply = apply, out_of_combat = true,
	events = { "PLAYER_ENTERING_WORLD", "EDIT_MODE_LAYOUTS_UPDATED" }, on_event = function() apply(module.enabled(id)) end,
})
