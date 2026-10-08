local _, Everlook = ...

Everlook.npcs = {}

-- The entry id is fixed for a guid. Casts ask again for the same spawn.
local guid_ids = {}

function Everlook.npcs.creature_id(guid)
	if not Everlook.world.usable(guid) or type(guid) ~= "string" then
		return nil
	end
	local cached = guid_ids[guid]
	if cached == false then
		return nil
	end
	if cached ~= nil then
		return cached
	end
	local id = Everlook.world.guid_id(guid, "Creature") or Everlook.world.guid_id(guid, "Vehicle")
	guid_ids[guid] = id or false
	return id
end

local function public(value)
	if Everlook.world.usable(value) then
		return value
	end
end

-- Nameplates and mouseover refire for the same spawn. One sighting per source
-- per window keeps the row current without rebuilding the world document.
local sightings = Everlook.sightings.window()
local plain_guid = Everlook.sightings.plain_guid
-- Level, classification, creature type, reaction, and health stay put for a spawn.
-- Later sightings only move the pin.
local settled = {}
local refresh_locations = {}
local refresh_row = { sources = {} }

function Everlook.npcs.record(unit, source, guid)
	if not unit or unit == "" then
		return
	end
	-- A secret guid errors on this comparison. false is a plain sentinel for an empty mouseover.
	if not Everlook.world.usable(guid) then
		return
	end
	if guid == false then
		return
	end
	if type(guid) ~= "string" then
		if not UnitGUID then
			return
		end
		guid = UnitGUID(unit)
		if not plain_guid(guid) then
			return
		end
	end
	if sightings.same(guid, source) then
		return
	end
	-- Mouseover keeps firing while the cursor stays. A player or other
	-- non-creature never gains a row, so remember the guid and stop.
	if UnitIsPlayer and public(UnitIsPlayer(unit)) then
		sightings.note(guid, source)
		return
	end
	local id = Everlook.npcs.creature_id(guid)
	if not id then
		sightings.note(guid, source)
		return
	end
	if settled[guid] then
		sightings.note(guid, source)
		refresh_row.id = id
		refresh_row.sources[1] = source
		local location = Everlook.location.player(true)
		if location then
			refresh_locations[1] = location
			refresh_row.locations = refresh_locations
		else
			refresh_row.locations = nil
		end
		Everlook.world.store("npcs", refresh_row)
		return
	end
	local name = public(UnitName and UnitName(unit))
	if type(name) ~= "string" or name == "" then
		return
	end
	local level = public(UnitLevel and UnitLevel(unit))
	if type(level) ~= "number" or level > 0 then
		sightings.note(guid, source)
	end
	local row = {
		id = id,
		name = name,
		minLevel = level,
		maxLevel = level,
		classification = public(UnitClassification and UnitClassification(unit)),
		creatureType = public(UnitCreatureType and UnitCreatureType(unit)),
		creatureFamily = public(UnitCreatureFamily and UnitCreatureFamily(unit)),
		sources = { source },
		location = Everlook.location.player(true),
	}
	local faction = public(UnitFactionGroup and UnitFactionGroup(unit))
	if type(faction) == "string" then
		row.factionGroup = faction
	end
	local title = public(UnitPVPName and UnitPVPName(unit))
	if type(title) == "string" and title ~= name then
		row.subtitle = title
	end
	local health = public(UnitHealthMax and UnitHealthMax(unit))
	row.maxHealth = health
	if UnitPowerMax then
		local mana = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
		row.maxMana = public(UnitPowerMax(unit, mana))
	end
	if UnitIsTrainer then
		local trainer = public(UnitIsTrainer(unit))
		if trainer ~= nil then
			row.isTrainer = trainer and true or false
		end
	end
	local reaction_known = true
	if UnitReaction and UnitFactionGroup then
		reaction_known = false
		local side = public(UnitFactionGroup("player"))
		local reaction = public(UnitReaction(unit, "player"))
		if type(reaction) == "number" then
			reaction_known = true
			if side == "Alliance" then
				row.reactionAlliance = reaction
			elseif side == "Horde" then
				row.reactionHorde = reaction
			end
		end
	end
	if reaction_known
		and type(level) == "number" and level > 0
		and type(row.classification) == "string" and row.classification ~= ""
		and type(row.creatureType) == "string" and row.creatureType ~= ""
		and type(health) == "number" and health > 0 then
		settled[guid] = true
	end
	if row.location then
		row.locations = { row.location }
	end
	row.location = nil
	Everlook.world.store("npcs", row)
	Everlook.npcs.note_faction(id)
