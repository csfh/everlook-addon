local addonName, Everlook = ...

-- Module addons are separate addons, and a global is the only table they can
-- share with this one. Everlook.module and Everlook.island are the supported
-- interface for other addons. The rest is internal and can change.
_G.Everlook = Everlook

Everlook.world = {}

local NULL = {}
local rows = {}
-- True once the collection lives in pages. `rows` is then empty, or while an
-- older whole-collection copy is still the saved one, that copy.
local paged = false
-- True when the saved pages cannot be read this session, so the saved upload is left as it is.
local keep_upload = false
local dirty = false
-- Tallies ride along on the next real edit, or on logout when the file is written.
local counts_dirty = false
-- Moves on every counter or pin count that changes without the row "changing",
-- so a store can tell the segment holding it that it has new numbers to save.
local bumped = 0
local session_new = 0
local session_reported = 0
local row_total = 0
local bucket_totals = {}
-- Bumped when a row appears or a name a listing prints changes. The collected
-- listings are rebuilt only when it moves.
local collected_version = 0

local BUCKETS = {
	"maps", "factions", "spells", "skillLines", "currencies", "items", "objects", "npcs", "quests", "talents",
	"recipes", "kills", "drops", "vendors", "merchantCosts", "objectLoot", "fishingLoot", "npcSpells",
	"npcFactions", "taxiNodes", "taxiRoutes",
}

local COLUMNS = {
	maps = { "id", "name", "parentMapId", "mapType", "areas" },
	factions = { "id", "name", "parentFactionId", "side" },
	spells = { "id", "name", "castTimeMs", "rangeMax", "icon", "rank", "description", "cooldownMs", "powerType", "powerCost", "school", "rangeMin" },
	skillLines = { "id", "name", "isProfession", "isSecondary" },
	currencies = { "id", "name", "icon" },
	items = { "id", "name", "quality", "itemLevel", "minLevel", "classId", "className", "subclassId", "subclassName", "equipLoc", "bindType", "stackCount", "sellPrice", "buyPrice", "icon", "setId", "setName", "isCraftingReagent", "teachesSpellId", "startsQuestId", "stats", "effects", "setBonuses", "classRestrictions", "raceRestrictions", "requiredReputations", "uniqueCount", "uniqueEquipped", "requiredSkillLineId", "requiredSkillValue", "armor", "damageMin", "damageMax", "weaponSpeed", "block", "durability", "locations", "sources" },
	objects = { "id", "name", "objectType", "locations", "sources" },
	npcs = { "id", "name", "subtitle", "minLevel", "maxLevel", "classification", "creatureType", "creatureFamily", "factionGroup", "factionId", "reactionAlliance", "reactionHorde", "maxHealth", "maxMana", "isTrainer", "trainerSpells", "locations", "sources", "gossip" },
	quests = { "id", "title", "level", "requiredLevel", "suggestedGroup", "frequency", "description", "objectiveText", "progressText", "completionText", "questType", "factionSide", "mapId", "objectives", "giverId", "turnInId", "starters", "enders", "rewards", "locations", "sources", "requires", "requiredItems", "questLineId", "questLineName" },
	talents = { "id", "name", "icon", "classId", "treeId", "treeName", "nodeId", "tier", "column", "maxRank", "rank", "spellId", "prereqTier", "prereqColumn" },
	recipes = { "spellId", "name", "skillLineId", "craftedItemId", "craftedMinimum", "craftedMaximum", "orangeSkill", "yellowSkill", "greenSkill", "greySkill", "reagents" },
	kills = { "npcId", "kills", "loots", "pickpockets", "skins" },
	drops = { "npcId", "itemId", "drops", "quantity" },
	vendors = { "npcId", "itemId", "price", "quantity", "stock", "extendedCost" },
	merchantCosts = { "npcId", "itemId", "position", "costItemId", "currencyId", "amount" },
	objectLoot = { "objectId", "itemId", "opens", "drops", "quantity" },
	fishingLoot = { "mapId", "areaId", "itemId", "casts", "drops", "areaName" },
	npcSpells = { "npcId", "spellId", "casts" },
	npcFactions = { "npcId", "factionId", "reputation" },
	taxiNodes = { "id", "name", "mapId", "x", "y", "factionSide" },
	taxiRoutes = { "fromNodeId", "toNodeId", "cost", "durationSeconds", "hops" },
}

local KEYS = {
	maps = { "id" }, factions = { "id" }, spells = { "id" }, skillLines = { "id" }, currencies = { "id" },
	items = { "id" }, objects = { "id" }, npcs = { "id" }, quests = { "id" }, talents = { "id" }, taxiNodes = { "id" },
	recipes = { "spellId" }, kills = { "npcId" }, npcFactions = { "npcId", "factionId" },
	drops = { "npcId", "itemId" }, vendors = { "npcId", "itemId" },
	merchantCosts = { "npcId", "itemId", "position" }, objectLoot = { "objectId", "itemId" },
	fishingLoot = { "mapId", "areaId", "itemId" }, npcSpells = { "npcId", "spellId" },
	taxiRoutes = { "fromNodeId", "toNodeId" },
}

local COUNTERS = {
	drops = true, kills = true, loots = true, pickpockets = true, skins = true,
	opens = true, casts = true, quantity = true, seen = true,
}

local SOURCES = { target = 1, mouseover = 2, nameplate = 3, merchant = 4, loot = 5 }
local pin_buckets = { quests = true, objects = true, npcs = true, taxiNodes = true, vendors = true }
local pin_watchers = {}

-- Mouseover and casts check every unit guid. Reject the wrong kind, then
-- read the entry id in place so the lookup does not allocate.
function Everlook.world.guid_id(guid, kind)
	if not Everlook.world.usable(guid) or type(guid) ~= "string" or type(kind) ~= "string" then
		return nil
	end
	local length = #kind
	if #guid <= length or guid:byte(length + 1) ~= 45 then
		return nil
	end
	for index = 1, length do
		if guid:byte(index) ~= kind:byte(index) then
			return nil
		end
	end
	local hyphens = 1
	local start
	local guid_length = #guid
	for index = length + 2, guid_length do
		local byte = guid:byte(index)
		if byte == 45 then
			hyphens = hyphens + 1
			if hyphens == 5 then
				start = index + 1
				break
			end
		end
	end
	if not start or start > guid_length then
		return nil
	end
	local id = 0
	local digits = 0
	for index = start, guid_length do
		local byte = guid:byte(index)
		if byte == 45 then
			break
		end
		if byte < 48 or byte > 57 then
			return nil
		end
		id = id * 10 + (byte - 48)
		digits = digits + 1
	end
	if digits == 0 then
		return nil
	end
	return id
end

function Everlook.say(text)
	if type(text) ~= "string" or text == "" then
		return
	end
	local frame = DEFAULT_CHAT_FRAME
	if type(frame) ~= "table" or type(frame.AddMessage) ~= "function" then
		return
	end
	frame:AddMessage("Everlook: " .. text)
end

function Everlook.world.usable(value)
	if issecretvalue and issecretvalue(value) then
		return false
	end
	return true
end

