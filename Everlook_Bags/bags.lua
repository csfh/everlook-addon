local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local layout = Everlook.bags_layout
local item_level = Everlook.bags_item_level
local id = "bags"

-- Stock anchors the grid's bottom right corner 4 pixels above the money frame.
local GRID_OFFSET_Y = 4
local LABEL_FONT = "NumberFontNormalSmall"

local hooked = false
-- The size stock gave the frame on its last layout pass, and whether this
-- module has moved the slots since. Both are needed to put the frame back.
local stock_width, stock_height
local changed = false
-- A label belongs to a slot's button for as long as the game keeps the button.
local labels = setmetatable({}, { __mode = "k" })

local function secret(value)
	return issecretvalue and issecretvalue(value)
end

local function combined_bag()
	local frame = _G.ContainerFrameCombinedBags
	if type(frame) ~= "table" then return nil end
	for _, method in ipairs({ "EnumerateValidItems", "GetWidth", "GetHeight", "SetSize" }) do
		if type(frame[method]) ~= "function" then return nil end
	end
	return frame
end

local function remember_stock_size(frame)
	stock_width, stock_height = frame:GetWidth(), frame:GetHeight()
end

local function slots_of(frame)
	local slots = {}
	for _, button in frame:EnumerateValidItems() do
		slots[#slots + 1] = { button = button, bag = button:GetBagID(), slot = button:GetID(), extended = button:IsExtended() }
	end
	return slots
end

-- Lays the grid out in the given number of columns, anchored where stock
-- anchors it. At the stock column count this is the layout stock draws.
local function place(frame, columns)
	if not frame.MoneyFrame or not stock_width then return end
	local slots = layout.order(slots_of(frame))
	local grid = layout.grid(#slots, columns)
	for index, slot in ipairs(slots) do
		local position = grid.positions[index]
		slot.button:ClearAllPoints()
		slot.button:SetPoint("BOTTOMRIGHT", frame.MoneyFrame, "TOPRIGHT", position.x, GRID_OFFSET_Y + position.y)
	end
	frame:SetSize(layout.resized(stock_width, stock_height, #slots, columns))
end

local function gear_label(button)
	if type(C_Container) ~= "table" or type(C_Item) ~= "table" or type(ColorManager) ~= "table" then return nil end
	local info = C_Container.GetContainerItemInfo(button:GetBagID(), button:GetID())
	if type(info) ~= "table" then return nil end
	local item_id, link = info.itemID, info.hyperlink
	if secret(item_id) or secret(link) or type(item_id) ~= "number" or type(link) ~= "string" then return nil end
	local class_id = select(6, C_Item.GetItemInfoInstant(item_id))
	return item_level.label(class_id, info.quality, C_Item.GetDetailedItemLevelInfo(link))
end

local function show_labels(frame, wanted)
	for _, button in frame:EnumerateValidItems() do
		local content, quality
		if wanted then content, quality = gear_label(button) end
		local text = labels[button]
		if content then
			if not text then
				text = button:CreateFontString(nil, "OVERLAY", LABEL_FONT)
				text:SetDrawLayer("OVERLAY", 7)
				text:SetPoint("TOP", button, "TOP", 0, -2)
				labels[button] = text
			end
			local color = ColorManager.GetColorDataForItemQuality(quality)
			text:SetText(content)
			if color then text:SetTextColor(color.r, color.g, color.b) else text:SetTextColor(1, 1, 1) end
			text:Show()
		elseif text then
			text:Hide()
		end
	end
end

-- Stock has just drawn the grid and sized the frame. Anything wanted that
-- stock does not do is done over it.
local function on_layout(frame)
	if not module.enabled(id) then return end
	remember_stock_size(frame)
	local columns = module.get(id, "columns")
	changed = columns ~= layout.STOCK_COLUMNS
	if changed then place(frame, columns) end
end

-- Stock has refreshed what the slots hold, which is when a label can change.
local function on_items(frame)
	if module.enabled(id) then show_labels(frame, module.get(id, "item_level")) end
end

-- The hooks run after stock and cannot be taken off, so they check the
-- module is on each time. Methods stock owns are never replaced or called.
local function install(frame)
	if hooked or type(hooksecurefunc) ~= "function" then return end
	if type(frame.UpdateItemLayout) ~= "function" or type(frame.UpdateItems) ~= "function" then return end
	hooksecurefunc(frame, "UpdateItemLayout", on_layout)
	hooksecurefunc(frame, "UpdateItems", on_items)
	hooked = true
end

local function apply(enabled)
	local frame = combined_bag()
	if not frame then return end
	if enabled then install(frame) end
	local shown = type(frame.IsShown) == "function" and frame:IsShown()
	if not shown then
		-- A closed bag is laid out from scratch by stock when it opens.
		changed = false
		return
	end
	if not changed then remember_stock_size(frame) end
	local columns = enabled and module.get(id, "columns") or layout.STOCK_COLUMNS
	if changed or columns ~= layout.STOCK_COLUMNS then
		place(frame, columns)
		changed = columns ~= layout.STOCK_COLUMNS
	end
	show_labels(frame, enabled and module.get(id, "item_level"))
end

module.register({
	addon = addon_name, page = "interface", order = 90,
	id = id, name = "Bags",
	description = "Adds to the combined bag, which needs Combine all bags to be on in the game's settings. It keeps the bag's look, and its slots, search box and sort button stay the game's own. Turning this off puts the grid back as the game draws it, and a choice here does nothing until this is on.",
	options = {
		item_level = { name = "Show item level on gear", default = false, description = "Writes the item level of each weapon and piece of armor, including rings, trinkets and cloaks, at the top of its slot in the color of its quality. Other items show nothing, and turning this off removes the numbers." },
		columns = { name = "Columns", default = 10, min = 10, max = 16, step = 1, description = "How many slots sit in each row of the combined bag. Ten is how the game draws it, and more columns make the bag wider and shorter." },
	},
	apply = apply,
})
