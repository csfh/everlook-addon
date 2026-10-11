local Everlook = Everlook

-- Sections are the content other addons put in the open island's panes. This file
-- reads one spec into a clean record, or says why it cannot, and keeps the records.
-- It draws nothing and calls no WoW API; island_blocks.lua draws what it holds.
local section = {}
Everlook.island_section = section

local capsule = Everlook.island_capsule

-- Only these regions draw in this release. The header and the metrics join in a
-- later one, so a producer cannot name a region that would silently show nothing.
local REGIONS = { pane_a = true, pane_b = true }
local SPEC_KEYS = { source = true, key = true, region = true, title = true, order = true, blocks = true, expires = true }
local BLOCK_KEYS = {
	row = { kind = true, row = true, action = true, tooltip = true },
	text = { kind = true, text = true },
	heading = { kind = true, text = true },
	gap = { kind = true, size = true },
	meter = { kind = true, label = true, value = true, fraction = true, tone = true },
	cells = { kind = true, cells = true },
	table = { kind = true, title = true, columns = true, rows = true, footer = true, action = true, open = true },
}
local MAX_COLUMNS, MAX_ROWS = 3, 8
local CELL_KEYS = { icon = true, label = true, value = true, ring = true }
local RING_KEYS = { fraction = true, tone = true }
local MAX_CELLS = 6
local ACTION_KEYS = { id = true, label = true, on_click = true }
local TOOLTIP_KEYS = { title = true, lines = true }
local GAPS = { within = true, near = true, section = true }

section.limits = { sections = 12, blocks = 30, bytes = 8192, order_min = 100, order_max = 999, order_default = 500, expires_max = 3600 }

local function usable(value)
	if issecretvalue and issecretvalue(value) then return false end
	return value ~= nil
end

local function plain_table(value)
	return usable(value) and type(value) == "table" and getmetatable(value) == nil
end

local function plain_string(value, maximum)
	return usable(value) and type(value) == "string" and #value >= 1 and #value <= maximum and value:find("%S") ~= nil
end

-- A text a producer writes is plain: no colour codes, links or textures, which all start with a pipe.
local function plain_text(value, maximum)
	return plain_string(value, maximum) and not value:find("|", 1, true)
end

local function known_keys(value, allowed)
	for key in pairs(value) do
		if not allowed[key] then return false end
	end
	return true
end

local function identifier(value)
	return plain_string(value, 32) and value:find("^[%a_][%w_]*$") ~= nil
end

-- Our own addons may take the first slots of a pane. Anyone else starts below them.
function section.builtin(source)
	return type(source) == "string" and (source:find("^everlook") ~= nil or source:find("^smart_island") ~= nil)
end

local function read_action(action)
	if not plain_table(action) or not known_keys(action, ACTION_KEYS) then return nil, "invalid_action" end
	if not identifier(action.id) then return nil, "invalid_action_id" end
	if not plain_text(action.label, 24) then return nil, "invalid_action_label" end
	if type(action.on_click) ~= "function" then return nil, "invalid_action_callback" end
	return { id = action.id, label = action.label, callback = action.on_click }
end

local function read_tooltip(tooltip)
	if not plain_table(tooltip) or not known_keys(tooltip, TOOLTIP_KEYS) then return nil, "invalid_tooltip" end
	if tooltip.title ~= nil and not plain_text(tooltip.title, 64) then return nil, "invalid_tooltip" end
	local lines = {}
	if tooltip.lines ~= nil then
		if not plain_table(tooltip.lines) or #tooltip.lines > 6 then return nil, "invalid_tooltip" end
		for key in pairs(tooltip.lines) do
			if type(key) ~= "number" or key < 1 or key > #tooltip.lines or key % 1 ~= 0 then return nil, "invalid_tooltip" end
		end
		for index = 1, #tooltip.lines do
			if not plain_text(tooltip.lines[index], 160) then return nil, "invalid_tooltip" end
			lines[index] = tooltip.lines[index]
		end
	end
	if tooltip.title == nil and #lines == 0 then return nil, "invalid_tooltip" end
	return { title = tooltip.title, lines = lines }
end

