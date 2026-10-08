local _, Everlook = ...

Everlook.talents = {}

local function integer(value)
	if not Everlook.world.usable(value) or type(value) ~= "number" then
		return nil
	end
	if value < 0 or value ~= math.floor(value) then
		return nil
	end
	return value
end

local function text(value)
	if Everlook.world.usable(value) and type(value) == "string" and value ~= "" then
		return value
	end
end

local function spell_id(link)
	if type(link) ~= "string" then
		return nil
	end
	local id = link:match("Hspell:(%d+)")
	return integer(tonumber(id))
end

local function class_id()
	if not UnitClass then
		return nil
	end
	local _, _, id = UnitClass("player")
	return integer(id)
end

local function store(row)
	row.classId = row.classId or class_id()
	if not row.id or not row.name then
		return
	end
	Everlook.world.store("talents", row)
	if row.spellId and Everlook.spells and Everlook.spells.record then
		Everlook.spells.record(nil, row.spellId)
	end
end

local function scan_classic()
	if type(GetNumTalentTabs) ~= "function" or type(GetNumTalents) ~= "function" or type(GetTalentInfo) ~= "function" then
		return false
	end
	local tabs = integer(GetNumTalentTabs())
	if not tabs or tabs == 0 then
		return false
	end
	local found = false
	for tab = 1, tabs do
		local treeName
		if type(GetTalentTabInfo) == "function" then
			local ok, first, second = pcall(GetTalentTabInfo, tab)
			if ok then
				treeName = text(first) or text(second)
			end
		end
		local count = integer(GetNumTalents(tab)) or 0
		for index = 1, count do
			local ok, name, icon, tier, column, rank, maxRank = pcall(GetTalentInfo, tab, index)
			if ok then
				name = text(name)
				local link
				if type(GetTalentLink) == "function" then
					local linked, value = pcall(GetTalentLink, tab, index)
					if linked then
						link = spell_id(value)
					end
				end
				local prereqTier, prereqColumn
				if type(GetTalentPrereqs) == "function" then
					local ready, requiredTier, requiredColumn = pcall(GetTalentPrereqs, tab, index)
					if ready then
						prereqTier = integer(requiredTier)
						prereqColumn = integer(requiredColumn)
					end
				end
				if name then
					found = true
					store({
						id = link or (tab * 1000 + index),
						name = name,
						icon = integer(icon),
						treeId = tab,
						treeName = treeName,
						nodeId = index,
						tier = integer(tier),
						column = integer(column),
						maxRank = integer(maxRank),
						rank = integer(rank),
						spellId = link,
						prereqTier = prereqTier,
						prereqColumn = prereqColumn,
					})
				end
			end
		end
	end
	return found
end

local function definition_spell(configId, entryId)
	if type(C_Traits.GetEntryInfo) ~= "function" or type(C_Traits.GetDefinitionInfo) ~= "function" then
		return nil
	end
	local ok, entry = pcall(C_Traits.GetEntryInfo, configId, entryId)
	if not ok or type(entry) ~= "table" then
		return nil
	end
	local defined, definition = pcall(C_Traits.GetDefinitionInfo, entry.definitionID)
	if not defined or type(definition) ~= "table" then
		return nil
	end
	return definition
end

local function scan_config(configId, classOverride)
	if type(C_Traits.GetConfigInfo) ~= "function" or type(C_Traits.GetTreeNodes) ~= "function" or type(C_Traits.GetNodeInfo) ~= "function" then
		return
	end
	local ok, info = pcall(C_Traits.GetConfigInfo, configId)
	if not ok or type(info) ~= "table" or type(info.treeIDs) ~= "table" then
		return
	end
	for _, treeId in ipairs(info.treeIDs) do
		treeId = integer(treeId)
		local nodes
		if treeId then
			local ready, listed = pcall(C_Traits.GetTreeNodes, treeId)
			if ready then
				nodes = listed
			end
		end
		if treeId and type(nodes) == "table" then
			for _, nodeId in ipairs(nodes) do
				nodeId = integer(nodeId)
				local known, node = pcall(C_Traits.GetNodeInfo, configId, nodeId)
				if known and type(node) == "table" and nodeId then
					local spellId, name, icon
					local entries = node.entryIDs
					if type(entries) == "table" then
						for i = 1, #entries do
							local definition = definition_spell(configId, entries[i])
							if type(definition) == "table" then
								spellId = integer(definition.spellID) or spellId
								name = text(definition.overrideName) or name
								icon = integer(definition.overrideIcon) or icon
							end
						end
					end
					if spellId and not name and Everlook.spells then
						name = nil
					end
					if spellId or name then
						store({
							id = spellId or nodeId,
							name = name or ("Talent " .. tostring(spellId or nodeId)),
							icon = icon,
							classId = classOverride,
							treeId = treeId,
							nodeId = nodeId,
							tier = integer(node.posY),
							column = integer(node.posX),
							maxRank = integer(node.maxRanks),
							rank = integer(node.currentRank),
							spellId = spellId,
						})
					end
				end
			end
		end
	end
end

local function scan_traits()
	if not C_ClassTalents or not C_Traits or type(C_ClassTalents.GetActiveConfigID) ~= "function" then
		return
	end
	local seen = {}
	local function read(configId, classOverride)
		configId = integer(configId)
		if not configId or seen[configId] then
			return
		end
		seen[configId] = true
		scan_config(configId, classOverride)
	end
	read(C_ClassTalents.GetActiveConfigID(), nil)
	if type(GetNumSpecializations) == "function" and type(GetSpecializationInfo) == "function" and type(C_ClassTalents.GetConfigIDsBySpecID) == "function" then
		local specs = integer(GetNumSpecializations()) or 0
		for index = 1, specs do
			local specId = integer(GetSpecializationInfo(index))
			if specId then
				local ok, configs = pcall(C_ClassTalents.GetConfigIDsBySpecID, specId)
				if ok and type(configs) == "table" then
					for i = 1, #configs do
						read(configs[i], nil)
					end
				end
			end
		end
	end
end

function Everlook.talents.scan()
	if not scan_classic() then
		scan_traits()
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_TALENT_UPDATE")
frame:RegisterEvent("CHARACTER_POINTS_CHANGED")
frame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
frame:RegisterEvent("TRAIT_CONFIG_UPDATED")
frame:SetScript("OnEvent", function()
	Everlook.talents.scan()
end)
