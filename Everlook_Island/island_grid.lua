local Everlook = Everlook

-- The open island's 12-column grid. The margin is the inset every surface uses,
-- and the gutter is twice it: each pane keeps its own inset, so two panes sit a
-- gutter apart. A width is on the grid when its columns are whole pixels, which
-- the two panel widths are (36 and 12 pixel columns).
local grid = {}
Everlook.island_grid = grid

grid.columns, grid.margin, grid.gutter = 12, 12, 24
grid.widths = { one = 432, two = 720 }
-- Pane A is five columns and pane B seven, so the quests get the narrower side.
grid.pane_columns = 5

-- The width of one column at a panel width.
function grid.column(width)
	return (width - 2 * grid.margin - (grid.columns - 1) * grid.gutter) / grid.columns
end

-- The width of `count` columns and the gutters between them.
function grid.span(width, count)
	return count * grid.column(width) + (count - 1) * grid.gutter
end

-- Where column `index` (counting from 1) starts.
function grid.left(width, index)
	return grid.margin + (index - 1) * (grid.column(width) + grid.gutter)
end

-- The panel width that fits `available`: two panes when they fit, otherwise
-- one, otherwise whatever is left.
function grid.fit(two, available)
	if two and available >= grid.widths.two then return grid.widths.two, true end
	if available >= grid.widths.one then return grid.widths.one, false end
	return available, false
end

-- The x of the divider between the panes, and the width of the pane after it.
-- It sits in the middle of the gutter, so each pane has the margin on its side.
function grid.panes(width, two)
	if not two then return 0, width end
	local divider = grid.left(width, grid.pane_columns + 1) - grid.gutter / 2
	return divider, width - divider
end
