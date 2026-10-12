local addon_name = ...
local Everlook = Everlook
local junk = Everlook.bags_junk
local layout = Everlook.bags_layout

-- A coin button in the bag's title row turns mark mode on. While it is on,
-- each slot gets a transparent button over it that marks or unmarks the item
-- in that slot, so the game's own click and drag on the slot stay untouched
-- and the slot's own handlers never run. A marked item shows the game's junk
-- coin. Everything here is added to the stock frame; none of it replaces
-- anything the game made.
local COIN_ATLAS = "bags-junkcoin"
local BUTTON_SIZE = 22
local OVERLAY_LEVELS_ABOVE_SLOT = 5
-- The bag's own children, such as the button over its title that opens the bag menu, sit just
-- above the bag. The coin must be above them to get its click, and below the 510 the game gives
-- the add-slots button.
local COIN_LEVELS_ABOVE_BAG = 20

local marker = {}
local bag, coin_button, hide_hooked
local mode = false
-- Per slot button, for as long as the game keeps it.
local overlays = setmetatable({}, { __mode = "k" })
local coins = setmetatable({}, { __mode = "k" })

local function item_id_of(button)
	if type(C_Container) ~= "table" or type(C_Container.GetContainerItemInfo) ~= "function" then return nil end
	local info = C_Container.GetContainerItemInfo(button:GetBagID(), button:GetID())
	if type(info) ~= "table" then return nil end
	local item_id = info.itemID
	if not junk.valid(item_id) then return nil end
	return item_id
end

local function show_coin(button, marked)
	local coin = coins[button]
	if marked then
		if not coin then
			coin = button:CreateTexture(nil, "OVERLAY", nil, 5)
			coin:SetAtlas(COIN_ATLAS, true)
			coin:SetPoint("TOPLEFT", button, "TOPLEFT", 1, 0)
			coins[button] = coin
		end
		coin:Show()
	elseif coin then
		coin:Hide()
	end
end

local function refresh_coins(active)
	local data = junk.data()
	for _, button in ipairs(layout.buttons_of(bag)) do
		local item_id = active and item_id_of(button)
		show_coin(button, item_id ~= nil and junk.is_marked(data, item_id))
	end
	if not active then
		for _, coin in pairs(coins) do coin:Hide() end
	end
end

local function say_on_tooltip(owner, button)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	local item_id = item_id_of(button)
	if not item_id then
		GameTooltip:Hide()
		return
	end
	GameTooltip:SetBagItem(button:GetBagID(), button:GetID())
	GameTooltip:AddLine(junk.is_marked(junk.data(), item_id) and "Click to mark this as not junk" or "Click to mark this as junk")
	GameTooltip:Show()
end

local function toggle_slot(overlay, button)
	local item_id = item_id_of(button)
	if not item_id then return end
	junk.toggle(junk.data(), item_id)
	refresh_coins(true)
	say_on_tooltip(overlay, button)
end

local function overlay_of(button)
	local overlay = overlays[button]
	if overlay then return overlay end
	overlay = CreateFrame("Button", nil, button)
	overlay:SetAllPoints(button)
	overlay:SetFrameLevel(button:GetFrameLevel() + OVERLAY_LEVELS_ABOVE_SLOT)
	overlay:RegisterForClicks("LeftButtonUp")
	overlay:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
	overlay:SetScript("OnClick", function(self) toggle_slot(self, button) end)
	overlay:SetScript("OnEnter", function(self) say_on_tooltip(self, button) end)
	overlay:SetScript("OnLeave", function() GameTooltip:Hide() end)
	overlays[button] = overlay
	return overlay
end

local function refresh_overlays()
	if not mode then
		for _, overlay in pairs(overlays) do overlay:Hide() end
		return
	end
	for _, button in ipairs(layout.buttons_of(bag)) do overlay_of(button):Show() end
end

local function set_mode(on)
	local was = mode
	mode = on
	if coin_button then
		if on then coin_button:LockHighlight() else coin_button:UnlockHighlight() end
	end
	refresh_overlays()
	if was and not on and marker.on_stop then marker.on_stop(bag) end
end

local function make_coin_button()
	local close = bag.CloseButton
	if coin_button or type(close) ~= "table" then return end
	coin_button = CreateFrame("Button", nil, bag)
	coin_button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	coin_button:SetFrameLevel(bag:GetFrameLevel() + COIN_LEVELS_ABOVE_BAG)
	coin_button:SetPoint("RIGHT", close, "LEFT", -2, 0)
	local icon = coin_button:CreateTexture(nil, "ARTWORK")
	icon:SetAtlas(COIN_ATLAS, true)
	icon:SetPoint("CENTER")
	coin_button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
	coin_button:RegisterForClicks("LeftButtonUp")
	coin_button:SetScript("OnClick", function() set_mode(not mode) end)
	coin_button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Mark junk")
		GameTooltip:AddLine("Click items to mark or unmark them as junk, then click here again to stop. A marked item shows the junk coin, and every copy of it is marked.")
		GameTooltip:Show()
	end)
	coin_button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Whether mark mode is on. Whoever moves slots around waits for it to end, so
-- the slot under the cursor stays put while marks are made.
function marker.is_active()
	return mode
end

-- Set by the caller: runs with the bag when mark mode ends by a click on the
-- coin or by the bag closing.
marker.on_stop = nil

-- Brings the bag in line with the settings: the button, the coins and, in mark
-- mode, the overlays are there when the marker is on, and gone when it is off.
-- It is safe to call again whenever the slots may have changed.
function marker.apply(frame, active)
	bag = frame
	if active then
		make_coin_button()
		if coin_button then coin_button:Show() end
		if not hide_hooked and type(frame.HookScript) == "function" then
			frame:HookScript("OnHide", function() if mode then set_mode(false) end end)
			hide_hooked = true
		end
	else
		mode = false
		if coin_button then
			coin_button:Hide()
			coin_button:UnlockHighlight()
		end
	end
	refresh_coins(active)
	refresh_overlays()
end

Everlook.bags_marker = marker
