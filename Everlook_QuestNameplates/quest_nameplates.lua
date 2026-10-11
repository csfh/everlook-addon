local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "quest_nameplates"

-- The game's own quest mark floats above a unit and an addon can neither move nor restyle it, so this adds a
-- small mark of its own on the nameplate, and the game's stays where it is. The game says whether a unit is part
-- of a quest you are on, and that is all this marks: who offers a quest you have not taken is not something the
-- game tells an addon about a unit.
local ATLAS = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Quest"
local FALLBACK = "Interface\\TargetingFrame\\PortraitQuestBadge"
local icons = setmetatable({}, { __mode = "k" })
local by_unit = {}

local function plain(value)
	return value ~= nil and not (issecretvalue and issecretvalue(value))
end

local function plate_of(unit)
	local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
	if not plate or (plate.IsForbidden and plate:IsForbidden()) then return nil end
	return plate
end

-- A unit that belongs to a quest in your log: a target, an item to use, someone to talk to or hand in to, or a
-- quest boss. A player never is.
local function on_a_quest(unit)
	if not (UnitExists and UnitExists(unit)) then return false end
	local player = UnitIsPlayer and UnitIsPlayer(unit)
	if not plain(player) or player then return false end
	local related = C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest and C_QuestLog.UnitIsRelatedToActiveQuest(unit)
	if plain(related) and related then return true end
	local boss = UnitIsQuestBoss and UnitIsQuestBoss(unit)
	return plain(boss) and boss and true or false
end

-- A name left as the game had it, kept so a plate that loses its mark gets its own alignment back.
local aligned = setmetatable({}, { __mode = "k" })

local function restore_name(plate)
	local name = aligned[plate]
	aligned[plate] = nil
	if name and name.fontstring and name.fontstring.SetJustifyH then name.fontstring:SetJustifyH(name.justify) end
end

-- A plate is remembered by the unit it was marking, because by the time the game says the unit is gone the plate
-- can no longer be found from it, and a plate is reused for the next unit.
local function hide(unit)
	local plate = by_unit[unit]
	by_unit[unit] = nil
	if not plate then return end
	if icons[plate] then icons[plate]:Hide() end
	restore_name(plate)
end

local function art(icon)
	if icon.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(ATLAS) then
		icon:SetAtlas(ATLAS)
	else
		icon:SetTexture(FALLBACK)
	end
end

-- Left-aligns the name over the health bar, and remembers how it was, so the name sits above the bar's left end
-- beside the mark and not over the middle of the bar.
local function left_align(plate, name)
	if not (name and name.SetJustifyH and name.GetJustifyH) then return end
	if not aligned[plate] then
		local justify = name:GetJustifyH()
		if plain(justify) then aligned[plate] = { fontstring = name, justify = justify } end
	end
	name:SetJustifyH("LEFT")
end

-- Temporary: what the game did with the last few marks, kept in the saved variables to read after a reload, because
-- a nameplate is restricted and cannot be measured by eye from here. Removed once the layout is settled.
local function trace(unit, layout, name, bar, icon)
	local function measure(region)
		if not region then return "none" end
		local ok, left, bottom, width, height = pcall(region.GetRect, region)
		if not ok then return "error: " .. tostring(left) end
		return tostring(left) .. "," .. tostring(bottom) .. " " .. tostring(width) .. "x" .. tostring(height)
	end
	local function kind(region)
		if not region then return "none" end
		local ok, value = pcall(region.GetObjectType, region)
		return ok and tostring(value) or "error"
	end
	EverlookDB = EverlookDB or {}
	local log = EverlookDB.quest_nameplates_trace
	if type(log) ~= "table" then log = {}; EverlookDB.quest_nameplates_trace = log end
	local ok, justify = pcall(function() return name and name:GetJustifyH() end)
	local ok_points, points = pcall(function() return icon:GetNumPoints() end)
	log[#log + 1] = table.concat({
		tostring(unit), "layout=" .. tostring(layout), "name=" .. kind(name), "bar=" .. kind(bar),
		"icon " .. measure(icon), "points=" .. (ok_points and tostring(points) or "error"), "shown=" .. tostring(icon:IsShown()),
		"name " .. measure(name), "bar " .. measure(bar), "justify=" .. (ok and tostring(justify) or "error"),
	}, " | ")
	while #log > 8 do table.remove(log, 1) end
