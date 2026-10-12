local addon_name = ...
local Everlook = Everlook
local layout = Everlook.bags_layout

-- A list of the grouped bag's sections to the left of the grid, each row with
-- the section's name and how many slots it holds, and a first row for all of
-- them. A click on a row calls back with its key. The list is a child of the
-- combined bag and is made once.
local TITLE_FONT = "GameFontNormal"
local COUNT_FONT = "GameFontHighlightSmall"
local INSET = 4

local sidebar = { ALL = "all" }
local list
local rows = {}

local function make_list(frame)
	list = CreateFrame("Frame", nil, frame)
	list:EnableMouse(false)
end

local function make_row(index)
	local row = CreateFrame("Button", nil, list)
	row:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
	row:RegisterForClicks("LeftButtonUp")
	row.title = row:CreateFontString(nil, "OVERLAY", TITLE_FONT)
	row.title:SetPoint("LEFT", row, "LEFT", INSET, 0)
	row.count = row:CreateFontString(nil, "OVERLAY", COUNT_FONT)
	row.count:SetPoint("RIGHT", row, "RIGHT", -INSET, 0)
	row:SetScript("OnClick", function(self) if self.on_click and self.key then self.on_click(self.key) end end)
	rows[index] = row
	return row
end

-- Draws the list with `entries`, each { key, title, count }, bottom right corner
-- `offset` above `anchor` and `gap` left of the grid. The row whose key is
-- `selected` stays lit.
function sidebar.show(frame, anchor, offset, grid_width, entries, selected, on_click)
	if not list then make_list(frame) end
	local height = #entries * layout.SIDEBAR_ROW_HEIGHT
	list:ClearAllPoints()
	list:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", -(grid_width + layout.SIDEBAR_GAP), offset)
	list:SetSize(layout.SIDEBAR_WIDTH, height)
	for index, entry in ipairs(entries) do
		local row = rows[index] or make_row(index)
		row.key, row.on_click = entry.key, on_click
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(index - 1) * layout.SIDEBAR_ROW_HEIGHT)
		row:SetSize(layout.SIDEBAR_WIDTH, layout.SIDEBAR_ROW_HEIGHT)
		row.title:SetText(entry.title)
		row.count:SetText(tostring(entry.count))
		if entry.key == selected then row:LockHighlight() else row:UnlockHighlight() end
		row:Show()
	end
	for index = #entries + 1, #rows do rows[index]:Hide() end
	list:Show()
end

function sidebar.hide()
	if list then list:Hide() end
end

Everlook.bags_sidebar = sidebar
