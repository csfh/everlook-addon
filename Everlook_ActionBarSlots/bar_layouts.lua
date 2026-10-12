local addon_name = ...
local Everlook = Everlook

-- Edit Mode layouts as plain data: what the game hands out in C_EditMode.GetLayouts, with
-- the presets ahead of the saved layouts in one numbering. Nothing here touches a frame.
local layouts = { NAME = "Everlook Slots", BARS = { 2, 3 } }

local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, inner in pairs(value) do result[key] = copy(inner) end
	return result
end

-- The game's own numbers for what these edits name, or nothing when this client lacks
-- one of them, so an edit it cannot make is never made.
function layouts.constants()
	local enum = type(Enum) == "table" and Enum or {}
	local system = type(enum.EditModeSystem) == "table" and enum.EditModeSystem.ActionBar
	local bar_setting = type(enum.EditModeActionBarSetting) == "table" and enum.EditModeActionBarSetting.AlwaysShowButtons
	local character = type(enum.EditModeLayoutType) == "table" and enum.EditModeLayoutType.Character
	local limits = type(Constants) == "table" and type(Constants.EditModeConsts) == "table" and Constants.EditModeConsts.EditModeMaxLayoutsPerType
	if type(system) ~= "number" or type(bar_setting) ~= "number" or type(character) ~= "number" or type(limits) ~= "number" then return nil end
	return { system = system, always_show = bar_setting, character = character, max = limits }
end

local function is_bar(system, c)
	if system.system ~= c.system then return false end
	for _, index in ipairs(layouts.BARS) do
		if system.systemIndex == index then return true end
	end
	return false
end

-- Turns off Always Show Buttons on the bars above the main bar. True when it changed something.
function layouts.hide_empty(layout, c)
	local changed = false
	for _, system in ipairs(layout.systems or {}) do
		if is_bar(system, c) then
			system.settings = system.settings or {}
			local found = false
			for _, row in ipairs(system.settings) do
				if row.setting == c.always_show then
					found = true
					if row.value ~= 0 then row.value, changed = 0, true end
				end
			end
			if not found then
				system.settings[#system.settings + 1] = { setting = c.always_show, value = 0 }
				changed = true
			end
		end
	end
	return changed
end

-- Makes sure the saved layouts hold one named Everlook with the empty slots hidden, adding it
-- as a copy of the layout in use when there is none. Returns { index, created, changed,
-- previous } where index counts the presets first and previous names the layout that was in
-- use (nothing when that was this one). A failure returns nothing and says why.
function layouts.prepare(info, presets, c)
	if not c or type(info) ~= "table" or type(info.layouts) ~= "table" or type(info.activeLayout) ~= "number" or type(presets) ~= "table" then
		return nil, "no layouts"
	end
	local preset_count = #presets
	local active = info.activeLayout
	local source = active <= preset_count and presets[active] or info.layouts[active - preset_count]
	if type(source) ~= "table" then return nil, "no active layout" end
	local ours
	for position, item in ipairs(info.layouts) do
		if item.layoutName == layouts.NAME then ours = position; break end
	end
	if ours then
		local item = info.layouts[ours]
		local result = { index = preset_count + ours, created = false, changed = layouts.hide_empty(item, c) }
		if source ~= item then result.previous = { name = source.layoutName, type = source.layoutType } end
		return result
	end
	local same_kind = 0
	for _, item in ipairs(info.layouts) do
		if item.layoutType == c.character then same_kind = same_kind + 1 end
	end
	if same_kind >= c.max then return nil, "full" end
	local made = copy(source)
	made.layoutName, made.layoutType = layouts.NAME, c.character
	layouts.hide_empty(made, c)
	info.layouts[#info.layouts + 1] = made
	return {
		index = preset_count + #info.layouts, created = true, changed = true,
		previous = { name = source.layoutName, type = source.layoutType },
	}
end

-- The number of the layout with this name and type, presets counted first.
function layouts.find(info, presets, wanted)
	if type(info) ~= "table" or type(info.layouts) ~= "table" or type(presets) ~= "table" or type(wanted) ~= "table" then return nil end
	for position, item in ipairs(presets) do
		if item.layoutName == wanted.name and item.layoutType == wanted.type then return position end
	end
	for position, item in ipairs(info.layouts) do
		if item.layoutName == wanted.name and item.layoutType == wanted.type then return #presets + position end
	end
end

-- The number of the layout this module made or adopted, whatever its type.
function layouts.ours(info, presets)
	if type(info) ~= "table" or type(info.layouts) ~= "table" or type(presets) ~= "table" then return nil end
	for position, item in ipairs(info.layouts) do
		if item.layoutName == layouts.NAME then return #presets + position end
	end
end

Everlook.bar_layouts = layouts