end

local function show(unit)
	hide(unit)
	if not module.enabled(id) or not on_a_quest(unit) then return end
	local plate = plate_of(unit)
	local frame = plate and plate.UnitFrame
	if not frame or not frame.CreateTexture then return end
	local name = frame.name
	local bar = frame.HealthBarsContainer or frame.healthBar
	local layout = module.get(id, "layout")
	local width = module.get(id, "width")
	local icon = icons[plate]
	if not icon then
		icon = frame:CreateTexture(nil, "OVERLAY")
		icons[plate] = icon
	end
	icon:ClearAllPoints()
	if layout == "name_right" and (name or bar) then
		icon:SetSize(width, width)
		icon:SetPoint("LEFT", name or bar, "RIGHT", 2, 0)
	elseif layout == "bar_left" and (bar or name) then
		icon:SetSize(width, width)
		icon:SetPoint("RIGHT", bar or name, "LEFT", -2, 0)
	elseif layout == "name_left" and (name or bar) then
		icon:SetSize(width, width)
		icon:SetPoint("RIGHT", name or bar, "LEFT", -2, 0)
	elseif name and bar then
		-- Both rows: from the top of the name to the bottom of the health bar, just left of the bar's left end,
		-- which is four in from where the name starts.
		icon:SetWidth(width)
		icon:SetPoint("TOPRIGHT", name, "TOPLEFT", -6, 0)
		icon:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", -2, 0)
	elseif name or bar then
		icon:SetSize(width, width)
		icon:SetPoint("RIGHT", name or bar, "LEFT", -2, 0)
	else
		return
	end
	art(icon)
	icon:Show()
	by_unit[unit] = plate
	if module.get(id, "align_name") then left_align(plate, name) end
	pcall(trace, unit, layout, name, bar, icon)
end

local function refresh_all()
	for unit in pairs(by_unit) do hide(unit) end
	if not module.enabled(id) or not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if plain(unit) and type(unit) == "string" then show(unit) end
	end
end

module.register({
	addon = addon_name, page = "interface", order = 45,
	id = id,
	name = "Quest marks on nameplates",
	description = "Puts a quest mark beside the nameplate of a unit that is part of a quest you are on: a target, someone to talk to or hand in to, or a quest boss. The game's own quest mark above the unit stays, because an addon cannot move or hide it. Who offers a quest you have not taken is not something the game tells an addon about a unit, so those get no mark.",
	options = {
		layout = { name = "Where the mark goes", default = "rows", choices = { { "rows", "Left of the name and the health bar" }, { "name_left", "Left of the name" }, { "name_right", "Right of the name" }, { "bar_left", "Left of the health bar" } }, description = "Puts the mark to the left of both the name and the health bar, as tall as the two together, or beside only the name or only the health bar." },
		width = { name = "Mark width", default = 26, min = 12, max = 48, step = 2, description = "Sets how wide the mark is, from 12 to 48, in steps of 2. Beside both the name and the health bar it is as tall as the two together, and beside only one it is square." },
		align_name = { name = "Left-align the name of a marked unit", default = true, description = "Moves the name of a unit that has a mark to the left end of its health bar, beside the mark, and puts it back as the game had it when the mark goes. Other nameplates keep their names where they are." },
	},
	apply = refresh_all,
	events = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" },
	on_event = function(event, unit)
		if event == "NAME_PLATE_UNIT_ADDED" then
			if plain(unit) and type(unit) == "string" then show(unit) end
		elseif event == "NAME_PLATE_UNIT_REMOVED" then
			if plain(unit) and type(unit) == "string" then hide(unit) end
		else
			refresh_all()
		end
	end,
})
