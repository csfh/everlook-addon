local addonName, Everlook = ...

-- Module addons are separate addons, and a global is the only table they can
-- share with this one. Everlook.module and Everlook.island are the supported
-- interface for other addons. The rest is internal and can change.
_G.Everlook = Everlook

Everlook.world = {}

local NULL = {}
local rows = {}
local dirty = false
-- Tallies ride along on the next real edit, or on logout when the file is written.
local counts_dirty = false
local session_new = 0
local session_reported = 0
local lookup_stale = true

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

-- Repeat pins only add to seen. That count is updated in place so a sighting
-- does not copy the whole list.
local function merge_locations(existing, incoming)
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
			local found
			for j = 1, #existing do
				if same_pin(existing[j], location) then
					found = existing[j]
					break
				end
			end
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

-- Names, quest titles, givers, turn-ins, and drop counts rebuild the tooltip
-- lookup when they change, and so does a new row in any listed bucket.
-- Vendors, casts, and object drops list no fields, so only a new row rebuilds
-- them. A creature seen in a new place, or a repeat cast, does not.
local LOOKUP_FIELDS = {
	npcs = { "name" },
	items = { "name" },
	spells = { "name" },
	quests = { "title", "giverId", "turnInId" },
	vendors = {},
	drops = { "drops" },
	npcSpells = {},
	objectLoot = {},
}

local LOOKUP_SHOWN = {}
for bucket, fields in pairs(LOOKUP_FIELDS) do
	LOOKUP_SHOWN[bucket] = {}
	for index = 1, #fields do
		LOOKUP_SHOWN[bucket][fields[index]] = true
	end
end

-- Identical restatements must not mark the world dirty. A dirty flag rebuilds
-- and compresses the whole saved document on the next flush.
local function merge(target, source)
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
			elseif COUNTERS[key] and type(value) == "number" and type(target[key]) == "number" then
				if value ~= 0 then
					target[key] = target[key] + value
					counts_dirty = true
				end
			elseif key == "locations" then
				if has_location(value) then
					local merged, kind = merge_locations(target.locations, value)
					if kind == "place" then
						target.locations = merged
						changed = true
					elseif kind == "seen" then
						counts_dirty = true
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
				if value ~= "" and target[key] ~= value then
					target[key] = value
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
	local bucket_rows = rows[bucket]
	local row = bucket_rows and bucket_rows[id]
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
	local left_text = left.text:lower()
	local right_text = right.text:lower()
	if left_text == right_text then
		return left.id < right.id
	end
	return left_text < right_text
end