local function usable(value)
	return Everlook.world.usable(value)
end

local function get_row(bucket, key)
	if paged then
		return Everlook.pages.get(bucket, key)
	end
	local bucket_rows = rows[bucket]
	return bucket_rows and bucket_rows[key]
end

local function each_row(bucket, visitor)
	if paged then
		Everlook.pages.each(bucket, visitor)
		return
	end
	local bucket_rows = rows[bucket]
	if bucket_rows then
		for key, row in pairs(bucket_rows) do
			visitor(key, row)
		end
	end
end

local function copy_location(location)
	if type(location) ~= "table" or not usable(location.mapId) then
		return nil
	end
	return {
		mapId = location.mapId,
		x = location.x,
		y = location.y,
		seen = location.seen or 1,
		zone = location.zone,
		subzone = location.subzone,
		role = location.role,
	}
end

local function same_pin(left, right)
	return left.mapId == right.mapId
		and left.x == right.x
		and left.y == right.y
		and (left.role or "") == (right.role or "")
end

-- A short list is quicker to scan than to index. A long one gets an index of
-- its pins, so a sighting costs one lookup however many places a row holds.
-- The index lives beside the list, never in it, so it is never saved. The
-- table is not weak: the collector would have to sweep a weak table in one
-- step at the end of every garbage cycle, and the lists live all session.
local PIN_SCAN_LIMIT = 12
local pin_indexes = {}

local function pin_key(location)
	local map_id, x, y = location.mapId, location.x, location.y
	if type(map_id) == "number" and type(x) == "number" and type(y) == "number"
		and map_id >= 0 and map_id < 100000 and x >= 0 and x <= 1000 and y >= 0 and y <= 1000
		and x % 1 == 0 and y % 1 == 0 then
		return map_id * 1002001 + x * 1001 + y
	end
	return tostring(map_id) .. ":" .. (type(x) == "number" and string.format("%.17g", x) or tostring(x))
		.. ":" .. (type(y) == "number" and string.format("%.17g", y) or tostring(y))
end

local function pin_index(list, owner)
	local holder = paged and owner and Everlook.pages.page_of(owner) or nil
	local indexes = pin_indexes
	if holder then
		indexes = holder.pins or {}
		holder.pins = indexes
	end
	local index = indexes[list]
	if index and index.count == #list then
		return index
	end
	index = { count = 0 }
	for position = 1, #list do
		local pin = list[position]
		if type(pin) == "table" then
			local role = pin.role or ""
			local by_role = index[role]
			if not by_role then
				by_role = {}
				index[role] = by_role
			end
			local key = pin_key(pin)
			if by_role[key] == nil then
				by_role[key] = pin
			end
		end
	end
	index.count = #list
	indexes[list] = index
	return index
end

local function find_pin(list, index, location)
	if index then
		local by_role = index[location.role or ""]
		return by_role and by_role[pin_key(location)]
	end
	for position = 1, #list do
		if same_pin(list[position], location) then
			return list[position]
		end
	end
end

