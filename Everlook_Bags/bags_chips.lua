local addon_name = ...
local Everlook = Everlook
local layout = Everlook.bags_layout

-- A row of chips over the grouped bag, wrapped to the grid's width: one for all
-- the sections and one for each, with its name and how many slots it holds. A
-- click on a chip calls back with its key. The chips share a frame that is a
-- child of the combined bag, and each is made once.
local TITLE_FONT = "GameFontHighlightSmall"
local COUNT_FONT = "GameFontDisableSmall"
local PADDING = 8
local COUNT_GAP = 4
local FILL = { 1, 1, 1, 0.08 }
local FILL_SELECTED = { 1, 0.82, 0, 0.22 }

local chips = { ALL = "all" }
local list
local made = {}

local function make_list(frame)
	list = CreateFrame("Frame", nil, frame)
	list:EnableMouse(false)
end

local function make_chip(index)
	local chip = CreateFrame("Button", nil, list)
	chip:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
	chip:RegisterForClicks("LeftButtonUp")
	chip.fill = chip:CreateTexture(nil, "BACKGROUND")
	chip.fill:SetAllPoints(chip)
	chip.title = chip:CreateFontString(nil, "OVERLAY", TITLE_FONT)
	chip.title:SetPoint("LEFT", chip, "LEFT", PADDING, 0)
	chip.count = chip:CreateFontString(nil, "OVERLAY", COUNT_FONT)
	chip.count:SetPoint("RIGHT", chip, "RIGHT", -PADDING, 0)
	chip:SetScript("OnClick", function(self) if self.on_click and self.key then self.on_click(self.key) end end)
	made[index] = chip
	return chip
end

-- Draws the chips with `entries`, each { key, title, count }, as wide as the grid and with
-- their bottom right corner `offset` above `anchor`. The chip whose key is `selected` stays
-- lit. It returns how tall the chips are together.
function chips.show(frame, anchor, offset, grid_width, entries, selected, on_click)
	if not list then make_list(frame) end
	local widths = {}
	for index, entry in ipairs(entries) do
		local chip = made[index] or make_chip(index)
		chip.title:SetText(entry.title)
		chip.count:SetText(tostring(entry.count))
		widths[index] = PADDING + chip.title:GetStringWidth() + COUNT_GAP + chip.count:GetStringWidth() + PADDING
	end
	local placed = layout.chips(widths, grid_width)
	list:ClearAllPoints()
	list:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, offset)
	list:SetSize(grid_width, placed.height)
	for index, entry in ipairs(entries) do
		local chip, spot = made[index], placed.items[index]
		chip.key, chip.on_click = entry.key, on_click
		chip:ClearAllPoints()
		chip:SetPoint("TOPLEFT", list, "TOPLEFT", spot.x, -(spot.row - 1) * (layout.CHIP_HEIGHT + layout.CHIP_GAP))
		chip:SetSize(spot.width, layout.CHIP_HEIGHT)
		if entry.key == selected then
			chip:LockHighlight()
			chip.fill:SetColorTexture(unpack(FILL_SELECTED))
		else
			chip:UnlockHighlight()
			chip.fill:SetColorTexture(unpack(FILL))
		end
		chip:Show()
	end
	for index = #entries + 1, #made do made[index]:Hide() end
	list:Show()
	return placed.height
end

function chips.hide()
	if list then list:Hide() end
end

Everlook.bags_chips = chips
