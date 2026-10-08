local Everlook = Everlook
local wheel = {}
Everlook.wheel = wheel

-- A ring of labels around the cursor. Moving the cursor toward a label chooses it. The wheel only draws and
-- measures. What the labels do is up to the caller.

-- Pixels from the centre inside which nothing is chosen, so a press that never moves chooses nothing.
local DEAD_ZONE = 22
-- The ring is an ellipse, wider than tall, so labels that are wider than they are high do not touch.
local RADIUS_X, RADIUS_Y = 128, 98
local LABEL_HEIGHT, LABEL_PADDING = 30, 22
local EDGE_MARGIN_X, EDGE_MARGIN_Y = RADIUS_X + 70, RADIUS_Y + 30

local IDLE_FILL, IDLE_EDGE, IDLE_TEXT = { 0.05, 0.05, 0.07, 0.88 }, { 1, 1, 1, 0.22 }, { 1, 1, 1, 1 }
local CHOSEN_FILL, CHOSEN_EDGE, CHOSEN_TEXT = { 0.98, 0.78, 0.22, 1 }, { 1, 0.95, 0.7, 1 }, { 0.08, 0.06, 0.02, 1 }

local root, labels, dot
local count, chosen = 0, nil

-- Wedge 1 is straight up and the rest follow clockwise. Angles are the usual counterclockwise ones from the
-- positive x axis, so the screen's y axis points up.
local function angle_of(index, total)
	return math.pi / 2 - (index - 1) * 2 * math.pi / total
end

-- The wedge a cursor offset points at, or nil when it is inside the dead zone.
function wheel.sector(total, dx, dy)
	if total < 1 or dx * dx + dy * dy < DEAD_ZONE * DEAD_ZONE then return nil end
	local step = 2 * math.pi / total
	local clockwise_from_top = (math.pi / 2 - math.atan2(dy, dx)) % (2 * math.pi)
	return math.floor((clockwise_from_top + step / 2) / step) % total + 1
end

-- Where a label's centre sits relative to the wheel's centre: on the ellipse, along the wedge's own direction.
function wheel.position(index, total)
	local angle = angle_of(index, total)
	local cosine, sine = math.cos(angle), math.sin(angle)
	local reach = 1 / math.sqrt((cosine / RADIUS_X) ^ 2 + (sine / RADIUS_Y) ^ 2)
	return cosine * reach, sine * reach
end

local function paint(label, fill, edge, text)
	label.edge:SetColorTexture(edge[1], edge[2], edge[3], edge[4])
	label.fill:SetColorTexture(fill[1], fill[2], fill[3], fill[4])
	label.text:SetTextColor(text[1], text[2], text[3], text[4])
end

local function choose(index)
	if index == chosen then return end
	if chosen and labels[chosen] then paint(labels[chosen], IDLE_FILL, IDLE_EDGE, IDLE_TEXT) end
	chosen = index
	if chosen then paint(labels[chosen], CHOSEN_FILL, CHOSEN_EDGE, CHOSEN_TEXT) end
end

local function update()
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	local centre_x, centre_y = root.centre_x, root.centre_y
	choose(wheel.sector(count, x / scale - centre_x, y / scale - centre_y))
end

local function build_root()
	root = CreateFrame("Frame", "EverlookRadialWheel", UIParent)
	root:SetFrameStrata("FULLSCREEN_DIALOG")
	root:SetSize(1, 1)
	root:EnableMouse(false)
	root:Hide()
	labels = {}
	dot = root:CreateTexture(nil, "ARTWORK")
	dot:SetSize(10, 10)
	dot:SetPoint("CENTER", root, "CENTER")
	dot:SetColorTexture(1, 1, 1, 0.45)
	if root.CreateMaskTexture then
		local mask = root:CreateMaskTexture()
		mask:SetAllPoints(dot)
		mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		dot:AddMaskTexture(mask)
	end
	root:SetScript("OnUpdate", update)
end

local function build_label(index)
	local frame = CreateFrame("Frame", nil, root)
	frame:EnableMouse(false)
	frame:SetSize(80, LABEL_HEIGHT)
	local label = { frame = frame }
	label.edge = frame:CreateTexture(nil, "BACKGROUND")
	label.edge:SetAllPoints(frame)
	label.fill = frame:CreateTexture(nil, "BORDER")
	label.fill:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
	label.fill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
	label.text = frame:CreateFontString(nil, "OVERLAY")
	label.text:SetFontObject("GameFontHighlightLarge")
	label.text:SetPoint("CENTER", frame, "CENTER")
	labels[index] = label
	return label
end

function wheel.is_open()
	return root ~= nil and root:IsShown()
end

function wheel.selected()
	-- Key release can arrive after the cursor moves but before the next rendered frame.
	if wheel.is_open() then update() end
	return chosen
end

-- Open the wheel with one label per entry of `texts`, centred on (x, y) in interface units. The centre is moved
-- inward when the labels would run off the screen, and the choice is measured from the centre it ends up with.
function wheel.open(texts, x, y)
	if not root then build_root() end
	count, chosen = #texts, nil
	root.centre_x = math.max(EDGE_MARGIN_X, math.min(UIParent:GetWidth() - EDGE_MARGIN_X, x))
	root.centre_y = math.max(EDGE_MARGIN_Y, math.min(UIParent:GetHeight() - EDGE_MARGIN_Y, y))
	root:ClearAllPoints()
	root:SetPoint("CENTER", UIParent, "BOTTOMLEFT", root.centre_x, root.centre_y)
	for index = 1, math.max(count, #labels) do
		local label = labels[index]
		if index > count then
			if label then label.frame:Hide() end
		else
			label = label or build_label(index)
			label.text:SetText(texts[index])
			label.frame:SetWidth(label.text:GetStringWidth() + 2 * LABEL_PADDING)
			local offset_x, offset_y = wheel.position(index, count)
			label.frame:ClearAllPoints()
			label.frame:SetPoint("CENTER", root, "CENTER", offset_x, offset_y)
			paint(label, IDLE_FILL, IDLE_EDGE, IDLE_TEXT)
			label.frame:Show()
		end
	end
	root:Show()
end

function wheel.close()
	chosen = nil
	if root then root:Hide() end
end
