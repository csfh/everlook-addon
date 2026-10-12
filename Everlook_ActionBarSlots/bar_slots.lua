local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local layouts = Everlook.bar_layouts
local settings = Everlook.blizzard_settings
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
	if not all then return end
	local c, info, presets = ready()
	if not c then return end
	-- Done once. A way back with no layout behind it, left by an earlier version, is not done.
	if all[guid] and layouts.ours(info, presets) then return end
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

-- Action Bar 2 and 3 have to be switched on in the game's settings, or there is nothing to
-- hide the slots on. The core helper does that, waits out the first seconds after login, and
-- puts back only what it turned on.
local BARS = { "action_bar_2", "action_bar_3" }
local retry_queued = false
local apply

local function bars(enabled)
	local waiting = false
	for _, key in ipairs(BARS) do
		local ok, why
		if enabled then ok, why = settings.ensure(key, true) else ok, why = settings.release(key) end
		if not ok and why == "waiting" then waiting = true end
	end
	-- After combat this runs again on its own, and after login it waits for the game to settle.
	if waiting and not retry_queued then
		retry_queued = true
		settings.when_settled(function()
			retry_queued = false
			apply(module.enabled(id))
		end)
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
