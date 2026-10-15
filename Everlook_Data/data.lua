-- What players have seen, checked against each other on everlook.ing, for the tooltips. The generated
-- files (meta.lua and the chunks) call into this one, so it loads first. A chunk is plain text, one
-- record per line, found by `string.find` on the id; nothing is parsed until something asks.
Everlook_Data = Everlook_Data or {}
local data = Everlook_Data
local chunks = {}

-- Called by each generated chunk file, in ascending order of the first id it holds.
function data.chunk(kind, first, text)
	local list = chunks[kind]
	if not list then
		list = {}
		chunks[kind] = list
	end
	list[#list + 1] = { first = first, text = text }
end

-- The text after `id|` on the record for this id, or nil.
function data.find(kind, id)
	local list = chunks[kind]
	if not list or type(id) ~= "number" then return nil end
	local chunk
	for index = #list, 1, -1 do
		if list[index].first <= id then
			chunk = list[index]
			break
		end
	end
	if not chunk then return nil end
	local key = "\n" .. id .. "|"
	local start = chunk.text:find(key, 1, true)
	if not start then return nil end
	local from = start + #key
	local finish = chunk.text:find("\n", from, true)
	return chunk.text:sub(from, (finish or #chunk.text + 1) - 1)
end

-- The creatures that drop an item, the ones seen dropping it most first: { { npc = 448, drops = 12, name = "Hogger" }, ... }.
function data.drops(item_id)
	local record = data.find("drops", item_id)
	if not record then return nil end
	local list = {}
	for entry in record:gmatch("[^;]+") do
		local npc, drops, name = entry:match("^(%d+):(%d+):(.*)$")
		if npc then list[#list + 1] = { npc = tonumber(npc), drops = tonumber(drops), name = name } end
	end
	return #list > 0 and list or nil
end

-- The instances entered from an outdoor map: { { instance = 43, x = 525, y = 375, enters = 9, name = "Wailing Caverns" }, ... }.
function data.entrances(map_id)
	local record = data.find("entrances", map_id)
	if not record then return nil end
	local list = {}
	for entry in record:gmatch("[^;]+") do
		local instance, x, y, enters, name = entry:match("^(%d+):(%d+):(%d+):(%d+):(.*)$")
		if instance then
			list[#list + 1] = { instance = tonumber(instance), x = tonumber(x), y = tonumber(y), enters = tonumber(enters), name = name ~= "" and name or nil }
		end
	end
	return #list > 0 and list or nil
end

-- Where most of a zone's creatures sit in level: { low = 7, high = 10, spawns = 1432 }.
function data.levels(map_id)
	local record = data.find("levels", map_id)
	local low, high, spawns = (record or ""):match("^(%d+):(%d+):(%d+)$")
	if not low then return nil end
	return { low = tonumber(low), high = tonumber(high), spawns = tonumber(spawns) }
end

-- The quests a creature gives: { { quest = 176, level = 9, before = { 54 } }, ... }, `before` being what must be done first.
function data.givers(npc_id)
	local record = data.find("givers", npc_id)
	if not record then return nil end
	local list = {}
	for entry in record:gmatch("[^;]+") do
		local quest, level, before = entry:match("^(%d+):(%d+):([%d%.]*)$")
		if quest then
			local required = {}
			for id in before:gmatch("%d+") do required[#required + 1] = tonumber(id) end
			list[#list + 1] = { quest = tonumber(quest), level = tonumber(level), before = required }
		end
	end
	return #list > 0 and list or nil
end

function data.version()
	return data.meta and data.meta.version or nil
end
