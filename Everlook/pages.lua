local _, Everlook = ...

-- The collection lives in pages. A page is the rows of one bucket whose first
-- key falls in a range, saved as one string and decoded only when something
-- reads or writes one of its rows. The saved file therefore holds a few
-- thousand strings instead of every row as tables, which Lua cannot compile
-- past about 200,000 rows and which would need the whole collection in memory.
--
-- A page that grows past its size is cut at the middle key in two, and only
-- its own rows move. Which page holds a key is worked out from the key and a
-- short list of where the pages start, so nothing else is saved to find it.

Everlook.pages = {}
local P = Everlook.pages

local floor = math.floor

-- Rows in a full page, chosen so one is around 30 to 60 KB saved.
local CAP = {
	maps = 12, factions = 512, spells = 192, skillLines = 512, currencies = 512, items = 128, objects = 128,
	npcs = 40, quests = 24, talents = 512, recipes = 256, kills = 1024, drops = 1024, vendors = 1024,
	merchantCosts = 1024, objectLoot = 1024, fishingLoot = 512, npcSpells = 1024, npcFactions = 1024,
	taxiNodes = 256, taxiRoutes = 512,
}

-- Indexes kept beside the rows. They are rebuilt from the rows, so they are saved
-- but never uploaded.
local DERIVED = {
	ixItemVendors = true, ixNpcSells = true, ixItemDrops = true, ixNpcCasts = true, ixNpcQuests = true, ixObjectLoot = true,
}
for name in pairs(DERIVED) do
	CAP[name] = 2048
end

local MAX_LOADED = 48
local LAST_KEY = 999999999

local dirs = {}
local by_name = {}
local page_of = {}
local loaded_count = 0
local clock_tick = 0
local pinned
local stats = { decodes = 0, decodeMs = 0, worstDecodeMs = 0, splits = 0, evictions = 0 }

-- Called with a page each time it changes. The encoder sets it.
P.on_dirty = function() end

-- Called with the two pages when one is cut in two. The encoder sets it.
P.on_split = function() end

local function now_ms()
	return type(debugprofilestop) == "function" and debugprofilestop() or 0
end

local active = false

-- Whether the collection is in pages this session.
function P.active()
	return active
end

function P.set_active(value)
	active = value and true or false
end

function P.enabled()
	return type(C_EncodingUtil) == "table"
		and type(C_EncodingUtil.SerializeCBOR) == "function"
		and type(C_EncodingUtil.DeserializeCBOR) == "function"
		and type(C_EncodingUtil.EncodeBase64) == "function"
		and type(C_EncodingUtil.DecodeBase64) == "function"
end

-- The number that decides a row's page: the first part of its key.
local function first_of(key)
	local number = key
	if type(key) == "string" then
		number = tonumber(key:match("^%-?%d+"))
	end
	if type(number) ~= "number" or number < 0 then
		return 0
	end
	if number > LAST_KEY then
		return LAST_KEY
	end
	return floor(number)
end

function P.first_of(key)
	return first_of(key)
end

local function directory(bucket)
	local dir = dirs[bucket]
	if not dir then
		dir = { starts = {}, pages = {} }
		dirs[bucket] = dir
	end
	return dir
end

local function new_page(bucket, start)
	local page = {
		bucket = bucket,
		start = start,
		name = bucket .. "." .. start,
		count = 0,
		version = 0,
		used = 0,
	}
	by_name[page.name] = page
	return page
end

local function insert_page(bucket, page)
	local dir = directory(bucket)
	local at = #dir.starts + 1
	for index = 1, #dir.starts do
		if dir.starts[index] > page.start then
			at = index
			break
		end
	end
	table.insert(dir.starts, at, page.start)
	table.insert(dir.pages, at, page)
	return at
end

-- The page whose range holds `first`, made on first use.
local function locate(bucket, first)
	local dir = directory(bucket)
	if #dir.starts == 0 then
		insert_page(bucket, new_page(bucket, 0))
	end
	local low, high = 1, #dir.starts
	while low < high do
		local middle = floor((low + high + 1) / 2)
		if dir.starts[middle] <= first then
			low = middle
		else
			high = middle - 1
		end
	end
	return dir.pages[low], low
