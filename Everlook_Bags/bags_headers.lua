local addon_name = ...
local Everlook = Everlook
local layout = Everlook.bags_layout

-- A header over each section of the grouped bag: its name, how many slots it
-- holds, and the game's own divider under them. A header is a child of the
-- combined bag that lets clicks through to the slots, and one is kept for each
-- section for as long as the bag lives.
local DIVIDER_ATLAS = "Options_HorizontalDivider"
local TITLE_FONT = "GameFontNormal"
local COUNT_FONT = "GameFontHighlightSmall"
local INSET = 2

local headers = {}
local made = {}

-- The divider's own height, or nothing when this client has no such atlas.
local function divider_height()
	if type(C_Texture) ~= "table" or type(C_Texture.GetAtlasInfo) ~= "function" then return nil end
	local info = C_Texture.GetAtlasInfo(DIVIDER_ATLAS)
	if type(info) ~= "table" or type(info.height) ~= "number" or info.height <= 0 then return nil end
	return info.height
end

local function make(frame)
	local header = CreateFrame("Frame", nil, frame)
	header:EnableMouse(false)
	local title = header:CreateFontString(nil, "OVERLAY", TITLE_FONT)
	title:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", INSET, 4)
	local count = header:CreateFontString(nil, "OVERLAY", COUNT_FONT)
	count:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -INSET, 4)
	local height = divider_height()
	if height then
		local rule = header:CreateTexture(nil, "ARTWORK")
		rule:SetAtlas(DIVIDER_ATLAS)
		rule:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
		rule:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
		rule:SetHeight(height)
	end
	return { frame = header, title = title, count = count }
end

-- Draws a header for each section of the grouped grid, up from `offset` above
-- the corner the grid is anchored to, and hides the headers it no longer needs.
function headers.show(frame, anchor, offset, grouped)
	local used = {}
	for _, section in ipairs(grouped.sections) do
		local header = made[section.key]
		if not header then
			header = make(frame)
			made[section.key] = header
		end
		used[section.key] = true
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
