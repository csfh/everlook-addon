local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local plates = Everlook.nameplates
local id = "npc_titles"
local SOURCE = "everlook_titles"

-- The client draws an NPC's name and <title> in the world as engine text, which an addon cannot restyle. A friendly
-- NPC's nameplate is a frame, so it takes the same name style as a player's. Nameplates carry no title, so this
-- gives the nameplate view a subtitle line for it, read from the second line of the unit's tooltip.
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

-- The line under a friendly NPC's name, in the name's colour.
local function subtitle(unit, _, plate)
	if not friendly_npc(unit) then return nil end
	local title = title_of(unit)
	if not title then return nil end
	local red, green, blue = 0.1, 1, 0.1
	local name = plate and plate.UnitFrame and plate.UnitFrame.name
	if name and name.GetTextColor then
		local r, g, b = name:GetTextColor()
		if plain(r) and plain(g) and plain(b) then red, green, blue = r, g, b end
	end
	return { text = title, color = { red, green, blue } }
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
	if enabled then
		plates.provide({ source = SOURCE, order = 20, kinds = { "friendly_npc" }, subtitle = subtitle })
	else
		plates.remove(SOURCE)
	end
end

module.register({
	addon = addon_name, page = "interface", order = 40,
	id = id,
	name = "NPC names on nameplates",
	description = "Friendly NPCs get the same name style as players, with their title under the name. The game draws an NPC's own name and title as engine text that an addon cannot restyle, so this uses friendly NPC nameplates instead. The title is a line on the Nameplates view, which does the placing and needs to be on for a title to show.",
	options = {
		use_nameplates = { name = "Switch the game's NPC names to nameplates", default = true, description = "Turns on friendly NPC nameplates and turns off the game's own NPC names for friendly special NPCs, such as trainers and flight masters. Turning this module off, or this option, puts those settings back as they were." },
	},
	apply = apply,
	out_of_combat = true,
})
