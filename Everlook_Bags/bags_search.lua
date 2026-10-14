local addon_name = ...
local Everlook = Everlook

-- The game's one search box sits on the combined bag at a width made for the
-- game's own grid. When this module changes the grid, the box is made as wide as
-- the frame less its left offset and the grid's inset from the frame's edge, so
-- its right edge meets the grid's. Only the width changes, never the anchor.
-- The inset is read while the layout is still the game's, when edges can be read.
local search = {}
local inset
local fitted = false

local function box_on(frame)
	local box = _G.BagItemSearchBox
	if type(box) ~= "table" or box.anchorBag ~= frame then return nil end
	return box
end

function search.measure(frame)
	inset = nil
	if type(frame.GetRight) ~= "function" or type(frame.MoneyFrame) ~= "table" or type(frame.MoneyFrame.GetRight) ~= "function" then return end
	local frame_right, grid_right = frame:GetRight(), frame.MoneyFrame:GetRight()
	if type(frame_right) == "number" and type(grid_right) == "number" then inset = frame_right - grid_right end
end

function search.fit(frame)
	local box = box_on(frame)
	if not box or not inset or type(box.GetPoint) ~= "function" or type(box.SetWidth) ~= "function" then return end
	local _, _, _, offset = box:GetPoint(1)
	if type(offset) ~= "number" then return end
	box:SetWidth(math.max(frame:GetWidth() - offset - inset, 1))
	fitted = true
end

-- The game's own anchor and width, put back by the game's own method.
function search.restore(frame)
	if not fitted then return end
	fitted = false
	local box = box_on(frame)
	if box and type(frame.SetSearchBoxPoint) == "function" and type(box.ClearAllPoints) == "function" then
		box:ClearAllPoints()
		frame:SetSearchBoxPoint(box)
	end
end

Everlook.bags_search = search