end

local function upper_bound(bucket, index)
	local dir = dirs[bucket]
	return dir.starts[index + 1]
end

local function in_range(bucket, index, first)
	local dir = dirs[bucket]
	local upper = dir.starts[index + 1]
	return first >= dir.starts[index] and (upper == nil or first < upper)
end

-- A page's rows changed, so its saved copy and its upload segment are out of date.
function P.mark(page)
	page.version = page.version + 1
	page.raw_dirty = true
	page.seg_dirty = not DERIVED[page.bucket]
	P.on_dirty(page)
end

-- The place of the page that holds `key` in the bucket's list of pages, from 1.
function P.index_of(bucket, key)
	local _, index = locate(bucket, first_of(key))
	return index
end

function P.derived(bucket)
	return DERIVED[bucket] == true
end

-- The first page whose range starts at or after `start`.
function P.page_from(bucket, start)
	local dir = dirs[bucket]
	if not dir then
		return nil
	end
	local low, high = 1, #dir.starts + 1
	while low < high do
		local middle = floor((low + high) / 2)
		if dir.starts[middle] < start then
			low = middle + 1
		else
			high = middle
		end
	end
	return dir.pages[low]
end

local function forget(page)
	for _, row in pairs(page.rows) do
		page_of[row] = nil
	end
	page.rows = nil
	page.pins = nil
	page.records = nil
	loaded_count = loaded_count - 1
	stats.evictions = stats.evictions + 1
end

-- Drops the pages used longest ago, never one whose rows are not saved yet and
-- never the one being walked. A page that only needs its upload segment built
-- can go, since the segment is built from the saved copy. A few at a time, so a long list of pages that
-- became free is let go over several saves and not in one frame.
local EVICT_AT_ONCE = 32

