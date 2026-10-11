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

local function hide(unit)
	local icon = by_unit[unit]
	by_unit[unit] = nil
	if icon then icon:Hide() end
end

local function art(icon)
	if icon.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(ATLAS) then
		icon:SetAtlas(ATLAS)
	else
		icon:SetTexture(FALLBACK)
	end
end

local function show(unit)
	hide(unit)
	if not module.enabled(id) or not on_a_quest(unit) then return end
	local plate = plate_of(unit)
	local frame = plate and plate.UnitFrame
	if not frame or not frame.CreateTexture then return end
	local place = module.get(id, "place")
	local anchor, point, relative, offset
	if place == "name_right" then
		anchor, point, relative, offset = frame.name or frame.healthBar, "LEFT", "RIGHT", 2
	elseif place == "bar_left" then
		anchor, point, relative, offset = frame.healthBar or frame.name, "RIGHT", "LEFT", -2
	else
		anchor, point, relative, offset = frame.name or frame.healthBar, "RIGHT", "LEFT", -2
	end
	if not anchor then return end
	local icon = icons[plate]
	if not icon then
		icon = frame:CreateTexture(nil, "OVERLAY")
		icons[plate] = icon
	end
	art(icon)
	local size = module.get(id, "size")
	icon:SetSize(size, size)
	icon:ClearAllPoints()
	icon:SetPoint(point, anchor, relative, offset, 0)
	icon:Show()
	by_unit[unit] = icon
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
	description = "Puts a small quest mark beside the nameplate of a unit that is part of a quest you are on: a target, someone to talk to or hand in to, or a quest boss. The game's own quest mark above the unit stays, because an addon cannot move or hide it. Who offers a quest you have not taken is not something the game tells an addon about a unit, so those get no mark.",
	options = {
		place = { name = "Where the mark goes", default = "name_left", choices = { { "name_left", "Left of the name" }, { "name_right", "Right of the name" }, { "bar_left", "Left of the health bar" } }, description = "Puts the mark to the left or right of a nameplate's name, or to the left of its health bar." },
		size = { name = "Mark size", default = 16, min = 8, max = 32, step = 2, description = "Sets how large the mark is, from 8 to 32, in steps of 2." },
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