end

function Everlook.npcs.note_faction(creature_id)
	local reader = C_CreatureInfo and C_CreatureInfo.GetFactionInfo
	if type(reader) ~= "function" or type(creature_id) ~= "number" then
		return
	end
	local ok, info = pcall(reader, creature_id)
	if not ok or type(info) ~= "table" then
		return
	end
	local faction_id = public(info.factionID or info.factionId)
	if type(faction_id) ~= "number" or faction_id <= 0 then
		return
	end
	Everlook.world.store("npcFactions", { npcId = creature_id, factionId = faction_id })
end

local function gossip_lines()
	if not C_GossipInfo or type(C_GossipInfo.GetText) ~= "function" then
		return nil
	end
	local greeting = C_GossipInfo.GetText()
	if not public(greeting) then
		return nil
	end
	local lines = {}
	if type(greeting) == "string" and greeting ~= "" then
		lines[#lines + 1] = greeting
	end
	local options = C_GossipInfo.GetOptions and C_GossipInfo.GetOptions() or {}
	if type(options) == "table" then
		for index = 1, #options do
			local option = options[index]
			local label = type(option) == "table" and public(option.name or option.text) or nil
			if type(label) == "string" and label ~= "" then
				lines[#lines + 1] = label
			end
		end
	end
	return lines
end

function Everlook.npcs.gossip()
	local guid = UnitGUID and UnitGUID("npc")
	local creature_id = Everlook.npcs.creature_id(guid)
	if not creature_id then
		return false
	end
	local lines = gossip_lines()
	if not lines or #lines == 0 then
		return false
	end
	local row = Everlook.world.row and Everlook.world.row("npcs", creature_id)
	local have, seen = {}, {}
	if type(row) == "table" and type(row.gossip) == "string" then
		for line in row.gossip:gmatch("[^\n]+") do
			if not seen[line] then
				seen[line] = true
				have[#have + 1] = line
			end
		end
	end
	local grew = false
	for index = 1, #lines do
		local line = lines[index]
		if not seen[line] and #have < 8 then
			seen[line] = true
			have[#have + 1] = line
			grew = true
		end
	end
	if not grew then
		return false
	end
	return Everlook.world.store("npcs", { id = creature_id, gossip = table.concat(have, "\n") }) == true
end

local function trainer_spell_id(index, category)
	if category == "header" then
		return nil
	end
	if C_TooltipInfo and type(C_TooltipInfo.GetTrainerService) == "function" then
		local ok, data = pcall(C_TooltipInfo.GetTrainerService, index)
		local spell_type = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Spell
		if ok and type(data) == "table" and type(data.id) == "number" and data.id > 0 then
			if spell_type == nil or data.type == nil or data.type == spell_type then
				return data.id
			end
		end
	end
	if type(GetTrainerServiceItemLink) == "function" then
		local link = GetTrainerServiceItemLink(index)
		if type(link) == "string" then
			local spell_id = tonumber(link:match("spell:(%d+)"))
			if type(spell_id) == "number" and spell_id > 0 then
				return spell_id
			end
		end
	end
end

function Everlook.npcs.read_trainer()
	if type(GetNumTrainerServices) ~= "function" or type(GetTrainerServiceInfo) ~= "function" then
		return false
	end
	local creature_id = Everlook.npcs.creature_id(UnitGUID and UnitGUID("npc"))
	if not creature_id then
		return false
	end
	local count = GetNumTrainerServices()
	if type(count) ~= "number" then
		return false
	end
	local ids = {}
	for index = 1, count do
		local _, _, category = GetTrainerServiceInfo(index)
		local spell_id = public(trainer_spell_id(index, category))
		if type(spell_id) == "number" and spell_id > 0 then
			ids[#ids + 1] = spell_id
		end
	end
	if #ids == 0 then
		return false
	end
	table.sort(ids)
	local row = Everlook.world.row and Everlook.world.row("npcs", creature_id)
	local previous = type(row) == "table" and row.trainerSpells or nil
	if type(previous) == "table" and #previous == #ids then
		local same = true
		for index = 1, #ids do
			local have = previous[index]
			local have_id = type(have) == "table" and have.spellId or have
			if have_id ~= ids[index] then
				same = false
				break
			end
		end
		if same then
			return false
		end
	end
	local spells = {}
	for index = 1, #ids do
		spells[index] = { spellId = ids[index] }
		if Everlook.spells and Everlook.spells.record then
			Everlook.spells.record(nil, ids[index])
		end
	end
	return Everlook.world.store("npcs", { id = creature_id, isTrainer = true, trainerSpells = spells }) == true
end

function Everlook.npcs.vignette(vignette_guid)
	if not C_VignetteInfo or type(C_VignetteInfo.GetVignetteInfo) ~= "function" then
		return false
	end
	local ok, info = pcall(C_VignetteInfo.GetVignetteInfo, vignette_guid)
	if not ok or type(info) ~= "table" then
		return false
	end
	local guid = info.objectGUID or info.guid
	local creature_id = Everlook.npcs.creature_id(guid)
	if not creature_id then
		return false
	end
	local name = public(info.name)
	local row = { id = creature_id, classification = "rare", sources = { "vignette" } }
	if type(name) == "string" and name ~= "" then
		row.name = name
	end
	if Everlook.location and Everlook.location.player then
		local location = Everlook.location.player()
		if location then
			if C_VignetteInfo and type(C_VignetteInfo.GetVignettePosition) == "function" and type(location.mapId) == "number" then
				local placed, position = pcall(C_VignetteInfo.GetVignettePosition, vignette_guid, location.mapId)
				if placed and type(position) == "table" then
					local raw_x, raw_y
					if type(position.GetXY) == "function" then
						raw_x, raw_y = position:GetXY()
					else
						raw_x, raw_y = position.x, position.y
					end
					local function scale_point(value)
						value = public(value)
						if type(value) ~= "number" or value < 0 or value > 1 then
							return nil
						end
						return math.floor(value * 1000 + 0.5)
					end
					local x = scale_point(raw_x)
					local y = scale_point(raw_y)
					if x and y then
						location.x = x
						location.y = y
					end
				end
			end
			location.role = 5
			row.locations = { location }
		end
	end
	Everlook.world.store("npcs", row)
	return true
end

function Everlook.npcs.scan_units()
	local units = { "target", "mouseover", "focus", "pet", "npc", "softinteract" }
	for i = 1, 4 do
		units[#units + 1] = "party" .. i
	end
	for i = 1, 8 do
		units[#units + 1] = "boss" .. i
	end
	for i = 1, 40 do
		units[#units + 1] = "nameplate" .. i
		units[#units + 1] = "raid" .. i
	end
	for i = 1, #units do
		local unit = units[i]
		local source = "nameplate"
		if unit == "target" or unit == "mouseover" or unit == "focus" or unit == "pet" or unit == "npc" or unit == "softinteract" then
			source = unit
		elseif unit:sub(1, 5) == "party" or unit:sub(1, 4) == "raid" or unit:sub(1, 4) == "boss" then
			source = "group"
		end
		Everlook.npcs.record(unit, source)
	end
end

-- Mouseover refires while the cursor stays. One guid read feeds the npc row.
-- Only a game object guid is handed to the node check.
function Everlook.npcs.on_mouseover()
	local guid = UnitGUID and UnitGUID("mouseover")
	if not Everlook.world.usable(guid) or type(guid) ~= "string" then
		guid = false
	end
	Everlook.npcs.record("mouseover", "mouseover", guid)
	local object_guid = guid ~= false and guid:byte(1) == 71 and guid:byte(2) == 97
	if object_guid and Everlook.objects and Everlook.objects.watch then
		Everlook.objects.watch(guid)
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
frame:RegisterEvent("MERCHANT_SHOW")
frame:RegisterEvent("GOSSIP_SHOW")
frame:RegisterEvent("TRAINER_SHOW")
if C_VignetteInfo and type(C_VignetteInfo.GetVignetteInfo) == "function" then
	frame:RegisterEvent("VIGNETTE_MINIMAP_UPDATED")
end
frame:SetScript("OnEvent", function(_, event, unit)
	if event == "PLAYER_TARGET_CHANGED" then
		Everlook.npcs.record("target", "target")
	elseif event == "UPDATE_MOUSEOVER_UNIT" then
		Everlook.npcs.on_mouseover()
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		Everlook.npcs.record(unit, "nameplate")
	elseif event == "MERCHANT_SHOW" then
		Everlook.npcs.record("npc", "merchant")
	elseif event == "GOSSIP_SHOW" then
		Everlook.npcs.gossip()
	elseif event == "TRAINER_SHOW" then
		Everlook.npcs.read_trainer()
	elseif event == "VIGNETTE_MINIMAP_UPDATED" then
		Everlook.npcs.vignette(unit)
	end
end)
