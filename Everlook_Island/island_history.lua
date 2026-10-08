local Everlook = Everlook

-- The Island's inbox across a reload or relog. Only plain history rows survive:
-- text, detail, money and severity. Actions, live conditions and secure cards
-- are rebuilt by their producers, so a stale one is never restored.
local history = {}
Everlook.island_history = history

local KEEP_SECONDS = 24 * 3600
local MAX_ROWS = 30

local function server_now()
	local clock = GetServerTime or time
	local value = clock and clock()
	if type(value) == "number" and value == value then return value end
	return 0
end

local function character_key()
	local guid = UnitGUID and UnitGUID("player")
	if issecretvalue and issecretvalue(guid) then return nil end
	if type(guid) == "string" and guid ~= "" then return guid end
end

local function restorable(entry)
	return not entry.persist and not entry.removed and not entry.frozen and entry.presentation ~= "status"
		and type(entry.text) == "string" and entry.text ~= ""
end

local function row_of(entry, saved_at, elapsed_now)
	return {
		source = entry.source, key = entry.key, kind = entry.kind, text = entry.text, detail = entry.detail,
		severity = entry.severity, icon = entry.icon, money = entry.money, count = entry.count, unread = entry.unread,
		age = math.max(0, elapsed_now - (entry.updated_at or elapsed_now)), saved_at = saved_at,
	}
end

-- notices are oldest first. now is the island clock, the same one updated_at uses.
function history.save(notices, now)
	local key = character_key()
	if not key then return end
	EverlookDB = EverlookDB or {}
	local store = type(EverlookDB.island_history) == "table" and EverlookDB.island_history or {}
	EverlookDB.island_history = store
	local saved_at = server_now()
	for other, bucket in pairs(store) do
		if type(bucket) ~= "table" or type(bucket.saved_at) ~= "number" or saved_at - bucket.saved_at > KEEP_SECONDS then
			store[other] = nil
		end
	end
	local rows = {}
	for index = math.max(1, #notices - MAX_ROWS + 1), #notices do
		if restorable(notices[index]) then rows[#rows + 1] = row_of(notices[index], saved_at, now) end
	end
	store[key] = { saved_at = saved_at, rows = rows }
end

local function plain_text(value, maximum)
	return type(value) == "string" and value ~= "" and #value <= maximum
end

-- Returns rows with an age in seconds, oldest first. Anything malformed or older than a day is dropped.
function history.load()
	local key = character_key()
	local store = EverlookDB and EverlookDB.island_history
	local bucket = key and type(store) == "table" and store[key]
	if type(bucket) ~= "table" or type(bucket.rows) ~= "table" or type(bucket.saved_at) ~= "number" then return {} end
	local away = math.max(0, server_now() - bucket.saved_at)
	local rows = {}
	for _, row in ipairs(bucket.rows) do
		if type(row) == "table" and plain_text(row.text, 512) and plain_text(row.source, 64) and plain_text(row.kind, 32)
			and type(row.age) == "number" and row.age + away <= KEEP_SECONDS and #rows < MAX_ROWS then
			rows[#rows + 1] = {
				source = row.source, key = plain_text(row.key, 64) and row.key or nil, kind = row.kind, text = row.text,
				detail = plain_text(row.detail, 512) and row.detail or nil,
				severity = (row.severity == "success" or row.severity == "warning" or row.severity == "error") and row.severity or "info",
				icon = plain_text(row.icon, 64) and row.icon or nil,
				money = type(row.money) == "number" and row.money % 1 == 0 and row.money or nil,
				count = type(row.count) == "number" and row.count >= 1 and row.count % 1 == 0 and row.count or 1,
				unread = row.unread == true, age = row.age + away,
			}
		end
	end
	return rows
end
