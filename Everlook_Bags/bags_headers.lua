local addon_name = ...
local Everlook = Everlook
local layout = Everlook.bags_layout

-- A header over each section of the grouped bag: its name, how many slots it
-- holds, and the game's own divider under them. A header is a child of the
-- combined bag, and one is kept for each section for as long as the bag lives.
-- It lets clicks through to the slots, unless sections can be folded, when a
-- click on it folds its section and an arrow shows whether it is.
local DIVIDER_ATLAS = "Options_HorizontalDivider"
local OPEN_ATLAS = "campaign_headericon_open"
local CLOSED_ATLAS = "campaign_headericon_closed"
local ARROW_WIDTH = 16
local TITLE_FONT = "GameFontNormal"
local COUNT_FONT = "GameFontHighlightSmall"
local INSET = 2

local headers = {}
local made = {}

-- An atlas's own height, or nothing when this client has no such atlas.
local function atlas_height(atlas)
	if type(C_Texture) ~= "table" or type(C_Texture.GetAtlasInfo) ~= "function" then return nil end
	local info = C_Texture.GetAtlasInfo(atlas)
	if type(info) ~= "table" or type(info.height) ~= "number" or info.height <= 0 then return nil end
	return info.height
end

local function make(frame)
	local header = CreateFrame("Button", nil, frame)
	header:EnableMouse(false)
	local title = header:CreateFontString(nil, "OVERLAY", TITLE_FONT)
	title:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", INSET, 4)
	local count = header:CreateFontString(nil, "OVERLAY", COUNT_FONT)
	count:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -INSET, 4)
	local height = atlas_height(DIVIDER_ATLAS)
	if height then
		local rule = header:CreateTexture(nil, "ARTWORK")
		rule:SetAtlas(DIVIDER_ATLAS)
		rule:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
		rule:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
		rule:SetHeight(height)
	end
	return { frame = header, title = title, count = count }
end

-- The arrow and the click, made once and only for a header that can be folded.
local function make_foldable(header, key)
	header.key = key
	header.frame:RegisterForClicks("LeftButtonUp")
	header.frame:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
	header.frame:SetScript("OnClick", function()
		if header.on_click then header.on_click(key) end
	end)
	if atlas_height(OPEN_ATLAS) and atlas_height(CLOSED_ATLAS) then
		header.arrow = header.frame:CreateTexture(nil, "ARTWORK")
		header.arrow:SetPoint("BOTTOMLEFT", header.frame, "BOTTOMLEFT", INSET, 4)
		header.title:ClearAllPoints()
		header.title:SetPoint("BOTTOMLEFT", header.frame, "BOTTOMLEFT", INSET + ARROW_WIDTH, 4)
	end
end

-- Draws a header for each section of the grouped grid, up from `offset` above
-- the corner the grid is anchored to, and hides the headers it no longer needs.
-- With `on_click` a click on a header calls it with the section's key.
function headers.show(frame, anchor, offset, grouped, on_click)
	local used = {}
	for _, section in ipairs(grouped.sections) do
		local header = made[section.key]
		if not header then
			header = make(frame)
			made[section.key] = header
		end
		used[section.key] = true
		if on_click and not header.key then make_foldable(header, section.key) end
		header.on_click = on_click
		header.frame:EnableMouse(on_click ~= nil)
		if header.arrow then
			header.arrow:SetAtlas(section.collapsed and CLOSED_ATLAS or OPEN_ATLAS, true)
			if on_click then header.arrow:Show() else header.arrow:Hide() end
		end
		header.frame:ClearAllPoints()
		header.frame:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, offset + section.header_y)
		header.frame:SetSize(grouped.width, layout.HEADER_HEIGHT)
		header.title:SetText(section.title)
		header.count:SetText(tostring(section.count))
		header.frame:Show()
	end
	for key, header in pairs(made) do
		if not used[key] then header.frame:Hide() end
	end
end

function headers.hide_all()
	for _, header in pairs(made) do header.frame:Hide() end
end

Everlook.bags_headers = headers
