local Everlook = Everlook

-- Two bars, along the top and bottom edges, each tracking its own figure. A bar
-- is a dim track with a fill on it, filling left to right. A secret reading
-- cannot be turned into a fraction, so the owner leaves that bar empty.
local rim = {}
Everlook.island_rim = rim

-- A small pill keeps its bars close to the border so its text stays clear. The
-- open island has room to hold them further in. CORNER keeps them off the
-- rounded corners.
local INSET_SMALL, INSET_LARGE, THICKNESS, CORNER, MARK = 5, 7, 2, 10, 8
local SMALL_HEIGHT = 44
local EDGES = { "top", "bottom" }
local TRACK = { 1, 1, 1, 0.12 }

rim.edges = EDGES

local function call(object, method, ...)
	local fn = object and object[method]
	if type(fn) == "function" then return fn(object, ...) end
end

local function inset_for(height)
	return height <= SMALL_HEIGHT and INSET_SMALL or INSET_LARGE
end

function rim.make(parent)
	local handle = { parent = parent, bars = {}, width = 0, height = 0 }
	for _, edge in ipairs(EDGES) do
		local track = call(parent, "CreateTexture", nil, "ARTWORK", nil, 5)
		call(track, "SetColorTexture", unpack(TRACK))
		call(track, "Hide")
		local fill = call(parent, "CreateTexture", nil, "OVERLAY", nil, 6)
		call(fill, "Hide")
		-- A small mark sits in one corner per bar, so each bar says what it tracks.
		local mark = call(parent, "CreateTexture", nil, "OVERLAY", nil, 7)
		call(mark, "SetSize", MARK, MARK)
		call(mark, "Hide")
		handle.bars[edge] = { track = track, fill = fill, mark = mark }
	end
	return handle
end

-- How long an edge's bar can be at this size, or nil when it does not fit.
function rim.length(width, height)
	local length = width - 2 * (inset_for(height) + CORNER)
	return length >= 12 and length or nil
end

-- The lit part of a bar for a fraction from 0 to 1.
function rim.lit(fraction, length)
	return math.max(0, math.min(1, fraction)) * length
end

-- Each bar's mark sits in the corner where the bar starts.
local MARK_CORNERS = { top = { "TOPLEFT", 1, -1 }, bottom = { "BOTTOMLEFT", 1, 1 } }

local function place(handle, edge)
	local bar = handle.bars[edge]
	local length = bar.fraction ~= nil and rim.length(handle.width, handle.height) or nil
	if not length then
		call(bar.track, "Hide")
		call(bar.fill, "Hide")
		call(bar.mark, "Hide")
		return
	end
	local parent, inset = handle.parent, inset_for(handle.height)
	local point, x, y
	if edge == "top" then point, x, y = "TOPLEFT", inset + CORNER, -inset
	else point, x, y = "BOTTOMLEFT", inset + CORNER, inset end
	local lit = rim.lit(bar.fraction, length)
	for _, piece in ipairs({ bar.track, bar.fill }) do
		call(piece, "ClearAllPoints")
		call(piece, "SetPoint", point, parent, point, x, y)
	end
	call(bar.track, "SetSize", length, THICKNESS)
	call(bar.track, "Show")
	-- Only the open island has the room; a small pill keeps its text clear.
	if bar.mark_name and handle.apply_mark and handle.height > SMALL_HEIGHT then
		local corner = MARK_CORNERS[edge]
		handle.apply_mark(bar.mark, bar.mark_name)
		call(bar.mark, "ClearAllPoints")
		call(bar.mark, "SetPoint", corner[1], parent, corner[1], corner[2] * (inset + 1), corner[3] * (inset + 1))
		call(bar.mark, "Show")
	else
		call(bar.mark, "Hide")
	end
	call(bar.fill, "SetColorTexture", unpack(bar.color))
	if lit >= 0.5 then
		call(bar.fill, "SetSize", lit, THICKNESS)
		call(bar.fill, "Show")
	else
		call(bar.fill, "Hide")
	end
end

-- fraction is nil to hide the bar. color is { r, g, b, a }. mark names the icon
-- that says what the bar tracks.
function rim.set(handle, edge, fraction, color, mark)
	local bar = handle and handle.bars[edge]
	if not bar then return end
	bar.fraction, bar.color, bar.mark_name = fraction, color or { 1, 1, 1, 1 }, mark
	place(handle, edge)
end

function rim.resize(handle, width, height)
	if not handle then return end
	handle.width, handle.height = width, height
	for _, edge in ipairs(EDGES) do
		if handle.bars[edge].fraction ~= nil then place(handle, edge) end
	end
end

function rim.fraction(handle, edge)
	local bar = handle and handle.bars[edge]
	return bar and bar.fraction
end