-- Returns the block copied, and the bytes of text it carries.
local function read_block(block)
	if not plain_table(block) then return nil, "invalid_block" end
	local kind = block.kind
	local allowed = type(kind) == "string" and BLOCK_KEYS[kind]
	if not allowed or not known_keys(block, allowed) then return nil, "invalid_block" end
	if kind == "gap" then
		if not GAPS[block.size or "near"] then return nil, "invalid_block" end
		return { kind = "gap", size = block.size or "near" }, 0
	end
	if kind == "text" then
		-- Up to four lines, so a line break is the one control character that is allowed.
		local text = block.text
		if not plain_string(text, 320) or text:find("|", 1, true) or text:gsub("\n", ""):find("%c") then return nil, "invalid_block" end
		local _, lines = text:gsub("\n", "")
		if lines > 3 then return nil, "invalid_block" end
		return { kind = "text", text = text }, #text
	end
	if kind == "heading" then
		if not plain_text(block.text, 48) then return nil, "invalid_block" end
		return { kind = "heading", text = block.text }, #block.text
	end
	if kind == "meter" then
		if not plain_text(block.label, 32) or not plain_text(block.value, 24) then return nil, "invalid_block" end
		local fraction = block.fraction
		if type(fraction) ~= "number" or fraction ~= fraction or fraction < 0 or fraction > 1 then return nil, "invalid_block" end
		local tone = capsule.tone_color(block.tone or "accent")
		if not tone then return nil, "invalid_block" end
		return { kind = "meter", label = block.label, value = block.value, fraction = fraction, tone = tone }, #block.label + #block.value
	end
	if kind == "cells" then
		local list = block.cells
		if not plain_table(list) or #list < 1 or #list > MAX_CELLS then return nil, "invalid_block" end
		for key in pairs(list) do
			if type(key) ~= "number" or key < 1 or key > #list or key % 1 ~= 0 then return nil, "invalid_block" end
		end
		local cells, bytes = {}, 0
		for index = 1, #list do
			local cell = list[index]
			if not plain_table(cell) or not known_keys(cell, CELL_KEYS) then return nil, "invalid_block" end
			if not plain_text(cell.label, 24) or not plain_text(cell.value, 24) then return nil, "invalid_block" end
			local copy = { label = cell.label, value = cell.value }
			bytes = bytes + #cell.label + #cell.value
			if cell.icon ~= nil then
				local icon, reason = capsule.read_mark(cell.icon)
				if reason then return nil, reason end
				if not icon then return nil, "invalid_block" end
				copy.icon = icon
			end
			if cell.ring ~= nil then
				local ring = cell.ring
				if not plain_table(ring) or not known_keys(ring, RING_KEYS) then return nil, "invalid_block" end
				local fraction = ring.fraction
				if type(fraction) ~= "number" or fraction ~= fraction or fraction < 0 or fraction > 1 then return nil, "invalid_block" end
				local tone = capsule.tone_color(ring.tone or "accent")
				if not tone then return nil, "invalid_block" end
				copy.ring = { fraction = fraction, tone = tone }
			end
			cells[index] = copy
		end
		return { kind = "cells", cells = cells }, bytes
	end
	if kind == "table" then
		if not plain_text(block.title, 32) then return nil, "invalid_block" end
		local columns, rows = block.columns, block.rows
		if not plain_table(columns) or #columns < 1 or #columns > MAX_COLUMNS then return nil, "invalid_block" end
		if not plain_table(rows) or #rows < 1 or #rows > MAX_ROWS then return nil, "invalid_block" end
		local bytes = #block.title
		local copy = { kind = "table", title = block.title, columns = {}, rows = {} }
		for key in pairs(columns) do
			if type(key) ~= "number" or key < 1 or key > #columns or key % 1 ~= 0 then return nil, "invalid_block" end
		end
		for index = 1, #columns do
			if not plain_text(columns[index], 12) then return nil, "invalid_block" end
			copy.columns[index] = columns[index]
			bytes = bytes + #columns[index]
		end
		for key in pairs(rows) do
			if type(key) ~= "number" or key < 1 or key > #rows or key % 1 ~= 0 then return nil, "invalid_block" end
		end
		for index = 1, #rows do
			local row = rows[index]
			-- A row is a name, then one value for each column.
			if not plain_table(row) or #row ~= #columns + 1 then return nil, "invalid_block" end
			for key in pairs(row) do
				if type(key) ~= "number" or key < 1 or key > #row or key % 1 ~= 0 then return nil, "invalid_block" end
			end
			copy.rows[index] = {}
			for position = 1, #row do
				if not plain_text(row[position], 24) then return nil, "invalid_block" end
				copy.rows[index][position] = row[position]
				bytes = bytes + #row[position]
			end
		end
		if block.footer ~= nil then
			if not plain_text(block.footer, 160) then return nil, "invalid_block" end
			copy.footer = block.footer
			bytes = bytes + #block.footer
		end
		if block.open ~= nil and type(block.open) ~= "boolean" then return nil, "invalid_block" end
		copy.open = block.open
		if block.action ~= nil then
			local action, reason = read_action(block.action)
			if not action then return nil, reason end
			copy.action = action
			bytes = bytes + #action.label
		end
		return copy, bytes
	end
	local row, reason = capsule.read_row(block.row)
	if not row then return nil, reason end
	local copy = { kind = "row", row = row }
	local bytes = #(row.title or "") + #(row.badge or "")
	for _, label in ipairs(row.labels or {}) do bytes = bytes + #(type(label) == "table" and label.text or label) end
	if block.action ~= nil then
		local action, action_reason = read_action(block.action)
		if not action then return nil, action_reason end
		copy.action = action
		bytes = bytes + #action.label
	end
	if block.tooltip ~= nil then
		local tooltip, tooltip_reason = read_tooltip(block.tooltip)
		if not tooltip then return nil, tooltip_reason end
		copy.tooltip = tooltip
		bytes = bytes + #(tooltip.title or "")
		for _, line in ipairs(tooltip.lines) do bytes = bytes + #line end
	end
	return copy, bytes
