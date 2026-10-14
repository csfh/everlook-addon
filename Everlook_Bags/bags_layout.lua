local addon_name = ...
local Everlook = Everlook

-- The numbers behind the stock combined bag's grid, from ContainerFrame.lua:
-- 37 pixel slots, 5 pixels apart, ten to a row, filled from the bottom right.
local ITEM_SIZE = 37
local SPACING = 5
local STEP = ITEM_SIZE + SPACING

local layout = { STOCK_COLUMNS = 10 }

-- The slot buttons the game has made, in order. Its own walk runs to the size of the
-- bag and meets a hole where a button is not made yet, which a plain loop cannot skip.
function layout.buttons_of(frame)
	local found = {}
	for _, button in frame:EnumerateValidItems() do
		if button ~= nil then found[#found + 1] = button end
	end
	return found
end

local function span(count)
	return count * ITEM_SIZE + (count - 1) * SPACING
end

-- Where each slot goes, as an offset from the bottom right corner of the grid.
-- A slot to the left has a negative x and a slot on a higher row a positive y.
function layout.grid(count, columns)
	local rows = math.ceil(count / columns)
	local positions = {}
	for index = 1, count do
		positions[index] = {
			x = 0 - ((index - 1) % columns) * STEP,
			y = math.floor((index - 1) / columns) * STEP,
		}
	end
	return { rows = rows, positions = positions, width = span(columns), height = span(rows) }
end

-- The size of the stock frame when its grid has a different column count. The
-- rest of the frame, its title bar, search box and money, stays as stock sized it.
function layout.resized(stock_width, stock_height, count, columns)
	local stock = layout.grid(count, layout.STOCK_COLUMNS)
	local wanted = layout.grid(count, columns)
	return stock_width + wanted.width - stock.width, stock_height + wanted.height - stock.height
end

-- Sections stacked top to bottom, each a header over its own grid. The grid is
-- anchored at its bottom right corner and the offsets run up and to the left of
-- it, so the bottom section starts at the anchor and each section above clears
-- the one below. A row of slots is full width, a short last row fills from the left.
layout.HEADER_HEIGHT = 20
local HEADER_GAP = 4
local SECTION_GAP = 10

-- From this many columns small sections can share a row, because a row is wide enough
-- for several of them and their headers.
layout.PACK_COLUMNS = 12

function layout.packs(columns)
	return columns >= layout.PACK_COLUMNS
end

-- How many slot widths a section is as wide as: its slots in one row, or its header, which
-- the caller measures in pixels, when that is wider. A section of more than one row, and
-- one wider than the grid, is the whole grid. A hidden section is nothing.
local function cells_of(section, drawn, columns)
	local wanted = section.state == "collapsed" and 0 or drawn
	if section.header_width then
		wanted = math.max(wanted, math.ceil((section.header_width + SPACING) / STEP))
	end
	return math.min(wanted, columns)
end

-- The rows of sections stacked top to bottom, each a header over its own slots. With
-- `pack`, consecutive sections of one row go side by side, in stock order and a slot's
-- width apart, for as long as they fit, and every other section is a row of its own.
local function bands_of(entries, columns, pack)
	local bands = {}
	for _, entry in ipairs(entries) do
		local band = bands[#bands]
		local joins = pack and band ~= nil and entry.single and band.single
			and band.cells + 1 + entry.cells <= columns
		if not joins then
			band = { members = {}, cells = 0, single = pack and entry.single }
			bands[#bands + 1] = band
		end
		entry.start = band.cells > 0 and band.cells + 1 or 0
		band.cells = entry.start + entry.cells
		band.members[#band.members + 1] = entry
	end
	return bands
end

-- A section is open, "collapsed" to its header alone, or "hidden" without even that. An
-- open one draws `visible` of its slots when that is less than its count, and its count stays.
-- Sections that share a row have their headers on one level, as wide as the section.
function layout.grouped(sections, columns, pack)
	local entries = {}
	for _, section in ipairs(sections) do
		if section.count > 0 and section.state ~= "hidden" then
			local collapsed = section.state == "collapsed"
			local drawn = collapsed and 0 or math.min(section.visible or section.count, section.count)
			local rows = math.ceil(drawn / columns)
			local cells = rows > 1 and columns or cells_of(section, drawn, columns)
			entries[#entries + 1] = {
				section = section, collapsed = collapsed, drawn = drawn, rows = rows, cells = cells,
				single = rows <= 1,
			}
		end
	end
	local bands = bands_of(entries, columns, pack)
	local placed = {}
	local bottom, height = 0, 0
	for index = #bands, 1, -1 do
		local band = bands[index]
		local rows_height = 0
		for _, entry in ipairs(band.members) do
			if entry.rows > 0 then rows_height = math.max(rows_height, span(entry.rows)) end
		end
		local header_y = bottom + (rows_height > 0 and rows_height + HEADER_GAP or 0)
		local alone = #band.members == 1
		local group = {}
		for _, entry in ipairs(band.members) do
			local section = entry.section
			local result = { key = section.key, title = section.title, count = section.count, positions = {}, header_y = header_y }
			if entry.collapsed then result.collapsed = true end
			local first = alone and 0 or entry.start
			for slot = 1, entry.drawn do
				local row_from_top = math.floor((slot - 1) / columns)
				local column = alone and (slot - 1) % columns or first + slot - 1
				result.positions[slot] = {
					x = 0 - (columns - 1 - column) * STEP,
					y = bottom + (entry.rows - 1 - row_from_top) * STEP,
				}
			end
			if alone then
				result.header_x, result.header_width = 0, span(columns)
			else
				result.header_x, result.header_width = 0 - (columns - first - entry.cells) * STEP, span(entry.cells)
			end
			group[#group + 1] = result
		end
		for member = #group, 1, -1 do table.insert(placed, 1, group[member]) end
		height = header_y + layout.HEADER_HEIGHT
		bottom = height + SECTION_GAP
	end
	return { sections = placed, width = span(columns), height = height }
end

-- Chips, one for each section and one for everything, wrapped in rows over the grid
-- and as wide as it. A chip is as wide as its text needs, which the caller measures,
-- and one wider than the room is cut to it and takes a row alone.
layout.CHIP_HEIGHT = 22
layout.CHIP_GAP = 6
layout.CHIPS_MARGIN = 8

function layout.chips(widths, available)
	local items = {}
	local row, x = 1, 0
	for index, wanted in ipairs(widths) do
		local width = math.min(wanted, available)
		if x > 0 and x + width > available then
			row = row + 1
			x = 0
		end
		items[index] = { x = x, row = row, width = width }
		x = x + width + layout.CHIP_GAP
	end
	local rows = #items > 0 and row or 0
	local height = rows > 0 and rows * layout.CHIP_HEIGHT + (rows - 1) * layout.CHIP_GAP or 0
	return { items = items, rows = rows, height = height }
end

-- The size of the stock frame when its grid is the grouped one. Chips over the grid,
-- `chips_height` tall, make it taller by that and the margin below them, and no wider.
function layout.grouped_size(stock_width, stock_height, count, grouped, chips_height)
	local stock = layout.grid(count, layout.STOCK_COLUMNS)
	local height = grouped.height
	if chips_height and chips_height > 0 then height = height + chips_height + layout.CHIPS_MARGIN end
	return stock_width + grouped.width - stock.width, stock_height + height - stock.height
end

-- The order stock lays slots out in: a locked slot last, then the bags from the
-- last to the first, and the slots in each bag from the first.
function layout.order(entries)
	local ordered = {}
	for index, entry in ipairs(entries) do ordered[index] = entry end
	table.sort(ordered, function(first, second)
		if (first.extended == true) ~= (second.extended == true) then return second.extended == true end
		if first.bag ~= second.bag then return first.bag > second.bag end
		return first.slot < second.slot
	end)
	return ordered
end

Everlook.bags_layout = layout