-- Repeat pins only add to seen. That count is updated in place so a sighting
-- does not copy the whole list.
local function merge_locations(existing, incoming, owner)
	local kind = "none"
	if type(incoming) ~= "table" then
		return existing, kind
	end
	if type(existing) ~= "table" then
		existing = {}
	end
	for i = 1, #incoming do
		local location = incoming[i]
		if type(location) == "table" and usable(location.mapId) then
			local index = #existing > PIN_SCAN_LIMIT and pin_index(existing, owner) or nil
			local found = find_pin(existing, index, location)
			if found then
				local bump = location.seen or 1
				if bump ~= 0 then
					found.seen = (found.seen or 1) + bump
					if kind ~= "place" then
						kind = "seen"
					end
				end
			else
				local copy = copy_location(location)
				if copy then
					existing[#existing + 1] = copy
					kind = "place"
					if index then
						local role = copy.role or ""
						local by_role = index[role]
						if not by_role then
							by_role = {}
							index[role] = by_role
						end
						by_role[pin_key(copy)] = copy
						index.count = #existing
					end
				end
			end
		end
	end
	return existing, kind
end

local function merge_sources(existing, incoming)
	local list = {}
	local seen = {}
	local function add(sources)
		if type(sources) ~= "table" then
			return
		end
		for i = 1, #sources do
			local source = sources[i]
			if type(source) == "string" and source ~= "" and not seen[source] then
				seen[source] = true
				list[#list + 1] = source
			end
		end
	end
	add(existing)
	add(incoming)
	return list
end

local function same(left, right)
	if left == right then
		return true
	end
	if type(left) ~= "table" or type(right) ~= "table" then
		return false
	end
	local seen = {}
	for key, value in pairs(left) do
		if not same(value, right[key]) then
			return false
		end
		seen[key] = true
	end
	for key in pairs(right) do
		if not seen[key] then
			return false
		end
	end
	return true
end

local function has_location(locations)
	if type(locations) ~= "table" then
		return false
	end
	for index = 1, #locations do
		local location = locations[index]
		if type(location) == "table" and usable(location.mapId) then
			return true
		end
	end
	return false
end

-- Source lists stay short. Scanning them avoids a set on every store.
local function has_new_source(existing, incoming)
	if type(incoming) ~= "table" then
		return false
	end
	for index = 1, #incoming do
		local source = incoming[index]
		if type(source) == "string" and source ~= "" and usable(source) then
			local found = false
			if type(existing) == "table" then
				for have = 1, #existing do
					if existing[have] == source then
						found = true
						break
					end
				end
			end
			if not found then
				return true
			end
		end
	end
	return false
end

local function merge_areas(existing, incoming)
	local list = {}
	local seen = {}
	local function add(entries, mark)
		if type(entries) ~= "table" then
			return false
		end
		local grew = false
		for index = 1, #entries do
			local area = entries[index]
			if type(area) == "table" and type(area.id) == "number" and usable(area.id) and area.id > 0 and not seen[area.id] then
				local name = area.name
				if type(name) ~= "string" or name == "" or not usable(name) then
					name = nil
				end
				seen[area.id] = true
				list[#list + 1] = { id = area.id, name = name }
				if mark then
					grew = true
				end
			end
		end
		return grew
	end
	add(existing, false)
	local grew = add(incoming, true)
	return list, grew
end

-- A later sighting may know more than an earlier one, never less. Lists that a
-- sighting read only in part do not replace a fuller list, an empty one never
-- replaces anything, and a map such as a quest's rewards is merged field by field.
local function is_list(value)
	return type(value) == "table" and (next(value) == nil or value[1] ~= nil)
end

local function enrich(stored, incoming)
	if type(stored) ~= "table" or type(incoming) ~= "table" then
		return incoming
	end
	if is_list(stored) or is_list(incoming) then
		if #incoming < #stored then
			return stored
		end
		return incoming
	end
	local merged = {}
	for key, value in pairs(stored) do
		merged[key] = value
	end
	for key, value in pairs(incoming) do
		merged[key] = enrich(stored[key], value)
	end
	return merged
end

-- Who starts or ends a quest accumulates: the same quest can be given by more than one creature or object.
local function endpoint_key(endpoint)
	return tostring(type(endpoint) == "table" and endpoint.type or "") .. ":" .. tostring(type(endpoint) == "table" and endpoint.id or "")
end

local function union_endpoints(stored, incoming)
	if not is_list(stored) or not is_list(incoming) then
		return incoming
	end
	local merged, known = {}, {}
	for index = 1, #stored do
		known[endpoint_key(stored[index])] = true
		merged[#merged + 1] = stored[index]
	end
	for index = 1, #incoming do
		local key = endpoint_key(incoming[index])
		if not known[key] then
			known[key] = true
			merged[#merged + 1] = incoming[index]
		end
	end
	return merged
end

-- "Unknown NPC 12" and "Talent 3" stand in until a name is read, so they never replace one.
local function placeholder_name(value)
	return type(value) == "string" and (value:match("^Unknown .+ %d+$") ~= nil or value:match("^Talent %d+$") ~= nil)
end

-- What a creature is only ever reads up: a vignette calls a creature rare, which must not undo an elite or a world boss.
local CLASSIFICATION_RANK = { trivial = 0, minus = 1, normal = 2, rare = 3, elite = 4, rareelite = 5, worldboss = 6 }

local function lowers_classification(stored, incoming)
	local before, after = CLASSIFICATION_RANK[stored], CLASSIFICATION_RANK[incoming]
	return before ~= nil and after ~= nil and after < before
end

-- Fields that look like counters but are plain values in these buckets.
local PLAIN_VALUES = { vendors = { quantity = true } }

-- Identical restatements must not mark the world dirty. A dirty flag rebuilds
-- and compresses the whole saved document on the next flush.
local function merge(target, source, plain)
	local changed = false
	for key, value in pairs(source) do
		if usable(value) then
			if key == "minLevel" and type(value) == "number" then
				local next_level = value
				if type(target.minLevel) == "number" then
					next_level = math.min(target.minLevel, value)
				end
				if target.minLevel ~= next_level then
					target.minLevel = next_level
					changed = true
				end
			elseif key == "maxLevel" and type(value) == "number" then
				local next_level = value
				if type(target.maxLevel) == "number" then
					next_level = math.max(target.maxLevel, value)
				end
				if target.maxLevel ~= next_level then
					target.maxLevel = next_level
					changed = true
				end
			elseif COUNTERS[key] and not (plain and plain[key]) and type(value) == "number" and type(target[key]) == "number" then
				if value ~= 0 then
					target[key] = target[key] + value
					counts_dirty = true
					bumped = bumped + 1
				end
			elseif key == "locations" then
				if has_location(value) then
					local merged, kind = merge_locations(target.locations, value, target)
					if kind == "place" then
						target.locations = merged
						changed = true
					elseif kind == "seen" then
						counts_dirty = true
						bumped = bumped + 1
					end
				end
			elseif key == "sources" then
				if has_new_source(target.sources, value) then
					target.sources = merge_sources(target.sources, value)
					changed = true
				end
			elseif key == "areas" then
				local merged, grew = merge_areas(target.areas, value)
				if grew then
					target.areas = merged
					changed = true
				end
			elseif type(value) == "string" then
				local keeps_name = key == "name" and placeholder_name(value) and type(target.name) == "string" and target.name ~= "" and not placeholder_name(target.name)
				local keeps_class = key == "classification" and lowers_classification(target.classification, value)
				if value ~= "" and target[key] ~= value and not keeps_name and not keeps_class then
					target[key] = value
					changed = true
				end
			elseif type(value) == "table" then
				local merged
				if key == "starters" or key == "enders" then
					merged = union_endpoints(target[key], value)
				else
					merged = enrich(target[key], value)
				end
				if not same(target[key], merged) then
					target[key] = merged
					changed = true
				end
			elseif not same(target[key], value) then
				target[key] = value
				changed = true
			end
		end
	end
	return changed
end

-- Joined ids repeat on casts, drops, and vendor rows. The scratch list and
-- the cache keep those stores off the string allocator.
local key_scratch = {}
local key_nodes = {}

local function row_key(bucket, row)
	local keys = KEYS[bucket]
	if not keys then
		return nil
	end
	local count = #keys
	local first = row[keys[1]]
	if type(first) ~= "number" or not usable(first) then
		return nil
	end
	-- Most rows are keyed by one id. The number needs no extra string.
	if count == 1 then
		return first
	end
	key_scratch[1] = first
	for i = 2, count do
		local value = row[keys[i]]
		if type(value) ~= "number" or not usable(value) then
			return nil
		end
		key_scratch[i] = value
	end
	local node = key_nodes[bucket]
	if not node then
		node = {}
		key_nodes[bucket] = node
	end
	for i = 1, count - 1 do
		local part = key_scratch[i]
		local child = node[part]
		if not child then
			child = {}
			node[part] = child
		end
		node = child
	end
	local last = key_scratch[count]
	local cached = node[last]
	if type(cached) == "string" then
		return cached
	end
	for i = 1, count do
		key_scratch[i] = tostring(key_scratch[i])
	end
	cached = table.concat(key_scratch, ":", 1, count)
	node[last] = cached
	return cached
end

local LIST_LABELS = {
	maps = "Maps",
	factions = "Factions",
	spells = "Spells",
	skillLines = "Professions",
	currencies = "Currencies",
	items = "Items",
	objects = "Objects",
	npcs = "Creatures",
	quests = "Quests",
	talents = "Talents",
	recipes = "Recipes",
	kills = "Kills",
	drops = "Drops",
	vendors = "Vendors",
	merchantCosts = "Vendor costs",
	objectLoot = "Object loot",
	fishingLoot = "Fishing",
	npcSpells = "Creature spells",
	npcFactions = "Creature factions",
	taxiNodes = "Flight masters",
	taxiRoutes = "Flight paths",
}

local LIST_PARTS = {
	maps = { { name = "name", id = "id" } },
	factions = { { name = "name", id = "id" } },
	spells = { { name = "name", id = "id" } },
	skillLines = { { name = "name", id = "id" } },
	currencies = { { name = "name", id = "id" } },
	items = { { name = "name", id = "id" } },
	objects = { { name = "name", id = "id" } },
	npcs = { { name = "name", id = "id" } },
	quests = { { name = "title", id = "id" } },
	talents = { { name = "name", id = "id" } },
	recipes = { { name = "name", id = "spellId" } },
	kills = { { id = "npcId", bucket = "npcs" } },
	drops = { { id = "npcId", bucket = "npcs" }, { id = "itemId", bucket = "items" } },
	vendors = { { id = "npcId", bucket = "npcs" }, { id = "itemId", bucket = "items" } },
	merchantCosts = {
		{ id = "npcId", bucket = "npcs" },
		{ id = "itemId", bucket = "items" },
		{ id = "costItemId", bucket = "items" },
		{ id = "currencyId", bucket = "currencies" },
	},
	objectLoot = { { id = "objectId", bucket = "objects" }, { id = "itemId", bucket = "items" } },
	fishingLoot = {
		{ name = "areaName", id = "mapId", bucket = "maps" },
		{ id = "itemId", bucket = "items" },
	},
	npcSpells = { { id = "npcId", bucket = "npcs" }, { id = "spellId", bucket = "spells" } },
	npcFactions = { { id = "npcId", bucket = "npcs" }, { id = "factionId", bucket = "factions" } },
	taxiNodes = { { name = "name", id = "id" } },
	taxiRoutes = {
		{ id = "fromNodeId", bucket = "taxiNodes" },
		{ id = "toNodeId", bucket = "taxiNodes" },
	},
}

local function lookup_name(bucket, id)
	local row = get_row(bucket, id)
	if type(row) ~= "table" then
		return nil
	end
	local name = row.name or row.title
	if type(name) == "string" and name ~= "" and usable(name) then
		return name
	end
end

-- A part prints the row's own name when it has one. Otherwise it prints the
-- name already collected for that id, and the id if that name is missing too.
local function part_text(row, part)
	local named = part.name and row[part.name]
	if type(named) == "string" and named ~= "" and usable(named) then
		return named
	end
	local id = row[part.id]
	if type(id) ~= "number" or not usable(id) then
		return nil
	end
	if part.bucket then
		local found = lookup_name(part.bucket, id)
		if found then
			return found
		end
	end
	return tostring(id)
end

local function record_text(bucket, row)
	local parts = LIST_PARTS[bucket]
	if not parts then
		return nil
	end
	local texts = {}
	for i = 1, #parts do
		local text = part_text(row, parts[i])
		if text then
			texts[#texts + 1] = text
		end
	end
	if #texts == 0 then
		return nil
	end
	return table.concat(texts, ", ")
end

local function compare_records(left, right)
	if left.key == right.key then
		return left.id < right.id
	end
	return left.key < right.key
end

-- A listing is rebuilt only after a row appears or a printed name changes. The
-- sort keys are lowered once, so the comparator does no string work.
local collected_cache = {}

function Everlook.world.collected_records(bucket)
	local cached = collected_cache[bucket]
	if cached and cached.version == collected_version then
		return cached.records
	end
	local records = {}
	each_row(bucket, function(_, row)
		local text = record_text(bucket, row)
		local key = row_key(bucket, row)
		if text and key ~= nil then
			records[#records + 1] = { text = text, key = text:lower(), id = tostring(key) }
		end
	end)
	table.sort(records, compare_records)
	collected_cache[bucket] = { version = collected_version, records = records }
	return records
end

-- Counts come from the running totals, so asking costs nothing.
function Everlook.world.collected_buckets()
	local listed = {}
	for i = 1, #BUCKETS do
		local bucket = BUCKETS[i]
		local count = bucket_totals[bucket]
		if count and count > 0 then
			listed[#listed + 1] = { bucket = bucket, label = LIST_LABELS[bucket] or bucket, count = count }
		end
	end
	return listed
end

function Everlook.world.collected()
	local listed = {}
	for i = 1, #BUCKETS do
		local bucket = BUCKETS[i]
		if bucket_totals[bucket] and bucket_totals[bucket] > 0 then
			local records = Everlook.world.collected_records(bucket)
			if #records > 0 then
				listed[#listed + 1] = {
					bucket = bucket,
					label = LIST_LABELS[bucket] or bucket,
					count = #records,
					records = records,
				}
			end
		end
	end
	return listed
end

local open_empty

function Everlook.world.reset()
	rows = {}
	dirty = false
	counts_dirty = false
	session_new = 0
	session_reported = 0
	paged = false
	keep_upload = false
	if Everlook.pages then
		Everlook.pages.reset()
		Everlook.pages.set_active(false)
	end
	row_total = 0
	bucket_totals = {}
	pin_indexes = {}
	collected_version = collected_version + 1
	Everlook.world.forget_lookup()
	if Everlook.location and Everlook.location.forget then
		Everlook.location.forget()
	end
	if Everlook.segments then
		Everlook.segments.reset()
	end
	-- A new, empty collection is kept in pages where it can be.
	open_empty()
end

function Everlook.world.session_new()
	return session_new
end

function Everlook.world.report_zone(zone)
	if session_new == session_reported then
		return false
	end
	if type(zone) ~= "string" or zone == "" or not usable(zone) then
		return false
	end
	local added = session_new - session_reported
	session_reported = session_new
	Everlook.say(added .. " new rows in " .. zone .. ".")
	return true
end

function Everlook.world.row_count()
	return row_total
end

function Everlook.world.load_message()
	local total = Everlook.world.row_count()
	local line
	if Everlook.config and Everlook.config.describe then
		local _
		_, line = Everlook.config.describe()
	end
	if type(line) == "string" and line ~= "" then
		return "Loaded. " .. total .. " rows. " .. line
	end
	return "Loaded. " .. total .. " rows."
end

function Everlook.world.each(bucket, visitor)
	if type(visitor) ~= "function" then
		return
	end
	each_row(bucket, visitor)
end

function Everlook.world.row(bucket, id)
	if type(bucket) ~= "string" or not usable(id) then
		return nil
	end
	return get_row(bucket, id)
end

-- Tooltip lines come from small indexes kept as rows are stored. Each index
-- holds up to three entries per id, which is all a tooltip shows, and the line
-- is written when it is asked for, from the names the rows hold now. A tooltip
-- never walks the world, however much has been collected. Where the collection
-- is in pages, the indexes are pages of their own, so a tooltip reads one or
-- two pages and nothing is rebuilt at login.
local LOOKUP_LIMIT = 3
local lookup = {}

-- The bucket each index is kept in when pages are used.
local INDEX_BUCKETS = {
	item_vendors = "ixItemVendors", npc_sells = "ixNpcSells", item_drops = "ixItemDrops",
	npc_casts = "ixNpcCasts", npc_quests = "ixNpcQuests", object_loot = "ixObjectLoot",
}
-- Bump this to have every index rebuilt from the rows next session.
local INDEX_VERSION = 1

function Everlook.world.forget_lookup()
	lookup = {
		item_vendors = {}, npc_sells = {}, item_drops = {}, npc_casts = {}, npc_quests = {}, object_loot = {},
	}
end

Everlook.world.forget_lookup()

local function index_list(group, id)
	if paged then
		return Everlook.pages.get(INDEX_BUCKETS[group], id)
	end
	return lookup[group][id]
end

local function lookup_add(group, id, value)
	local list = index_list(group, id)
	if not list then
		list = { value }
		if paged then
			Everlook.pages.add(INDEX_BUCKETS[group], id, list)
		else
			lookup[group][id] = list
		end
		return
	end
	for index = 1, #list do
		if list[index] == value then
			return
		end
	end
	if #list < LOOKUP_LIMIT then
		list[#list + 1] = value
		if paged then
			Everlook.pages.touch(list)
		end
	end
end

local function lookup_remove(group, id, value)
	local list = index_list(group, id)
	if not list then
		return
	end
	for index = 1, #list do
		if list[index] == value then
			table.remove(list, index)
			if paged then
				Everlook.pages.touch(list)
			end
			return
		end
	end
end

local function lookup_index(bucket, row)
	if bucket == "vendors" then
		if type(row.itemId) == "number" and type(row.npcId) == "number" then
			lookup_add("item_vendors", row.itemId, row.npcId)
			lookup_add("npc_sells", row.npcId, row.itemId)
		end
	elseif bucket == "drops" then
		if type(row.itemId) == "number" and type(row.npcId) == "number" then
			lookup_add("item_drops", row.itemId, row_key("drops", row))
		end
	elseif bucket == "npcSpells" then
		if type(row.npcId) == "number" and type(row.spellId) == "number" then
			lookup_add("npc_casts", row.npcId, row.spellId)
		end
	elseif bucket == "quests" then
		if type(row.giverId) == "number" then
			lookup_add("npc_quests", row.giverId, row.id)
		end
		if type(row.turnInId) == "number" then
			lookup_add("npc_quests", row.turnInId, row.id)
		end
	elseif bucket == "objectLoot" then
		if type(row.objectId) == "number" and type(row.itemId) == "number" then
			lookup_add("object_loot", row.objectId, row.itemId)
		end
	end
end

-- Whether the paged indexes hold every row. They are built in the background the
-- first time, and a tooltip says nothing until then.
local index_ready = true
local index_job

local LOOKUP_BUCKETS = { vendors = true, drops = true, npcSpells = true, quests = true, objectLoot = true }

local function lookup_label(bucket, id)
	local row = get_row(bucket, id)
	if type(row) == "table" then
		if type(row.name) == "string" and row.name ~= "" then
			return row.name
		end
		if type(row.title) == "string" and row.title ~= "" then
			return row.title
		end
	end
	return tostring(id)
end

local function quest_line(row, npc_id)
	local title = type(row.title) == "string" and row.title ~= "" and row.title or nil
	if title and (row.giverId == npc_id or row.turnInId == npc_id) then
		return "Quest: " .. title
	end
end

function Everlook.world.lookup(kind, id)
	local lines = {}
	if type(kind) ~= "string" or type(id) ~= "number" or not usable(id) then
		return lines
	end
	if paged and not index_ready then
		return lines
	end
	if kind == "item" then
		local vendors = index_list("item_vendors", id)
		for index = 1, vendors and #vendors or 0 do
			lines[#lines + 1] = "Vendor: " .. lookup_label("npcs", vendors[index])
		end
		local drops = index_list("item_drops", id)
		for index = 1, drops and #drops or 0 do
			local row = get_row("drops", drops[index])
			if row then
				local count = type(row.drops) == "number" and row.drops or 0
				lines[#lines + 1] = "Dropped by " .. lookup_label("npcs", row.npcId) .. " (" .. count .. ")"
			end
		end
	elseif kind == "npc" then
		local sells = index_list("npc_sells", id)
		for index = 1, sells and #sells or 0 do
			lines[#lines + 1] = "Sells " .. lookup_label("items", sells[index])
		end
		local casts = index_list("npc_casts", id)
		for index = 1, casts and #casts or 0 do
			lines[#lines + 1] = "Casts " .. lookup_label("spells", casts[index])
		end
		local quests = index_list("npc_quests", id)
		for index = 1, quests and #quests or 0 do
			local row = get_row("quests", quests[index])
			lines[#lines + 1] = row and quest_line(row, id) or nil
		end
	elseif kind == "object" then
		local loot = index_list("object_loot", id)
		for index = 1, loot and #loot or 0 do
			lines[#lines + 1] = "Contains " .. lookup_label("items", loot[index])
		end
	end
	while #lines > LOOKUP_LIMIT do
		lines[#lines] = nil
	end
	return lines
end

function Everlook.world.store(bucket, row)
	if type(row) ~= "table" then
		return
	end
	local key = row_key(bucket, row)
	if not key then
		return
	end
	local existing = get_row(bucket, key)
	local created = false
	if not existing then
		existing = {}
		created = true
		if paged then
			Everlook.pages.add(bucket, key, existing)
		end
		if not paged or Everlook.pages.migrating then
			local bucket_rows = rows[bucket]
			if not bucket_rows then
				bucket_rows = {}
				rows[bucket] = bucket_rows
			end
			bucket_rows[key] = existing
		end
	end
	local giver, turn_in, name, title, area_name
	if not created then
		name, title, area_name = existing.name, existing.title, existing.areaName
		if bucket == "quests" then
			giver, turn_in = existing.giverId, existing.turnInId
		end
	end
	local bumps = bumped
	local changed = merge(existing, row, PLAIN_VALUES[bucket])
	if changed then
		dirty = true
	end
	if paged and not created and (changed or bumped ~= bumps) then
		Everlook.pages.touch(existing)
	end
	if created then
		session_new = session_new + 1
		row_total = row_total + 1
		bucket_totals[bucket] = (bucket_totals[bucket] or 0) + 1
		collected_version = collected_version + 1
	elseif changed and (existing.name ~= name or existing.title ~= title or existing.areaName ~= area_name) then
		collected_version = collected_version + 1
	end
	if (changed or created) and pin_buckets[bucket] then
		for index = 1, #pin_watchers do
			pin_watchers[index](bucket)
		end
	end
	if LOOKUP_BUCKETS[bucket] and (created or changed) then
		if bucket == "quests" and not created then
			if giver ~= existing.giverId and type(giver) == "number" then
				lookup_remove("npc_quests", giver, existing.id)
			end
			if turn_in ~= existing.turnInId and type(turn_in) == "number" then
				lookup_remove("npc_quests", turn_in, existing.id)
			end
		end
		lookup_index(bucket, existing)
	end
	return changed
end

function Everlook.world.watch(listener)
	if type(listener) == "function" then
		pin_watchers[#pin_watchers + 1] = listener
	end
end

-- A repeat row only adds counters. Once those fields exist, the id columns
-- are left alone and the general merge is skipped.
function Everlook.world.count(bucket, row)
	if type(row) ~= "table" then
		return
	end
	local key = row_key(bucket, row)
	if not key then
		return
	end
	local existing = get_row(bucket, key)
	if not existing then
		Everlook.world.store(bucket, row)
		return
	end
	local pending = 0
	for field, amount in pairs(row) do
		if COUNTERS[field] and type(amount) == "number" and amount ~= 0 and usable(amount) then
			if type(existing[field]) ~= "number" then
				Everlook.world.store(bucket, row)
				return
			end
			pending = pending + 1
		end
	end
	if pending == 0 then
		return
	end
	for field, amount in pairs(row) do
		if COUNTERS[field] and type(amount) == "number" and amount ~= 0 and usable(amount) then
			existing[field] = existing[field] + amount
			counts_dirty = true
			bumped = bumped + 1
		end
	end
	if paged then
		Everlook.pages.touch(existing)
	end
end

local function pack_sources(sources)
	if type(sources) ~= "table" or #sources == 0 then
		return nil
	end
	local packed = {}
	for i = 1, #sources do
		packed[i] = SOURCES[sources[i]] or sources[i]
	end
	return packed
end

local function pack_locations(locations)
	if type(locations) ~= "table" or #locations == 0 then
		return nil
	end
	local packed = {}
	for i = 1, #locations do
		local location = locations[i]
		local row = {
			location.mapId,
			location.x,
			location.y,
			location.seen,
			location.zone,
			location.subzone,
			location.role,
		}
		while #row > 0 and row[#row] == nil do
			row[#row] = nil
		end
		for index = 1, #row do
			if row[index] == nil then
				row[index] = NULL
			end
		end
		packed[#packed + 1] = row
	end
	return packed
end

local function dense(values, count)
	local last = 0
	for i = 1, count do
		if values[i] ~= nil then
			last = i
		end
	end
	local packed = {}
	for i = 1, last do
		packed[i] = values[i]
		if packed[i] == nil then
			packed[i] = NULL
		end
	end
	if last == 0 then
		return nil
	end
	return packed
end

local function pack_item_refs(items)
	if type(items) ~= "table" or #items == 0 then
		return nil
	end
	local packed = {}
	for i = 1, #items do
		local item = items[i]
		local id = type(item) == "table" and (item.id or item.itemId or item.spellId) or nil
		if type(id) == "number" and usable(id) then
			local row = { id }
			if type(item.quantity) == "number" then
				row[2] = item.quantity
			end
			packed[#packed + 1] = row
		end
	end
	if #packed == 0 then
		return nil
	end
	return packed
end

local function pack_objectives(objectives)
	if type(objectives) ~= "table" or #objectives == 0 then
		return nil
	end
	local packed = {}
	for i = 1, #objectives do
		local objective = objectives[i]
		if type(objective) == "table" then
			local row = {}
			row[1] = objective.type
			row[2] = objective.id
			row[3] = objective.numRequired
			row[4] = objective.text
			row = dense(row, 4)
			if row then
				packed[#packed + 1] = row
			end
		end
	end
	if #packed == 0 then
		return nil
	end
	return packed
end

local function pack_endpoints(endpoints)
	if type(endpoints) ~= "table" or #endpoints == 0 then
		return nil
	end
	local packed = {}
	for i = 1, #endpoints do
		local endpoint = endpoints[i]
		if type(endpoint) == "table" and type(endpoint.id) == "number" then
			local row = {}
			row[1] = endpoint.type
			row[2] = endpoint.id
			row[3] = endpoint.name
			row = dense(row, 3)
			if row then
				packed[#packed + 1] = row
			end
		end
	end
	if #packed == 0 then
		return nil
	end
	return packed
end

local function pack_trainer_spells(spells)
	if type(spells) ~= "table" or #spells == 0 then
		return nil
	end
	local packed = {}
	for index = 1, #spells do
		local spell = spells[index]
		local spell_id = type(spell) == "table" and spell.spellId or spell
		if type(spell_id) == "number" and usable(spell_id) and spell_id > 0 then
			packed[#packed + 1] = { spell_id }
		end
	end
	if #packed == 0 then
		return nil
	end
	return packed
end

local function pack_ids(ids)
	if type(ids) ~= "table" or #ids == 0 then
		return nil
	end
	local packed = {}
	local seen = {}
	for i = 1, #ids do
		local id = ids[i]
		if type(id) == "table" then
			id = id.id
		end
		if type(id) == "number" and usable(id) and id > 0 and not seen[id] then
			seen[id] = true
			packed[#packed + 1] = id
		end
	end
	if #packed == 0 then
		return nil
	end
	return packed
end

local pack_reputations

local function pack_rewards(rewards)
	if type(rewards) ~= "table" then
		return nil
	end
	local packed = {}
	packed[1] = rewards.money
	packed[2] = rewards.experience
	packed[3] = pack_item_refs(rewards.items)
	packed[4] = pack_item_refs(rewards.choices)
	packed[5] = pack_reputations(rewards.reputations)
	packed[6] = pack_item_refs(rewards.spells)
	return dense(packed, 6)
end

local function pack_reagents(reagents)
	return pack_item_refs(reagents)
end

local function pack_pairs(pairs)
	if type(pairs) ~= "table" or #pairs == 0 then
		return nil
	end
	local packed = {}
	for i = 1, #pairs do
		local pair = pairs[i]
		if type(pair) == "table" then
			local name = pair.stat or pair.name
			local value = pair.value
			if value == nil then
				value = pair.threshold
			end
			if type(name) == "string" and name ~= "" and type(value) == "number" and usable(value) then
				local row = { name, value }
				if type(pair.text) == "string" and pair.text ~= "" then
					row[3] = pair.text
				end
				packed[#packed + 1] = row
			end
		end
	end
	if #packed == 0 then
		return nil
	end
	return packed
end

local function pack_names(entries)
	if type(entries) ~= "table" or #entries == 0 then
		return nil
	end
	local packed = {}
	for i = 1, #entries do
		local entry = entries[i]
		if type(entry) == "number" and usable(entry) and entry > 0 then
			packed[#packed + 1] = entry
		elseif type(entry) == "table" then
			local id = entry.id or entry.classId or entry.raceId
			if type(id) == "number" and usable(id) and id > 0 then
				local row = { id }
				local name = entry.name
				if type(name) == "string" and name ~= "" and usable(name) then
					row[2] = name
				end
				packed[#packed + 1] = row
			end
		end
	end
	if #packed == 0 then
		return nil
	end
	return packed
end

pack_reputations = function(entries)
	if type(entries) ~= "table" or #entries == 0 then
		return nil
	end
	local packed = {}
	for i = 1, #entries do
		local entry = entries[i]
		if type(entry) == "table" then
			local id = entry.factionId or entry.id
			local standing = entry.standing
			if standing == nil then
				standing = entry.amount
			end
			if type(id) == "number" and usable(id) and id > 0 and type(standing) == "number" and usable(standing) then
				packed[#packed + 1] = { id, standing }
			end
		end
	end
	if #packed == 0 then
		return nil
	end
	return packed
end

local function pack_effects(effects)
	if type(effects) ~= "table" or #effects == 0 then
		return nil
	end
	local packed = {}
	for i = 1, #effects do
		local effect = effects[i]
		if type(effect) == "table" then
			local text = effect.text
			if type(text) == "string" and text ~= "" and usable(text) then
				local row = { text }
				if type(effect.trigger) == "number" and usable(effect.trigger) then
					row[2] = effect.trigger
				end
				if type(effect.spellId) == "number" and usable(effect.spellId) then
					row[3] = effect.spellId
				end
				row = dense(row, 3)
				if row then
					packed[#packed + 1] = row
				end
			end
		end
	end
	if #packed == 0 then
		return nil
	end
	return packed
end

local function pack_value(column, row)
	if column == "sources" then
		return pack_sources(row.sources)
	end
	if column == "locations" then
		return pack_locations(row.locations)
	end
	if column == "objectives" then
		return pack_objectives(row.objectives)
	end
	if column == "starters" or column == "enders" then
		return pack_endpoints(row[column])
	end
	if column == "rewards" then
		return pack_rewards(row.rewards)
	end
	if column == "requires" then
		return pack_ids(row.requires)
	end
	if column == "requiredItems" then
		return pack_item_refs(row.requiredItems)
	end
	if column == "reagents" then
		return pack_reagents(row.reagents)
	end
	if column == "stats" or column == "setBonuses" then
		return pack_pairs(row[column])
	end
	if column == "effects" then
		return pack_effects(row.effects)
	end
	if column == "classRestrictions" or column == "raceRestrictions" or column == "areas" then
		return pack_names(row[column])
	end
	if column == "trainerSpells" then
		return pack_trainer_spells(row.trainerSpells)
	end
	if column == "requiredReputations" then
		return pack_reputations(row.requiredReputations)
	end
	local value = row[column]
	if not usable(value) or value == "" then
		return nil
	end
	return value
end

-- The flush packs every saved row. Holes stay NULL only through the last real
-- field, so the scratch list is not a second table.
local function pack_row(bucket, row)
	local columns = COLUMNS[bucket]
	local count = #columns
	local packed = {}
	local last = 0
	for i = 1, count do
		local value = pack_value(columns[i], row)
		if value ~= nil then
			packed[i] = value
			last = i
		else
			packed[i] = NULL
		end
	end
	for i = count, last + 1, -1 do
		packed[i] = nil
	end
	return packed
end

-- Packed rows are sequences. Only the document root has named fields, so a
-- row does not pay pairs() for every cell.
local function count_strings(value, counts, named)
	if type(value) == "string" and value ~= "" then
		counts[value] = (counts[value] or 0) + 1
		return
	end
	if type(value) ~= "table" or value == NULL then
		return
	end
	for i = 1, #value do
		count_strings(value[i], counts, false)
	end
	if named == false then
		return
	end
	for key, item in pairs(value) do
		if type(key) ~= "number" then
			count_strings(item, counts, false)
		end
	end
end

-- The packed document exists only for this build. Intern repeated strings
-- in place instead of copying every row into a second tree.
local function replace_strings(value, indexes, named)
	if type(value) ~= "table" or value == NULL then
		return
	end
	for i = 1, #value do
		local child = value[i]
		if type(child) == "string" then
			local index = indexes[child]
			if index then
				value[i] = index
			end
		else
			replace_strings(child, indexes, false)
		end
	end
	if named == false then
		return
	end
	for key, child in pairs(value) do
		if type(key) ~= "number" then
			if type(child) == "string" then
				local index = indexes[child]
				if index then
					value[key] = index
				end
			else
				replace_strings(child, indexes, false)
			end
		end
	end
end

-- What the segment encoder shares with this file. Not for other addons.
Everlook.world.internal = {
	pack_row = pack_row,
	count_strings = count_strings,
	replace_strings = replace_strings,
	null = NULL,
	columns = COLUMNS,
	keys = KEYS,
	buckets = BUCKETS,
}

function Everlook.world.document()
	local build, toc = "", 0
	if GetBuildInfo then
		local _, client_build, _, client_toc = GetBuildInfo()
		build = client_build or ""
		toc = client_toc or 0
	end
	local document = {
		v = 1,
		at = time and time() or 0,
		client = { build, GetLocale and GetLocale() or "", toc },
	}
	for i = 1, #BUCKETS do
		local bucket = BUCKETS[i]
		local packed = {}
		each_row(bucket, function(_, row)
			packed[#packed + 1] = pack_row(bucket, row)
		end)
		if #packed > 0 then
			document[bucket] = packed
		end
	end
	local counts = {}
	count_strings(document, counts)
	local table_strings = {}
	local indexes = {}
	for text, count in pairs(counts) do
		if count >= 2 then
			table_strings[#table_strings + 1] = text
		end
	end
	table.sort(table_strings)
	for i = 1, #table_strings do
		indexes[table_strings[i]] = i
	end
	if #table_strings > 0 then
		replace_strings(document, indexes)
		document.s = table_strings
	end
	return document
end

-- Milliseconds each step of the last flush took, saved with the world so a
-- slow logout can be read back from the SavedVariables file.
local flush_stats

local function stamp(name, started)
	if not started or not flush_stats then
		return nil
	end
	local now = debugprofilestop()
	flush_stats[name] = math.floor((now - started) * 10 + 0.5) / 10
	return now
end

local function encode_world()
	if not C_EncodingUtil or not C_EncodingUtil.SerializeCBOR then
		return nil
	end
	local clock = debugprofilestop and debugprofilestop() or nil
	local document = Everlook.world.document()
	clock = stamp("document", clock)
	local cbor = C_EncodingUtil.SerializeCBOR(document, { ignoreSerializationErrors = true })
	clock = stamp("cbor", clock)
	if type(cbor) ~= "string" then
		return nil
	end
	local raw = "1r." .. C_EncodingUtil.EncodeBase64(cbor)
	clock = stamp("base64", clock)
	local packed = raw
	if C_EncodingUtil.CompressString then
		local method = Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate or 0
		local level = Enum and Enum.CompressionLevel and Enum.CompressionLevel.OptimizeForSize or 2
		local compressed = C_EncodingUtil.CompressString(cbor, method, level)
		clock = stamp("compress", clock)
		if type(compressed) == "string" then
			local deflated = "1c." .. C_EncodingUtil.EncodeBase64(compressed)
			stamp("base64Compressed", clock)
			if #deflated < #raw then
				packed = deflated
			end
		end
	end
	if flush_stats then
		flush_stats.cborBytes = #cbor
	end
	return packed
end

local function note_flush_size(payload)
	EverlookDB.worldRows = Everlook.world.row_count()
	EverlookDB.worldBytes = type(payload) == "string" and #payload or 0
end

-- One pass over the saved rows at load, while the loading screen is up, sets
-- the running totals and the tooltip indexes that play then keeps current.
function Everlook.world.reindex()
	row_total = 0
	bucket_totals = {}
	pin_indexes = {}
	Everlook.world.forget_lookup()
	for index = 1, #BUCKETS do
		local bucket = BUCKETS[index]
		local total = 0
		if paged then
			total = Everlook.pages.total(bucket)
		else
			local bucket_rows = rows[bucket]
			if bucket_rows then
				for _, row in pairs(bucket_rows) do
					total = total + 1
					if LOOKUP_BUCKETS[bucket] and type(row) == "table" then
						lookup_index(bucket, row)
					end
				end
			end
		end
		if total > 0 then
			bucket_totals[bucket] = total
			row_total = row_total + total
		end
	end
	collected_version = collected_version + 1
	if paged then
		Everlook.world.start_index()
	end
	if Everlook.segments then
		Everlook.segments.rebuild()
	end
end

-- The paged indexes are built from the rows once, a page at a time in the
-- background, and kept up to date as rows are stored.
local INDEX_SOURCES = { "vendors", "drops", "npcSpells", "quests", "objectLoot" }

function Everlook.world.start_index()
	index_job = nil
	index_ready = true
	local db = EverlookDB
	if type(db) == "table" and db.ixVersion == INDEX_VERSION then
		return
	end
	local rows_to_read = 0
	for index = 1, #INDEX_SOURCES do
		rows_to_read = rows_to_read + Everlook.pages.total(INDEX_SOURCES[index])
	end
	if rows_to_read == 0 then
		if type(db) == "table" then
			db.ixVersion = INDEX_VERSION
		end
		return
	end
	index_ready = false
	index_job = { source = 1, from = 0 }
end

function Everlook.world.index_pending()
	return index_job ~= nil
end

-- Reads source pages until the time is up, a row or so at a time inside a page,
-- so a page of a thousand rows is not read in one frame. True while more remain.
function Everlook.world.index_step(limit_ms)
	local job = index_job
	if not job then
		return false
	end
	local clock = debugprofilestop
	local started = clock and clock() or 0
	while true do
		local bucket = INDEX_SOURCES[job.source]
		if not bucket then
			index_job = nil
			index_ready = true
			if type(EverlookDB) == "table" then
				EverlookDB.ixVersion = INDEX_VERSION
			end
			return false
		end
		if not job.list then
			local page = Everlook.pages.page_from(bucket, job.from)
			if not page then
				job.source = job.source + 1
				job.from = 0
			else
				job.from = page.start + 1
				if page.count > 0 then
					local list = {}
					for _, row in pairs(Everlook.pages.page_rows(page)) do
						if type(row) == "table" then
							list[#list + 1] = row
						end
					end
					job.list, job.at = list, 1
				end
			end
		else
			local list = job.list
			local last = job.at + 15
			if last > #list then
				last = #list
			end
			for index = job.at, last do
				lookup_index(bucket, list[index])
			end
			job.at = last + 1
			if job.at > #list then
				job.list = nil
			end
		end
		if not clock or clock() - started >= limit_ms then
			return true
		end
	end
end

-- Starts an empty collection in pages, where the client can keep them.
open_empty = function()
	local pages = Everlook.pages
	if not (pages and pages.enabled()) then
		return false
	end
	local ok = pages.self_test()
	if not ok then
		return false
	end
	pages.reset()
	pages.set_active(true)
	paged = true
	rows = {}
	return true
end

-- Opens the saved collection. It is kept in pages where the client can encode
-- them and hand them back whole. An older version saved every row as tables,
-- and those are moved into pages in the background, keeping the old copy until
-- every page is saved. Without an encoder the rows stay as tables.
function Everlook.world.load_saved()
	local db = EverlookDB
	if type(db) ~= "table" then
		return false
	end
	local pages = Everlook.pages
	local has_pages = type(db.pages) == "table" and next(db.pages) ~= nil
	if pages and pages.enabled() then
		local ok, reason = pages.self_test()
		db.pagesCheck = ok and "ok" or reason
		if ok then
			pages.set_active(true)
			paged = true
			local had_raw = type(db.raw) == "table"
			local carried
			if had_raw and (db.pagesMigrating or not has_pages) then
				-- Moving in: the old copy is the whole collection until every page is saved.
				db.pages, db.pageCounts, db.pagesMigrating = {}, {}, true
				rows = db.raw
				pages.import(rows)
			else
				-- The pages are the collection. A `raw` beside them holds only what an older
				-- build, or a session without pages, collected since.
				rows = {}
				pages.open_saved()
				if had_raw then
					carried = db.raw
					db.raw = nil
				end
			end
			Everlook.world.reindex()
			if carried then
				for bucket, bucket_rows in pairs(carried) do
					for _, row in pairs(bucket_rows) do
						if type(row) == "table" then
							row._seq = nil
							Everlook.world.store(bucket, row)
						end
					end
				end
			end
			return had_raw or next(db.pages or {}) ~= nil
		end
		if has_pages then
			-- The pages cannot be read here. Nothing is written over them, and what
			-- this session collects waits in `raw` to be added next time.
			rows = {}
			keep_upload = true
			return false
		end
	end
	if type(db.raw) ~= "table" then
		return false
	end
	rows = db.raw
	Everlook.world.reindex()
	return true
end

-- Every page is saved as its own string, so the old copy has been let go.
function Everlook.world.migrated()
	rows = {}
end

function Everlook.world.flush(include_counts)
	if not EverlookDB then
		return
	end
	-- raw is the collection. world and its signature are the signed upload.
	if not paged and (EverlookDB.raw ~= nil or Everlook.world.row_count() > 0) then
		EverlookDB.raw = rows
	end
	if keep_upload then
		return
	end
	-- Segments are packed and signed as they change, so logout only finishes
	-- what is left. The whole world is packed in one piece only where the
	-- client cannot encode, or where segments are not loaded.
	if Everlook.segments and Everlook.segments.finish() then
		EverlookDB.worldRows = Everlook.world.row_count()
		EverlookDB.worldBytes = Everlook.segments.bytes()
		return
	end
	if not dirty and not (include_counts and counts_dirty) then
		if include_counts then
			note_flush_size(EverlookDB.world)
		end
		return
	end
	flush_stats = debugprofilestop and {} or nil
	local payload = encode_world()
	note_flush_size(payload)
	if payload then
		EverlookDB.world = payload
		local clock = flush_stats and debugprofilestop() or nil
		if Everlook.config and Everlook.config.sign then
			Everlook.config.sign(payload)
		end
		stamp("sign", clock)
		dirty = false
		counts_dirty = false
		if flush_stats then
			flush_stats.rows = row_total
			flush_stats.bytes = #payload
			EverlookDB.flushStats = flush_stats
		end
	end
	flush_stats = nil
end

local function prepare_saved()
	EverlookDB = EverlookDB or {}
	EverlookDB.collection = nil
	EverlookDB.enabled = nil
	EverlookDB.eager = nil
	local minimap = EverlookDB.minimap
	if type(minimap) == "table" then
		minimap.icon = nil
	elseif minimap ~= nil then
		EverlookDB.minimap = nil
	end
end

-- What this addon holds, in KB, where the client says. Saved with the load and
-- logout timings so a heavy collection can be read back from the file.
function Everlook.world.memory_kb()
	if type(UpdateAddOnMemoryUsage) == "function" and type(GetAddOnMemoryUsage) == "function" then
		UpdateAddOnMemoryUsage()
		return math.floor(GetAddOnMemoryUsage(addonName) or 0)
	end
	return nil
end

EventUtil.ContinueOnAddOnLoaded(addonName, function()
	prepare_saved()
	local began = debugprofilestop and debugprofilestop() or nil
	Everlook.world.load_saved()
	if began then
		EverlookDB.loadStats = {
			loadMs = math.floor((debugprofilestop() - began) * 10 + 0.5) / 10,
			rows = row_total,
			memKB = Everlook.world.memory_kb(),
			paged = paged,
		}
	end
	Everlook.say(Everlook.world.load_message())
	local ticker = CreateFrame("Frame")
	ticker:RegisterEvent("PLAYER_LOGOUT")
	ticker:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	ticker:SetScript("OnEvent", function(_, event)
		if event == "ZONE_CHANGED_NEW_AREA" then
			local zone = GetZoneText and GetZoneText() or nil
			Everlook.world.report_zone(zone)
			return
		end
		-- WoW writes saved variables only at logout and on reload, which both
		-- fire PLAYER_LOGOUT. Packing and signing the world any sooner would
		-- only cost frames: signing in Lua takes a large share of a second.
		Everlook.world.flush(true)
	end)
end)
