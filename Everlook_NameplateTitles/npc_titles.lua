local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "npc_titles"

-- The client draws an NPC's name and <title> in the world as engine text, which
-- an addon cannot restyle. A friendly NPC's nameplate is a frame, so it takes
-- the same name style as a player's. Nameplates carry no title, so this adds it
-- as a second line, read from the second line of the unit's tooltip.
local lines = setmetatable({}, { __mode = "k" })
local by_unit = {}
local CVARS = { "nameplateShowFriendlyNpcs", "UnitNameNPC", "UnitNameFriendlySpecialNPCName" }

local function plain(value)
	return value ~= nil and not (issecretvalue and issecretvalue(value))
end

-- "<Gryphon Master>" from the tooltip, or nil when the NPC has no title.
local function title_of(unit)
	if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return nil end
	local data = C_TooltipInfo.GetUnit(unit)
	if not plain(data) or type(data) ~= "table" then return nil end
	local row = type(data.lines) == "table" and data.lines[2]
	if not plain(row) or type(row) ~= "table" then return nil end
	local text = row.leftText
	if not plain(text) or type(text) ~= "string" then return nil end
	return text:match("^<.+>$") and text or nil
end

local function friendly_npc(unit)
	return UnitExists and UnitExists(unit) and not UnitIsPlayer(unit) and not UnitCanAttack("player", unit)
end

local function plate_of(unit)
	local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
	if not plate or (plate.IsForbidden and plate:IsForbidden()) then return nil end
	return plate
end

local function hide(unit)
	local line = by_unit[unit]
	by_unit[unit] = nil
	if line then line:Hide() end
end

local function show(unit)
	hide(unit)
	if not module.enabled(id) or not friendly_npc(unit) then return end
	local plate = plate_of(unit)
	local frame = plate and plate.UnitFrame
	local name = frame and frame.name
	if not name or not name.GetFont then return end
	local title = title_of(unit)
	if not title then return end
	local line = lines[plate]
	if not line then
		line = frame:CreateFontString(nil, "OVERLAY")
		lines[plate] = line
	end
	-- Same face and outline as the name, a little smaller, in the name's colour.
	local path, size, flags = name:GetFont()
	if type(path) ~= "string" or type(size) ~= "number" then return end
	line:SetFont(path, math.max(8, math.floor(size * 0.8 + 0.5)), flags)
	local red, green, blue = 0.1, 1, 0.1
	if name.GetTextColor then
		local r, g, b = name:GetTextColor()
		if plain(r) and plain(g) and plain(b) then red, green, blue = r, g, b end
	end
	line:SetTextColor(red, green, blue)
	line:ClearAllPoints()
	line:SetPoint("TOP", name, "BOTTOM", 0, -1)
	line:SetText(title)
	line:Show()
	by_unit[unit] = line
end

local function refresh_all()
	for unit in pairs(by_unit) do hide(unit) end
	if not module.enabled(id) or not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if plain(unit) and type(unit) == "string" then show(unit) end
	end
end

-- The nameplate settings that turn the engine's NPC text off and the friendly
-- NPC nameplates on. What they were is kept, and put back when this goes off.
local function switch_names(enabled)
	if type(InCombatLockdown) ~= "function" or InCombatLockdown() or not GetCVar or not SetCVar then return end
	EverlookDB = EverlookDB or {}
	if enabled and module.get(id, "use_nameplates") then
		if type(EverlookDB.npc_titles_cvars) ~= "table" then
			local original = {}
			for _, name in ipairs(CVARS) do original[name] = GetCVar(name) end
			EverlookDB.npc_titles_cvars = original
		end
		SetCVar("nameplateShowFriendlyNpcs", "1")
		SetCVar("UnitNameNPC", "0")
		SetCVar("UnitNameFriendlySpecialNPCName", "0")
	elseif type(EverlookDB.npc_titles_cvars) == "table" then
		for _, name in ipairs(CVARS) do
			local value = EverlookDB.npc_titles_cvars[name]
			if type(value) == "string" then SetCVar(name, value) end
		end
		EverlookDB.npc_titles_cvars = nil
	end
end

local function apply(enabled)
	switch_names(enabled)
	refresh_all()
end

module.register({
	addon = addon_name, page = "interface", order = 40,
	id = id,
	name = "NPC names on nameplates",
	description = "Friendly NPCs get the same name style as players, with their title under the name. The game draws an NPC's own name and title as engine text that an addon cannot restyle, so this uses friendly NPC nameplates instead.",
	options = {
		use_nameplates = { name = "Switch the game's NPC names to nameplates", default = true, description = "Turns on friendly NPC nameplates and turns off the game's own NPC names for friendly special NPCs, such as trainers and flight masters. Turning this module off, or this option, puts those settings back as they were." },
	},
	apply = apply,
	out_of_combat = true,
	events = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_ENTERING_WORLD" },
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
