local _, Everlook = ...

Everlook.items = {}

local pending = {}

-- A tooltip can grow after the first read. Once two reads see the same
-- line count, a later record only adds a source, or the quest a starter begins.
local known = {}
local seen_lines = {}
local noted_quests = {}
local pending_quest = {}
local noted_sources = {}

local function note_source(id, source)
	local have = noted_sources[id]
	if not have then
		have = {}
		noted_sources[id] = have
	end
	have[source] = true
end

-- Loot and merchants repeat the same link shape. The id is read in place
-- so the capture is not allocated.
function Everlook.items.id_from_link(link)
	if not Everlook.world.usable(link) or type(link) ~= "string" then
		return nil
	end
	local start = link:find("item:", 1, true)
	if not start then
		return nil
	end
	start = start + 5
	local id = 0
	local digits = 0
	for index = start, #link do
		local byte = link:byte(index)
		if byte < 48 or byte > 57 then
			break
		end
		id = id * 10 + (byte - 48)
		digits = digits + 1
	end
	if digits == 0 then
		return nil
	end
	return id
end

local function public(value)
	if Everlook.world.usable(value) then
		return value
	end
end

local function text(value)
	value = public(value)
	if type(value) == "string" and value ~= "" then
		return value
	end
end

local function stat_label(key)
	key = public(key)
	if type(key) ~= "string" then
		return nil
	end
	local body = key:match("^ITEM_MOD_(.+)_SHORT$")
	if not body then
		return nil
	end
	body = body:gsub("_", " "):lower()
	return (body:gsub("(%a)([%w']*)", function(first, rest)
		return first:upper() .. rest
	end))
end