end

-- Reads a spec. Returns a record { source, key, region, title, order, expires, blocks, bytes }
-- or nil and a reason. The record shares nothing with the spec.
function section.read(spec)
	if not plain_table(spec) or not known_keys(spec, SPEC_KEYS) then return nil, "invalid_section" end
	if not plain_string(spec.source, 64) then return nil, "invalid_source" end
	if not plain_string(spec.key, 64) then return nil, "invalid_key" end
	if type(spec.region) ~= "string" or not REGIONS[spec.region] then return nil, "invalid_region" end
	if spec.title ~= nil and not plain_text(spec.title, 32) then return nil, "invalid_title" end
	local limits = section.limits
	local order = spec.order
	if order == nil then order = limits.order_default end
	local low = section.builtin(spec.source) and 0 or limits.order_min
	if not usable(order) or type(order) ~= "number" or order ~= order or order % 1 ~= 0 or order < low or order > limits.order_max then
		return nil, "invalid_order"
	end
	local expires = spec.expires
	if expires ~= nil and (not usable(expires) or type(expires) ~= "number" or expires ~= expires or expires < 1 or expires > limits.expires_max) then
		return nil, "invalid_expires"
	end
	local list = spec.blocks
	if not plain_table(list) or #list > limits.blocks then return nil, "invalid_blocks" end
	for key in pairs(list) do
		if type(key) ~= "number" or key < 1 or key > #list or key % 1 ~= 0 then return nil, "invalid_blocks" end
	end
	local blocks, bytes = {}, #(spec.title or "")
	for index = 1, #list do
		local block, block_bytes = read_block(list[index])
		if not block then return nil, block_bytes end
		blocks[index] = block
		bytes = bytes + block_bytes
	end
	return { source = spec.source, key = spec.key, region = spec.region, title = spec.title, order = order,
		expires = expires, blocks = blocks, bytes = bytes }
end

-- The records, in the order the panes draw them: by region, then `order`, then
-- when they were made. `next_handle` gives every record a number from the same counter
-- as the notices, so one function can tell what a handle names.
function section.new_store(next_handle)
	local store = { records = {} }

	local function find(source, key)
		for _, record in pairs(store.records) do
			if record.source == source and record.key == key then return record end
		end
	end

	function store.count() local total = 0; for _ in pairs(store.records) do total = total + 1 end; return total end

	function store.bytes(source)
		local total = 0
		for _, record in pairs(store.records) do
			if record.source == source then total = total + record.bytes end
		end
		return total
	end

	function store.get(handle) return store.records[handle] end

	-- Adds a record, or replaces the one with the same source and key and returns its handle.
	-- The limits are checked against what the store would hold afterwards.
	function store.put(record, now)
		local limits = section.limits
		local existing = find(record.source, record.key)
		if not existing and store.count() >= limits.sections then return nil, "limit" end
		local others = store.bytes(record.source) - (existing and existing.bytes or 0)
		if others + record.bytes > limits.bytes then return nil, "limit" end
		record.expires_at = record.expires and (now + record.expires) or nil
		if existing then
			record.handle, record.created = existing.handle, existing.created
		else
			record.handle = next_handle()
			record.created = record.handle
		end
		store.records[record.handle] = record
		return record.handle
	end

	function store.remove(handle)
		if not store.records[handle] then return false end
		store.records[handle] = nil
		return true
	end

	function store.clear() store.records = {} end

	-- Drops what has not been refreshed in time. Returns whether anything went.
	function store.prune(now)
		local gone = false
		for handle, record in pairs(store.records) do
			if record.expires_at and record.expires_at <= now then store.records[handle] = nil; gone = true end
		end
		return gone
	end

	function store.list(region)
		local list = {}
		for _, record in pairs(store.records) do
			if record.region == region then list[#list + 1] = record end
		end
		table.sort(list, function(left, right)
			if left.order ~= right.order then return left.order < right.order end
			return left.created < right.created
		end)
		return list
	end

	return store
end
