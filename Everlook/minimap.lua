local addonName, Everlook = ...

local ICON = "Interface\\AddOns\\Everlook\\assets\\logo.tga"
local DEFAULT_ANGLE = 160

local button

local function MinimapSettings()
	local minimap = EverlookDB and EverlookDB.minimap
	if type(minimap) == "table" then
		return minimap
	end
end

local function Angle()
	local minimap = MinimapSettings()
	local angle = minimap and minimap.angle
	if type(angle) == "number" then
		return angle
	end
	return DEFAULT_ANGLE
end

local function Place()
	if button:GetParent() ~= Minimap then
		return
	end
	local angle = math.rad(Angle())
	local radius = (math.max(Minimap:GetWidth(), Minimap:GetHeight()) / 2) + 5
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function DragOnUpdate(self)
	if self:GetParent() ~= Minimap then
		self:SetScript("OnUpdate", nil)
		return
	end
	local mx, my = Minimap:GetCenter()
	if not mx or not my then
		return
	end
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	cx, cy = cx / scale, cy / scale
	EverlookDB.minimap = MinimapSettings() or {}
	EverlookDB.minimap.angle = math.deg(math.atan2(cy - my, cx - mx))
	Place()
end

local function CreateButton()
	button = CreateFrame("Button", "EverlookMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:SetClampedToScreen(true)
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local overlay = button:CreateTexture(nil, "OVERLAY")
	overlay:SetSize(53, 53)
	overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	overlay:SetPoint("TOPLEFT")

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetSize(20, 20)
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetPoint("TOPLEFT", 7, -5)

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(20, 20)
	icon:SetTexture(ICON)
	icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	icon:SetPoint("TOPLEFT", 7, -5)
	button.icon = icon

	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Everlook")
		if Everlook.config and Everlook.config.describe then
			local _, line, r, g, b = Everlook.config.describe()
			GameTooltip:AddLine(line, r, g, b, true)
		end
		if Everlook.world and Everlook.world.session_new and Everlook.world.collected then
			local total = 0
			local collected = Everlook.world.collected()
			for index = 1, #collected do
				total = total + (collected[index].count or 0)
			end
			GameTooltip:AddLine(Everlook.world.session_new() .. " new this session. " .. total .. " rows.", 0.8, 0.8, 0.8)
		end
		GameTooltip:AddLine("Click to open the settings.", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:SetScript("OnClick", function()
		if Everlook.settings then Everlook.settings.toggle() end
	end)

	button:SetMovable(true)
	button:RegisterForDrag("LeftButton")
	button:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		self:SetScript("OnUpdate", DragOnUpdate)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		Place()
	end)

	Place()
	button:Show()
end

EventUtil.ContinueOnAddOnLoaded(addonName, function()
	EverlookDB = EverlookDB or {}

	local minimap = EverlookDB.minimap
	if type(minimap) == "table" then
		minimap.icon = nil
	else
		EverlookDB.minimap = nil
	end

	CreateButton()
	EventUtil.ContinueOnPlayerLogin(Place)
end)
