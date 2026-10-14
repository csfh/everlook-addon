local addon_name = ...
local Everlook = Everlook
local layout = Everlook.bags_layout

-- A header over each section of the grouped bag: its name, how many slots it
-- holds beside it, and the game's own divider under them. A header is a child of the
-- combined bag, and one is kept for each section for as long as the bag lives.
-- It lets clicks through to the slots, unless sections can be folded, when a
-- click on it folds its section and an arrow shows whether it is.
local DIVIDER_ATLAS = "Options_HorizontalDivider"
local OPEN_ATLAS = "campaign_headericon_open"
local CLOSED_ATLAS = "campaign_headericon_closed"
local ARROW_GAP = 4
local COUNT_GAP = 6
local TITLE_FONT = "GameFontNormal"
local COUNT_FONT = "GameFontDisableSmall"
local INSET = 2

local headers = {}
local made = {}

-- An atlas's own size, or nothing when this client has no such atlas.
local function atlas_size(atlas)
	if type(C_Texture) ~= "table" or type(C_Texture.GetAtlasInfo) ~= "function" then return nil end
	local info = C_Texture.GetAtlasInfo(atlas)
	if type(info) ~= "table" or type(info.height) ~= "number" or info.height <= 0
		or type(info.width) ~= "number" or info.width <= 0 then
		return nil
	end
	return info.width, info.height
end

local function atlas_height(atlas)
	local _, height = atlas_size(atlas)
	return height
end

-- Text and arrow are centred in the room the divider leaves above it.
local function make(frame)
	local header = CreateFrame("Button", nil, frame)
	header:EnableMouse(false)
	local rule_height = atlas_height(DIVIDER_ATLAS)
	local lift = (rule_height or 0) / 2
	local title = header:CreateFontString(nil, "OVERLAY", TITLE_FONT)
	title:SetPoint("LEFT", header, "LEFT", INSET, lift)
	local count = header:CreateFontString(nil, "OVERLAY", COUNT_FONT)
	count:SetPoint("LEFT", title, "RIGHT", COUNT_GAP, 0)
	if rule_height then
		local rule = header:CreateTexture(nil, "ARTWORK")
		rule:SetAtlas(DIVIDER_ATLAS)
		rule:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
		rule:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
		rule:SetHeight(rule_height)
	end
	return { frame = header, title = title, count = count, lift = lift }
end

-- The arrow and the click, made once and only for a header that can be folded.
-- The arrow is drawn at its atlas's own size, as the game draws its headers, and
-- the title starts after the wider of the two, so the two cannot overlap.
local function make_foldable(header, key)
	header.key = key
	header.frame:RegisterForClicks("LeftButtonUp")
	header.frame:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
	header.frame:SetScript("OnClick", function()
		if header.on_click then header.on_click(key) end
	end)
	local open_width, open_height = atlas_size(OPEN_ATLAS)
	local closed_width, closed_height = atlas_size(CLOSED_ATLAS)
	if open_width and closed_width and open_height and closed_height then
		header.arrow = header.frame:CreateTexture(nil, "ARTWORK")
		header.arrow:SetPoint("LEFT", header.frame, "LEFT", INSET, header.lift)
		header.arrow_room = math.max(open_width, closed_width) + ARROW_GAP
	end
end

-- The title is at the header's edge, or after the arrow while one is shown.
local function place_title(header, arrow_shown)
	local x = INSET + (arrow_shown and header.arrow_room or 0)
	header.title:ClearAllPoints()
	header.title:SetPoint("LEFT", header.frame, "LEFT", x, header.lift)
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
		place_title(header, header.arrow ~= nil and on_click ~= nil)
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