local function make_room()
	-- While the old whole-collection copy is still the saved one, its tables are
	-- the rows, so nothing is let go.
	if loaded_count <= MAX_LOADED or P.migrating then
		return
	end
	local candidates = {}
	for _, page in pairs(by_name) do
		if page.rows and page ~= pinned and not page.raw_dirty and not page.job then
			candidates[#candidates + 1] = page
		end
	end
	table.sort(candidates, function(left, right)
		return left.used < right.used
	end)
	local released = 0
	for index = 1, #candidates do
		if loaded_count <= MAX_LOADED or released >= EVICT_AT_ONCE then
			break
		end
		forget(candidates[index])
		released = released + 1
	end
end

-- Called when a page has just been saved and may be let go.
function P.trim()
	make_room()
end

-- Whether more pages are held than the cache keeps, once it may let them go.
function P.over()
	return loaded_count > MAX_LOADED and not P.migrating
end

local function decode(payload)
	if type(payload) ~= "string" or payload:sub(1, 3) ~= "p1." then
		return nil
	end
	local body = C_EncodingUtil.DecodeBase64(payload:sub(4))
	if type(body) ~= "string" then
		return nil
	end
	if C_EncodingUtil.DecompressString then
		local method = Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate or 0
		local inflated = C_EncodingUtil.DecompressString(body, method)
		if type(inflated) == "string" then
			body = inflated
		end
	end
	local rows = C_EncodingUtil.DeserializeCBOR(body)
	if type(rows) ~= "table" then
		return nil
	end
	return rows
end

local function saved_payload(page)
	local db = EverlookDB
	return type(db) == "table" and type(db.pages) == "table" and db.pages[page.name] or nil
end

-- Reads a page's rows into memory. A row left in a page by a split that did not
-- finish saving belongs to another page now, and is skipped.
local function load(page)
	clock_tick = clock_tick + 1
	page.used = clock_tick
	if page.rows then
		return page.rows
	end
	local started = now_ms()
	local rows = {}
	local payload = saved_payload(page)
	local decoded = payload and decode(payload) or nil
	if payload and not decoded then
		stats.unreadable = (stats.unreadable or 0) + 1
	end
	if decoded then
		local dir = dirs[page.bucket]
		local index
		for position = 1, #dir.pages do
			if dir.pages[position] == page then
				index = position
			end
		end
		local count = 0
		for key, row in pairs(decoded) do
			if type(row) == "table" and in_range(page.bucket, index, first_of(key)) then
				rows[key] = row
				page_of[row] = page
				count = count + 1
			end
		end
		page.count = count
	end
	page.rows = rows
	loaded_count = loaded_count + 1
	local spent = now_ms() - started
	stats.decodes = stats.decodes + 1
	stats.decodeMs = stats.decodeMs + spent
	if spent > stats.worstDecodeMs then
		stats.worstDecodeMs = spent
	end
	local keep = pinned
	pinned = page
	make_room()
	pinned = keep
	return rows
end

function P.page_rows(page)
	return load(page)
end

function P.get(bucket, key)
	local dir = dirs[bucket]
	if not dir or #dir.starts == 0 then
		return nil
	end
	local page = locate(bucket, first_of(key))
	-- A page nothing was ever saved for has no rows to read.
	if not page.rows and saved_payload(page) == nil then
		return nil
	end
	return load(page)[key]
end

-- Stores a row that has no page entry yet.
function P.add(bucket, key, row)
	local page, index = locate(bucket, first_of(key))
	local rows = load(page)
	if rows[key] == nil then
		page.count = page.count + 1
	end
	rows[key] = row
	page_of[row] = page
	P.mark(page)
	if page.count > (CAP[bucket] or 256) and not page.unsplittable then
		P.split(page)
	end
	return row
end

-- A row's content or counts changed.
function P.touch(row)
	local page = page_of[row]
	if page then
		P.mark(page)
	end
end

function P.page_of(row)
	return page_of[row]
end

-- Cuts a page at its middle key. The upper half becomes a new page. Both are
-- saved again, and a page that is only half saved is made right on load.
function P.split(page)
	local rows = load(page)
	local firsts, seen = {}, {}
	for key in pairs(rows) do
		local first = first_of(key)
		if not seen[first] then
			seen[first] = true
			firsts[#firsts + 1] = first
		end
	end
	if #firsts < 2 then
		page.unsplittable = true
		return nil
	end
	table.sort(firsts)
	local cut = firsts[floor(#firsts / 2) + 1]
	local upper = new_page(page.bucket, cut)
	upper.rows = {}
	loaded_count = loaded_count + 1
	local moved = 0
	for key, row in pairs(rows) do
		if first_of(key) >= cut then
			upper.rows[key] = row
			rows[key] = nil
			page_of[row] = upper
			moved = moved + 1
		end
	end
	upper.count = moved
	page.count = page.count - moved
	insert_page(page.bucket, upper)
	clock_tick = clock_tick + 1
	upper.used = clock_tick
	stats.splits = stats.splits + 1
	-- The new page is saved before the old one stops holding its rows.
	page.waits = upper
	P.on_split(page, upper)
	P.mark(upper)
	P.mark(page)
	return upper
end

-- Every row of a bucket, a page at a time. Only for what has to see them all.
function P.each(bucket, visitor)
	local dir = dirs[bucket]
	if not dir then
		return
	end
	local list = {}
	for index = 1, #dir.pages do
		list[index] = dir.pages[index]
	end
	for index = 1, #list do
		local page = list[index]
		if page.count > 0 or page.rows then
			local keep = pinned
			pinned = page
			local rows = load(page)
			for key, row in pairs(rows) do
				visitor(key, row)
			end
			pinned = keep
		end
	end
end

function P.pages(bucket)
	local dir = dirs[bucket]
	return dir and dir.pages or {}
end

function P.total(bucket)
	local dir = dirs[bucket]
	local total = 0
	if dir then
		for index = 1, #dir.pages do
			total = total + dir.pages[index].count
		end
	end
	return total
end

function P.by_name(name)
	return by_name[name]
end

function P.all()
	return by_name
end

function P.stats()
	return stats
end

function P.loaded()
	return loaded_count
end

-- What the saved file holds, found from the names of its pages.
function P.reset()
	dirs, by_name, page_of = {}, {}, {}
	loaded_count, clock_tick, pinned = 0, 0, nil
	P.migrating = false
	stats = { decodes = 0, decodeMs = 0, worstDecodeMs = 0, splits = 0, evictions = 0 }
end

function P.open_saved(buckets)
	P.reset()
	local db = EverlookDB
	if type(db) ~= "table" or type(db.pages) ~= "table" then
		return false
	end
	local counts = type(db.pageCounts) == "table" and db.pageCounts or {}
	local found = false
	for name in pairs(db.pages) do
		local bucket, start = tostring(name):match("^(%a+)%.(%d+)$")
		if bucket and tonumber(start) then
			local page = new_page(bucket, tonumber(start))
			page.count = tonumber(counts[name]) or 0
			insert_page(bucket, page)
			found = true
		end
	end
	return found
end

-- Moves a whole collection of rows, as an older version saved it, into pages.
function P.import(raw)
	P.reset()
	P.migrating = true
	local imported = 0
	for bucket, bucket_rows in pairs(raw) do
		for key, row in pairs(bucket_rows) do
			if type(row) == "table" then
				-- An earlier build numbered rows here. Pages do not need it.
				row._seq = nil
				P.add(bucket, key, row)
				imported = imported + 1
			end
		end
	end
	return imported
end

-- The encoded form of a page's rows, in stages the encoder runs a step at a time.
function P.encode_cbor(page)
	return C_EncodingUtil.SerializeCBOR(page.rows, { ignoreSerializationErrors = true })
end

function P.encode_payload(cbor)
	local body = cbor
	if C_EncodingUtil.CompressString then
		local method = Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate or 0
		local level = Enum and Enum.CompressionLevel and Enum.CompressionLevel.Default or 0
		local compressed = C_EncodingUtil.CompressString(cbor, method, level)
		if type(compressed) == "string" then
			body = compressed
		end
	end
	return "p1." .. C_EncodingUtil.EncodeBase64(body)
end

-- Writes a page's saved copy and its count together.
function P.store_payload(page, payload)
	local db = EverlookDB
	if type(db) ~= "table" then
		return
	end
	db.pages = db.pages or {}
	db.pageCounts = db.pageCounts or {}
	db.pages[page.name] = payload
	db.pageCounts[page.name] = page.count
end

-- Whether the engine hands back what it was given. A page that came back
-- different would lose data, so pages are used only if this holds.
local function same(left, right)
	if type(left) ~= type(right) then
		return false
	end
	if type(left) ~= "table" then
		return left == right
	end
	for key, value in pairs(left) do
		if not same(value, right[key]) then
			return false
		end
	end
	for key in pairs(right) do
		if left[key] == nil then
			return false
		end
	end
	return true
end

function P.self_test()
	if not P.enabled() then
		return false, "no encoder"
	end
	local sample = {
		[448] = { id = 448, name = "Hogger", minLevel = 11, flag = true, off = false, ratio = 0.25, locations = { { mapId = 37, x = 250, y = 600, seen = 3, zone = "Elwynn" }, { mapId = 37, x = 1, y = 2 } }, sources = { "target", "loot" }, rewards = { money = 5, items = { { id = 1, quantity = 2 } } } },
		["12:34"] = { npcId = 12, itemId = 34, drops = 7, quantity = 9 },
		[70000] = { id = 70000, description = string.rep("long text, ", 400) .. "\r\n\"quoted\"" },
	}
	local ok, payload = pcall(function()
		return P.encode_payload(C_EncodingUtil.SerializeCBOR(sample, { ignoreSerializationErrors = true }))
	end)
	if not ok or type(payload) ~= "string" then
		return false, "encode failed"
	end
	local decoded = decode(payload)
	if type(decoded) ~= "table" or not same(sample, decoded) then
		return false, "a page did not come back as it went in"
	end
	return true
end
