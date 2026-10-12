local addon_name = ...
local Everlook = Everlook

-- The numbers behind the stock combined bag's grid, from ContainerFrame.lua:
-- 37 pixel slots, 5 pixels apart, ten to a row, filled from the bottom right.
local ITEM_SIZE = 37
local SPACING = 5
local STEP = ITEM_SIZE + SPACING

local layout = { STOCK_COLUMNS = 10 }

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

function layout.grouped(sections, columns)
	local placed = {}
	local last = #sections
	local bottom, height = 0, 0
	for index = last, 1, -1 do
		local section = sections[index]
		if section.count > 0 then
			local rows = math.ceil(section.count / columns)
			local rows_height = span(rows)
			local positions = {}
			for slot = 1, section.count do
				local row_from_top = math.floor((slot - 1) / columns)
				positions[slot] = {
					x = 0 - (columns - 1 - (slot - 1) % columns) * STEP,
					y = bottom + (rows - 1 - row_from_top) * STEP,
				}
			end
			local section_height = layout.HEADER_HEIGHT + HEADER_GAP + rows_height
			table.insert(placed, 1, {
				key = section.key, title = section.title, count = section.count,
				header_y = bottom + rows_height + HEADER_GAP, positions = positions,
			})
			height = bottom + section_height
			bottom = height + SECTION_GAP
		end
	end
	return { sections = placed, width = span(columns), height = height }
end

-- The size of the stock frame when its grid is the grouped one.
function layout.grouped_size(stock_width, stock_height, count, grouped)
	local stock = layout.grid(count, layout.STOCK_COLUMNS)
	return stock_width + grouped.width - stock.width, stock_height + grouped.height - stock.height
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