function Everlook.world.collected()
	local listed = {}
	for i = 1, #BUCKETS do
		local bucket = BUCKETS[i]
		local bucket_rows = rows[bucket]
		if bucket_rows then
			local records = {}
			for _, row in pairs(bucket_rows) do
				local text = record_text(bucket, row)
				local key = row_key(bucket, row)
				if text and key ~= nil then
					records[#records + 1] = { text = text, id = tostring(key) }
				end
			end
			if #records > 0 then
				table.sort(records, compare_records)
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

function Everlook.world.reset()
	rows = {}
	dirty = false
	counts_dirty = false
	session_new = 0
	session_reported = 0
	lookup_stale = true
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
	local total = 0
	for index = 1, #BUCKETS do
		local bucket_rows = rows[BUCKETS[index]]
		if bucket_rows then
			for _ in pairs(bucket_rows) do
				total = total + 1
			end
		end
	end
	return total
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
	local bucket_rows = rows[bucket]
	if not bucket_rows or type(visitor) ~= "function" then
		return
	end
	for key, row in pairs(bucket_rows) do
		visitor(key, row)
	end
end

function Everlook.world.row(bucket, id)
	if type(bucket) ~= "string" or not usable(id) then
		return nil
	end
	local bucket_rows = rows[bucket]
	if not bucket_rows then
		return nil
	end
	return bucket_rows[id]
end

-- Reused by every store, so checking the shown fields allocates nothing.
local shown_before = {}

function Everlook.world.store(bucket, row)
	if type(row) ~= "table" then
		return
	end
	local key = row_key(bucket, row)
	if not key then
		return
	end
	local bucket_rows = rows[bucket]
	if not bucket_rows then
		bucket_rows = {}
		rows[bucket] = bucket_rows
	end
	local existing = bucket_rows[key]
	local created = false
	if not existing then
		existing = {}
		bucket_rows[key] = existing
		created = true
	end
	local shown = LOOKUP_FIELDS[bucket]
	if shown and not created then
		for index = 1, #shown do
			shown_before[index] = existing[shown[index]]
		end
	end
	local changed = merge(existing, row)
	if changed then
		dirty = true
	end
	if created then
		session_new = session_new + 1
	end
	if (changed or created) and pin_buckets[bucket] then
		for index = 1, #pin_watchers do
			pin_watchers[index](bucket)
		end
	end
	if shown then
		if created then
			lookup_stale = true
		else
			for index = 1, #shown do
				if existing[shown[index]] ~= shown_before[index] then
					lookup_stale = true
				end
				shown_before[index] = nil
			end
		end
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
	local bucket_rows = rows[bucket]
	local existing = bucket_rows and bucket_rows[key]
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
			if LOOKUP_SHOWN[bucket] and LOOKUP_SHOWN[bucket][field] then
				lookup_stale = true
			end
		end
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

local lookup_lines

local function lookup_name(bucket, id)
	local row = rows[bucket] and rows[bucket][id]
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

local function lookup_add(group, id, text)
	local lines = group[id]
	if not lines then
		lines = {}
		group[id] = lines
	end
	if #lines >= 3 then
		return
	end
	lines[#lines + 1] = text
end

local function build_lookup()
	local item, npc, object = {}, {}, {}
	local vendor_rows = rows.vendors
	if vendor_rows then
		for _, row in pairs(vendor_rows) do
			if type(row.itemId) == "number" and type(row.npcId) == "number" then
				lookup_add(item, row.itemId, "Vendor: " .. lookup_name("npcs", row.npcId))
				lookup_add(npc, row.npcId, "Sells " .. lookup_name("items", row.itemId))
			end
		end
	end
	local drop_rows = rows.drops
	if drop_rows then
		for _, row in pairs(drop_rows) do
			if type(row.itemId) == "number" and type(row.npcId) == "number" then
				local count = type(row.drops) == "number" and row.drops or 0
				lookup_add(item, row.itemId, "Dropped by " .. lookup_name("npcs", row.npcId) .. " (" .. count .. ")")
			end
		end
	end
	local cast_rows = rows.npcSpells
	if cast_rows then
		for _, row in pairs(cast_rows) do
			if type(row.npcId) == "number" and type(row.spellId) == "number" then
				lookup_add(npc, row.npcId, "Casts " .. lookup_name("spells", row.spellId))
			end
		end
	end
	local quest_rows = rows.quests
	if quest_rows then
		for _, row in pairs(quest_rows) do
			local title = type(row.title) == "string" and row.title ~= "" and row.title or nil
			if title then
				if type(row.giverId) == "number" then
					lookup_add(npc, row.giverId, "Quest: " .. title)
				end
				if type(row.turnInId) == "number" and row.turnInId ~= row.giverId then
					lookup_add(npc, row.turnInId, "Quest: " .. title)
				end
			end
		end
	end
	local loot_rows = rows.objectLoot
	if loot_rows then
		for _, row in pairs(loot_rows) do
			if type(row.objectId) == "number" and type(row.itemId) == "number" then
				lookup_add(object, row.objectId, "Contains " .. lookup_name("items", row.itemId))
			end
		end
	end
	lookup_lines = { item = item, npc = npc, object = object }
	lookup_stale = false
end

function Everlook.world.lookup(kind, id)
	if type(kind) ~= "string" or type(id) ~= "number" or not usable(id) then
		return {}
	end
	if lookup_stale or not lookup_lines then
		build_lookup()
	end
	local group = lookup_lines[kind]
	local lines = group and group[id]
	if not lines then
		return {}
	end
	local copy = {}
	for index = 1, #lines do
		copy[index] = lines[index]
	end
	return copy
end

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
		local bucket_rows = rows[bucket]
		if bucket_rows then
			local packed = {}
			for _, row in pairs(bucket_rows) do
				packed[#packed + 1] = pack_row(bucket, row)
			end
			if #packed > 0 then
				document[bucket] = packed
			end
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

local function encode_world()
	if not C_EncodingUtil or not C_EncodingUtil.SerializeCBOR then
		return nil
	end
	local cbor = C_EncodingUtil.SerializeCBOR(Everlook.world.document(), { ignoreSerializationErrors = true })
	if type(cbor) ~= "string" then
		return nil
	end
	local raw = "1r." .. C_EncodingUtil.EncodeBase64(cbor)
	local packed = raw
	if C_EncodingUtil.CompressString then
		local method = Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate or 0
		local level = Enum and Enum.CompressionLevel and Enum.CompressionLevel.OptimizeForSize or 2
		local compressed = C_EncodingUtil.CompressString(cbor, method, level)
		if type(compressed) == "string" then
			local deflated = "1c." .. C_EncodingUtil.EncodeBase64(compressed)
			if #deflated < #raw then
				packed = deflated
			end
		end
	end
	return packed
end

local function note_flush_size(payload)
	EverlookDB.worldRows = Everlook.world.row_count()
	EverlookDB.worldBytes = type(payload) == "string" and #payload or 0
end

function Everlook.world.load_saved()
	if not EverlookDB or type(EverlookDB.raw) ~= "table" then
		return false
	end
	rows = EverlookDB.raw
	return true
end

function Everlook.world.flush(include_counts)
	if not EverlookDB then
		return
	end
	-- raw is the collection. world and its signature are the signed upload.
	if EverlookDB.raw ~= nil or Everlook.world.row_count() > 0 then
		EverlookDB.raw = rows
	end
	if not dirty and not (include_counts and counts_dirty) then
		if include_counts then
			note_flush_size(EverlookDB.world)
		end
		return
	end
	local payload = encode_world()
	note_flush_size(payload)
	if payload then
		EverlookDB.world = payload
		if Everlook.config and Everlook.config.sign then
			Everlook.config.sign(payload)
		end
		dirty = false
		counts_dirty = false
	end
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

EventUtil.ContinueOnAddOnLoaded(addonName, function()
	prepare_saved()
	Everlook.world.load_saved()
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