local function item_stats(id, link)
	local reader = C_Item and C_Item.GetItemStats or GetItemStats
	if type(reader) ~= "function" then
		return nil
	end
	local query = public(link)
	if type(query) ~= "string" or query == "" then
		query = "item:" .. tostring(id)
	end
	local ok, stats = pcall(reader, query)
	if not ok or type(stats) ~= "table" then
		return nil
	end
	local totals = {}
	local names = {}
	for key, value in pairs(stats) do
		value = public(value)
		local name = stat_label(key)
		if name and type(value) == "number" and value ~= 0 and value == math.floor(value) then
			if not totals[name] then
				names[#names + 1] = name
			end
			totals[name] = (totals[name] or 0) + value
		end
	end
	if #names == 0 then
		return nil
	end
	table.sort(names)
	local list = {}
	for i = 1, #names do
		local name = names[i]
		if totals[name] ~= 0 then
			list[#list + 1] = { stat = name, value = totals[name] }
		end
	end
	if #list == 0 then
		return nil
	end
	return list
end

local function item_spell(id)
	local reader = C_Item and C_Item.GetItemSpell or GetItemSpell
	if type(reader) ~= "function" then
		return nil
	end
	local ok, spellName, spellId = pcall(reader, id)
	if not ok then
		return nil
	end
	if type(spellName) == "table" then
		spellId = spellName.spellID or spellName.spellId
		spellName = spellName.spellName or spellName.name
	end
	spellName = text(spellName)
	spellId = public(spellId)
	if not spellName then
		return nil
	end
	local effect = { text = spellName, trigger = 0 }
	if type(spellId) == "number" and spellId > 0 then
		effect.spellId = spellId
	end
	return effect
end

local function tooltip_lines(id)
	if not C_TooltipInfo or type(C_TooltipInfo.GetItemByID) ~= "function" then
		return nil
	end
	local ok, data = pcall(C_TooltipInfo.GetItemByID, id)
	if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then
		return nil
	end
	return data.lines
end

-- The same global templates are compiled again for every tooltip line.
local patterns = {}

local function line_pattern(format)
	if type(format) ~= "string" or format == "" then
		return nil
	end
	local pattern = patterns[format]
	if not pattern then
		pattern = "^" .. format:gsub("([%(%)%.%+%-%*%?%[%]%^%$%%])", "%%%1"):gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)") .. "$"
		patterns[format] = pattern
	end
	return pattern
end

-- A tooltip line has a left and a right half. A weapon puts its damage on the left and "Speed 1.80" on the
-- right of the same line, so both halves are read as separate texts, left first.
local function line_texts(lines)
	local texts = {}
	if type(lines) ~= "table" then
		return texts
	end
	for index = 1, #lines do
		local line = lines[index]
		if type(line) == "table" then
			local left = text(line.leftText)
			local right = text(line.rightText)
			if left then
				texts[#texts + 1] = left
			end
			if right then
				texts[#texts + 1] = right
			end
		end
	end
	return texts
end

-- Tooltip lines already say Use / Equip / Chance on hit. GetItemSpell is only the Use spell.
local function tooltip_effects(lines)
	local prefixes = {
		{ format = ITEM_SPELL_TRIGGER_ONUSE, trigger = 0, fallback = "^Use: (.+)$" },
		{ format = ITEM_SPELL_TRIGGER_ONEQUIP, trigger = 1, fallback = "^Equip: (.+)$" },
		{ format = ITEM_SPELL_TRIGGER_ONPROC, trigger = 2, fallback = "^Chance on hit: (.+)$" },
	}
	local effects = {}
	local bodies = line_texts(lines)
	for index = 1, #bodies do
		local body = bodies[index]
		if body then
			for prefix = 1, #prefixes do
				local spec = prefixes[prefix]
				local captured
				local pattern = line_pattern(spec.format)
				if pattern then
					captured = body:match(pattern)
				end
				if not captured then
					captured = body:match(spec.fallback)
				end
				captured = text(captured)
				if captured then
					effects[#effects + 1] = { text = captured, trigger = spec.trigger }
					break
				end
			end
		end
	end
	if #effects == 0 then
		return nil
	end
	return effects
end

local function item_effects(id, lines)
	local listed = tooltip_effects(lines)
	local use = item_spell(id)
	if listed then
		if use and use.spellId then
			for index = 1, #listed do
				if listed[index].trigger == 0 and not listed[index].spellId then
					listed[index].spellId = use.spellId
				end
			end
		end
		return listed
	end
	if use then
		return { use }
	end
	return nil
end

local class_names

local function class_ids_by_name()
	if class_names then
		return class_names
	end
	local map = {}
	local reader = C_CreatureInfo and C_CreatureInfo.GetClassInfo or GetClassInfo
	if type(reader) ~= "function" then
		return map
	end
	for id = 1, 13 do
		local ok, info = pcall(reader, id)
		local name = ok and (type(info) == "table" and text(info.className) or text(info)) or nil
		if name then
			map[name] = id
		end
	end
	if next(map) ~= nil then
		class_names = map
	end
	return map
end

local function split_names(list)
	local delimiter = ", "
	if type(LIST_DELIMITER) == "string" and LIST_DELIMITER ~= "" then
		delimiter = LIST_DELIMITER
	end
	local names = {}
	local start = 1
	while true do
		local first, last = list:find(delimiter, start, true)
		if not first then
			names[#names + 1] = list:sub(start)
			break
		end
		names[#names + 1] = list:sub(start, first - 1)
		start = last + 1
	end
	return names
end

local race_names

local function race_ids_by_name()
	if race_names then
		return race_names
	end
	local map = {}
	local reader = C_CreatureInfo and C_CreatureInfo.GetRaceInfo or GetRaceInfo
	if type(reader) ~= "function" then
		return map
	end
	for id = 1, 90 do
		local ok, info = pcall(reader, id)
		local name = ok and (type(info) == "table" and text(info.raceName) or text(info)) or nil
		if name and not map[name] then
			map[name] = id
		end
	end
	if next(map) ~= nil then
		race_names = map
	end
	return map
end

local function restrictions_from(list, ids)
	if type(list) ~= "string" or list == "" or type(ids) ~= "table" then
		return nil
	end
	local found = {}
	local seen = {}
	for _, name in ipairs(split_names(list)) do
		name = text((name:gsub("^%s+", ""):gsub("%s+$", "")))
		local id = name and ids[name] or nil
		if type(id) == "number" and not seen[id] then
			seen[id] = true
			found[#found + 1] = { id = id, name = name }
		end
	end
	if #found == 0 then
		return nil
	end
	table.sort(found, function(left, right)
		return left.id < right.id
	end)
	return found
end

-- A scan of every id is thousands of calls. When it finds nothing, the data
-- has not loaded, and asking again on every item would repeat it. Wait first.
local RESCAN_SECONDS = 30

local function too_soon(missed_at)
	local now = type(GetTime) == "function" and GetTime() or nil
	return type(missed_at) == "number" and type(now) == "number" and now - missed_at < RESCAN_SECONDS, now
end

local faction_names
local faction_missed

local function faction_ids_by_name()
	if faction_names then
		return faction_names
	end
	local map = {}
	local waiting, now = too_soon(faction_missed)
	if waiting then
		return map
	end
	local reader = C_Reputation and C_Reputation.GetFactionDataByID or GetFactionInfoByID
	if type(reader) ~= "function" then
		return map
	end
	for id = 1, 2500 do
		local ok, info = pcall(reader, id)
		local name = ok and (type(info) == "table" and text(info.name) or text(info)) or nil
		if name and not map[name] then
			map[name] = id
		end
	end
	if next(map) ~= nil then
		faction_names = map
	else
		faction_missed = now
	end
	return map
end

local function standing_id(name)
	for id = 1, 8 do
		local label = text(_G["FACTION_STANDING_LABEL" .. id])
		if label and label == name then
			return id
		end
	end
end

local skill_names
local skill_missed

local function skill_ids_by_name()
	if skill_names then
		return skill_names
	end
	local map = {}
	local waiting, now = too_soon(skill_missed)
	if waiting then
		return map
	end
	local reader = C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID
	if type(reader) ~= "function" then
		return map
	end
	for id = 1, 2500 do
		local ok, info = pcall(reader, id)
		local name = ok and type(info) == "table" and text(info.professionName or info.name) or nil
		if name and not map[name] then
			map[name] = id
		end
	end
	if next(map) ~= nil then
		skill_names = map
	else
		skill_missed = now
	end
	return map
end

local function whole(value)
	value = public(value)
	value = type(value) == "string" and tonumber(value) or value
	if type(value) == "number" and value > 0 and value == math.floor(value) then
		return value
	end
end

-- One pass per tooltip. Each field used to walk every line on its own.
local function read_lines(lines)
	local set_name
	local bonuses
	local bonus_seen
	local class_list
	local race_list
	local rep_faction
	local rep_standing
	local skill_name
	local skill_value
	local equipped_count
	local equipped_label
	local unique_count
	local unique_label
	local armor
	local block
	local durability
	local damage_min
	local damage_max
	local speed
	if type(lines) ~= "table" then
		return {}
	end
	local set_pattern = line_pattern(ITEM_SET_NAME)
	local bonus_pattern = line_pattern(ITEM_SET_BONUS_GRAY)
	local class_pattern = line_pattern(ITEM_CLASSES_ALLOWED)
	local race_pattern = line_pattern(ITEM_RACES_ALLOWED)
	local rep_pattern = line_pattern(ITEM_REQ_REPUTATION)
	local skill_pattern = line_pattern(ITEM_MIN_SKILL)
	local equipped_count_pattern = line_pattern(ITEM_UNIQUE_EQUIPPABLE_MULTIPLE)
	local equipped_label_pattern = line_pattern(ITEM_UNIQUE_EQUIPPABLE)
	local unique_count_pattern = line_pattern(ITEM_UNIQUE_MULTIPLE)
	local unique_label_pattern = line_pattern(ITEM_UNIQUE)
	local armor_pattern = line_pattern(ARMOR_TEMPLATE)
	local damage_pattern = line_pattern(DAMAGE_TEMPLATE)
	local school_pattern = line_pattern(DAMAGE_TEMPLATE_WITH_SCHOOL)
	local single_pattern = line_pattern(SINGLE_DAMAGE_TEMPLATE)
	local speed_pattern = line_pattern(SPEED_TEMPLATE)
	local block_pattern = line_pattern(SHIELD_BLOCK_TEMPLATE)
	local durability_pattern = line_pattern(DURABILITY_TEMPLATE)
	local bodies = line_texts(lines)
	for index = 1, #bodies do
		local body = bodies[index]
		if body then
			if not set_name and set_pattern then
				set_name = text(body:match(set_pattern))
			end
			if bonus_pattern then
				local count, bonus = body:match(bonus_pattern)
				count = tonumber(count)
				bonus = text(bonus)
				if bonus and type(count) == "number" and count > 0 and count == math.floor(count) then
					if not bonus_seen then
						bonus_seen = {}
						bonuses = {}
					end
					if not bonus_seen[count] then
						bonus_seen[count] = true
						bonuses[#bonuses + 1] = { name = bonus, threshold = count, text = bonus }
					end
				end
			end
			if not class_list and class_pattern then
				class_list = text(body:match(class_pattern))
			end
			if not race_list and race_pattern then
				race_list = text(body:match(race_pattern))
			end
			if not rep_faction and rep_pattern then
				local faction, standing = body:match(rep_pattern)
				faction = text(faction)
				standing = text(standing)
				if faction and standing then
					rep_faction = faction
					rep_standing = standing
				end
			end
			if not skill_name and skill_pattern then
				local name, value = body:match(skill_pattern)
				name = text(name)
				value = public(value)
				value = type(value) == "string" and tonumber(value) or value
				if name and type(value) == "number" and value > 0 and value == math.floor(value) then
					skill_name = name
					skill_value = value
				end
			end
			if not equipped_count and equipped_count_pattern then
				equipped_count = whole(body:match(equipped_count_pattern))
			end
			if not equipped_label and equipped_label_pattern and body:match(equipped_label_pattern) then
				equipped_label = true
			end
			if not unique_count and unique_count_pattern then
				unique_count = whole(body:match(unique_count_pattern))
			end
			if not unique_label and unique_label_pattern and body:match(unique_label_pattern) then
				unique_label = true
			end
			if not armor and armor_pattern then
				armor = whole(body:match(armor_pattern))
			end
			if not damage_min then
				if damage_pattern then
					local low, high = body:match(damage_pattern)
					low, high = whole(low), whole(high)
					if low and high and high >= low then
						damage_min, damage_max = low, high
					end
				end
				if not damage_min and school_pattern then
					local low, high = body:match(school_pattern)
					low, high = whole(low), whole(high)
					if low and high and high >= low then
						damage_min, damage_max = low, high
					end
				end
				if not damage_min and single_pattern then
					local value = whole(body:match(single_pattern))
					if value then
						damage_min, damage_max = value, value
					end
				end
			end
			if not speed and speed_pattern then
				local raw = body:match(speed_pattern)
				raw = public(raw)
				local seconds = type(raw) == "string" and tonumber(raw) or raw
				if type(seconds) == "number" and seconds > 0 then
					local hundredths = math.floor(seconds * 100 + 0.5)
					if hundredths > 0 then
						speed = hundredths
					end
				end
			end
			if not block and block_pattern then
				block = whole(body:match(block_pattern))
			end
			if not durability and durability_pattern then
				local _, maximum = body:match(durability_pattern)
				durability = whole(maximum)
			end
		end
	end
	if bonuses then
		table.sort(bonuses, function(left, right)
			return left.threshold < right.threshold
		end)
	end
	local classes = class_list and restrictions_from(class_list, class_ids_by_name()) or nil
	local races = race_list and restrictions_from(race_list, race_ids_by_name()) or nil
	local reputation
	if rep_faction then
		local standing = standing_id(rep_standing)
		local faction_id = faction_ids_by_name()[rep_faction]
		if type(standing) == "number" and type(faction_id) == "number" then
			Everlook.world.store("factions", {
				id = faction_id,
				name = rep_faction,
			})
			reputation = { { factionId = faction_id, standing = standing } }
		end
	end
	local skill_id
	local skill_required
	if skill_name then
		local found = skill_ids_by_name()[skill_name]
		if type(found) == "number" then
			Everlook.world.store("skillLines", {
				id = found,
				name = skill_name,
				isProfession = true,
			})
			skill_id = found
			skill_required = skill_value
		end
	end
	local unique_total
	local unique_equipped
	if equipped_count then
		unique_total = equipped_count
		unique_equipped = true
	elseif equipped_label then
		unique_total = 1
		unique_equipped = true
	elseif unique_count then
		unique_total = unique_count
		unique_equipped = false
	elseif unique_label then
		unique_total = 1
		unique_equipped = false
	end
	return {
		setName = set_name,
		bonuses = bonuses,
		classes = classes,
		races = races,
		reputation = reputation,
		skillId = skill_id,
		skillValue = skill_required,
		uniqueCount = unique_total,
		uniqueEquipped = unique_equipped,
		armor = armor,
		damageMin = damage_min,
		damageMax = damage_max,
		speed = speed,
		block = block,
		durability = durability,
	}
end

local function item_info(id)
	if not C_Item or not C_Item.GetItemInfo then
		return nil
	end
	local name, link, quality, itemLevel, minLevel, className, subclassName, stackCount, equipLoc, icon, sellPrice, classId, subclassId, bindType, _, setId, reagent = C_Item.GetItemInfo(id)
	name = public(name)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	setId = public(setId)
	if type(setId) ~= "number" or setId <= 0 or setId ~= math.floor(setId) then
		setId = nil
	end
	classId = public(classId)
	local lines = tooltip_lines(id)
	local fields = read_lines(lines)
	local setName = fields.setName
	local bonuses = fields.bonuses
	local classes = fields.classes
	local races = fields.races
	local reputation = fields.reputation
	local uniqueCount = fields.uniqueCount
	local uniqueEquipped = fields.uniqueEquipped
	local requiredSkillLineId = fields.skillId
	local requiredSkillValue = fields.skillValue
	local armor = fields.armor
	local damageMin = fields.damageMin
	local damageMax = fields.damageMax
	local weaponSpeed = fields.speed
	local block = fields.block
	local durability = fields.durability
	reagent = public(reagent)
	if reagent ~= true and reagent ~= false then
		reagent = nil
	end
	return {
		id = id,
		name = name,
		setId = setId,
		setName = setName,
		quality = public(quality),
		itemLevel = public(itemLevel),
		minLevel = public(minLevel),
		className = text(className),
		subclassName = text(subclassName),
		equipLoc = text(equipLoc),
		stackCount = public(stackCount),
		icon = public(icon),
		sellPrice = public(sellPrice),
		classId = classId,
		subclassId = public(subclassId),
		bindType = public(bindType),
		isCraftingReagent = reagent,
		stats = item_stats(id, link),
		effects = item_effects(id, lines),
		setBonuses = bonuses,
		classRestrictions = classes,
		raceRestrictions = races,
		requiredReputations = reputation,
		uniqueCount = uniqueCount,
		uniqueEquipped = uniqueEquipped,
		requiredSkillLineId = requiredSkillLineId,
		requiredSkillValue = requiredSkillValue,
		armor = armor,
		damageMin = damageMin,
		damageMax = damageMax,
		weaponSpeed = weaponSpeed,
		block = block,
		durability = durability,
	}, type(lines) == "table" and #lines > 0, type(lines) == "table" and #lines or 0
end

local function request(id)
	if C_Item and C_Item.RequestLoadItemDataByID then
		C_Item.RequestLoadItemDataByID(id)
	end
end

-- An item the addon has not read yet costs a tooltip and a pass over its
-- lines. A loot window, a vendor or a bag scan can hand over dozens at once,
-- so they wait in line and are read a millisecond at a time. Without a timer
-- the item is read on the spot.
local WORK_MS = 1
local waiting = {}
local waiting_first = 1
local waiting_last = 0
local waiting_sources = {}
local draining = false

local function drain()
	local started = debugprofilestop and debugprofilestop() or nil
	while waiting_first <= waiting_last do
		local job = waiting[waiting_first]
		waiting[waiting_first] = nil
		waiting_first = waiting_first + 1
		local by_source = waiting_sources[job[1]]
		if by_source then
			by_source[job[2]] = nil
			if next(by_source) == nil then
				waiting_sources[job[1]] = nil
			end
		end
		Everlook.items.record(job[1], job[2], job[3], job[4], true)
		if not started or debugprofilestop() - started >= WORK_MS then
			break
		end
	end
	if waiting_first > waiting_last then
		waiting_first, waiting_last = 1, 0
		draining = false
		return
	end
	C_Timer.After(0, drain)
end

local function wait_for_turn(id, source, name, startsQuestId)
	if not (C_Timer and C_Timer.After) then
		return false
	end
	local by_source = waiting_sources[id]
	local queued = by_source and by_source[source]
	if queued then
		queued[3] = queued[3] or name
		queued[4] = queued[4] or startsQuestId
		return true
	end
	if not by_source then
		by_source = {}
		waiting_sources[id] = by_source
	end
	local job = { id, source, name, startsQuestId }
	by_source[source] = job
	waiting_last = waiting_last + 1
	waiting[waiting_last] = job
	if not draining then
		draining = true
		C_Timer.After(0, drain)
	end
	return true
end

function Everlook.items.record(id, source, name, startsQuestId, now)
	if type(id) ~= "number" then
		return
	end
	source = source or "bag"
	if type(startsQuestId) ~= "number" or startsQuestId <= 0 or startsQuestId ~= math.floor(startsQuestId) then
		startsQuestId = pending_quest[id]
	end
	if type(startsQuestId) ~= "number" or startsQuestId <= 0 or startsQuestId ~= math.floor(startsQuestId) then
		startsQuestId = nil
	end
	local quest_is_new = startsQuestId ~= nil and noted_quests[id] ~= startsQuestId
	if known[id] then
		pending[id] = nil
		local have = noted_sources[id]
		if have and have[source] and not quest_is_new then
			return
		end
		note_source(id, source)
		local row = { id = id, sources = { source } }
		if quest_is_new then
			noted_quests[id] = startsQuestId
			row.startsQuestId = startsQuestId
		end
		Everlook.world.store("items", row)
		return
	end
	if not now and wait_for_turn(id, source, name, startsQuestId) then
		return
	end
	local observation, loaded, line_count = item_info(id)
	if not observation then
		if (type(name) == "string" and name ~= "") or quest_is_new then
			observation = { id = id }
			if type(name) == "string" and name ~= "" then
				observation.name = name
			end
		else
			pending[id] = source
			if startsQuestId then
				pending_quest[id] = startsQuestId
			end
			request(id)
			return
		end
	else
		pending[id] = nil
		if loaded then
			if seen_lines[id] == line_count then
				known[id] = true
			else
				seen_lines[id] = line_count
			end
		end
	end
	if quest_is_new then
		noted_quests[id] = startsQuestId
		pending_quest[id] = nil
		observation.startsQuestId = startsQuestId
	end
	observation.sources = { source }
	note_source(id, source)
	Everlook.world.store("items", observation)
end

local function bag_range()
	local first = 0
	local last = 4
	if Enum and Enum.BagIndex then
		first = Enum.BagIndex.Backpack or first
		last = Enum.BagIndex.Bag_4 or last
		if Enum.BagIndex.ReagentBag then
			last = Enum.BagIndex.ReagentBag
		end
	end
	return first, last
end

-- The info table is a full item record. The id alone is enough, and an empty
-- slot returns nil without building that record.
local function slot_item_id(bag, slot)
	if not C_Container then
		return nil
	end
	local read_id = C_Container.GetContainerItemID
	if type(read_id) == "function" then
		local id = read_id(bag, slot)
		if id == nil then
			return nil
		end
		if type(id) == "number" and public(id) then
			return id
		end
	end
	if type(C_Container.GetContainerItemInfo) ~= "function" then
		return nil
	end
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if type(info) ~= "table" then
		return nil
	end
	local id = public(info.itemID)
	if type(id) == "number" then
		return id
	end
	return Everlook.items.id_from_link(info.hyperlink)
end

function Everlook.items.scan_equipped()
	if not GetInventoryItemID then
		return
	end
	for slot = 1, 19 do
		local id = public(GetInventoryItemID("player", slot))
		if type(id) == "number" and id > 0 then
			Everlook.items.record(id, "equipped")
		end
	end
end

local function slot_quest(bag, slot)
	local reader = C_Container.GetContainerItemQuestInfo
	if type(reader) ~= "function" then
		return nil, nil, false
	end
	local ok, info = pcall(reader, bag, slot)
	if not ok or type(info) ~= "table" then
		return nil, nil, false
	end
	local questId = public(info.questID)
	if type(questId) ~= "number" or questId <= 0 or questId ~= math.floor(questId) then
		questId = nil
	end
	if questId and info.isActive == false then
		return questId, false, true
	end
	if info.isQuestItem then
		return questId, true, true
	end
	return nil, false, true
end

-- A bag update dirties one bag. A slot that still holds the same plain item skips the
-- quest lookup once that item is known. A quest item whose flags did not
-- change does not rebuild the quest. A failed lookup is not remembered, so
-- the next update can retry.
local slot_state = {}

local function plain_settled(id)
	local have = noted_sources[id]
	return known[id] and have and have.bag or false
end

local function same_slot(prev, id, questId, isQuestItem)
	return prev and prev[1] == id and prev[4]
		and prev[2] == (questId or false)
		and prev[3] == (isQuestItem and true or false)
end

local function save_slot(bag, slot, id, questId, isQuestItem)
	local by_slot = slot_state[bag]
	if not by_slot then
		by_slot = {}
		slot_state[bag] = by_slot
	end
	local row = by_slot[slot]
	if not row then
		row = {}
		by_slot[slot] = row
	end
	row[1] = id
	row[2] = questId or false
	row[3] = isQuestItem and true or false
	row[4] = true
end

local function record_slot(id, questId, isQuestItem, items_only)
	if questId and not isQuestItem then
		Everlook.items.record(id, "bag", nil, questId)
		if not items_only and Everlook.quests and Everlook.quests.note_item_starter then
			Everlook.quests.note_item_starter(questId, id)
		end
		return
	end
	Everlook.items.record(id, isQuestItem and "quest" or "bag")
	if not items_only and isQuestItem and questId and Everlook.quests and Everlook.quests.note_required_item then
		Everlook.quests.note_required_item(questId, id)
	end
end

local function scan_bag(bag)
	local slots = C_Container.GetContainerNumSlots(bag) or 0
	local by_slot = slot_state[bag]
	for slot = 1, slots do
		local id = slot_item_id(bag, slot)
		local prev = by_slot and by_slot[slot]
		if not id then
			if by_slot then
				by_slot[slot] = nil
			end
		elseif not (prev and prev[1] == id and prev[4] and not prev[2] and not prev[3] and plain_settled(id)) then
			local questId, isQuestItem, read_ok = slot_quest(bag, slot)
			if read_ok and same_slot(prev, id, questId, isQuestItem) then
				if not known[id] then
					record_slot(id, questId, isQuestItem, true)
				end
			else
				if read_ok then
					save_slot(bag, slot, id, questId, isQuestItem)
				end
				record_slot(id, questId, isQuestItem)
			end
		end
	end
end

function Everlook.items.scan_bags()
	if not C_Container or not C_Container.GetContainerNumSlots then
		return
	end
	local first, last = bag_range()
	for bag = first, last do
		scan_bag(bag)
	end
end

-- A bag update names the bag that changed, then one delayed event walks it.
-- The other bags stay as they were, so the slot walk can skip them.
local dirty_bags
local scan_all = false

local function note_bag(bag)
	if type(bag) ~= "number" then
		scan_all = true
		return
	end
	if not dirty_bags then
		dirty_bags = {}
	end
	dirty_bags[bag] = true
end

local function scan_changed()
	if scan_all or not dirty_bags or not C_Container or not C_Container.GetContainerNumSlots then
		scan_all = false
		dirty_bags = nil
		Everlook.items.scan_bags()
		return
	end
	local first, last = bag_range()
	for bag = first, last do
		if dirty_bags[bag] then
			scan_bag(bag)
		end
	end
	dirty_bags = nil
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
frame:SetScript("OnEvent", function(_, event, first, second)
	if event == "BAG_UPDATE" then
		note_bag(first)
		return
	end
	if event == "BAG_UPDATE_DELAYED" then
		scan_changed()
		return
	end
	if event == "PLAYER_ENTERING_WORLD" then
		dirty_bags = nil
		scan_all = false
		Everlook.items.scan_bags()
		return
	end
	if event == "GET_ITEM_INFO_RECEIVED" and second ~= false and pending[first] then
		Everlook.items.record(first, pending[first])
	end
end)
