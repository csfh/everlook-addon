local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local layout = Everlook.bags_layout
local item_level = Everlook.bags_item_level
local junk = Everlook.bags_junk
local categories = Everlook.bags_categories
local pins = Everlook.bags_pins
local recent = Everlook.bags_recent
local headers = Everlook.bags_headers
local marker = Everlook.bags_marker
local id = "bags"

-- Stock anchors the grid's bottom right corner 4 pixels above the money frame.
local GRID_OFFSET_Y = 4
-- Stock draws a stack count in this font, 5 pixels in from the bottom right. Gear never
-- stacks, so the item level takes the same place and cannot collide with a count.
local LABEL_FONT = "NumberFontNormal"

local hooked = false
-- The size stock gave the frame on its last layout pass, and whether this
-- module has moved the slots since. Both are needed to put the frame back.
local stock_width, stock_height
local changed = false
-- A label belongs to a slot's button for as long as the game keeps the button.
local labels = setmetatable({}, { __mode = "k" })
-- What arrived in the bags this session. It starts afresh whenever recent items are turned on.
local arrivals = recent.new()
-- Whether the bags can be read, which is only so once the player is in the world: at login the
-- game has not filled them yet, and a look then would count what was always there as arrived.
-- It is set by the first PLAYER_ENTERING_WORLD, or at once when Bags is turned on in a session
-- that is already running. Later loading screens, such as an instance, change nothing.
local in_world = false
-- Slots that already listen for a middle-click. A listener cannot be taken off, so it checks the settings.
local listening = setmetatable({}, { __mode = "k" })

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
local function place_flat(frame, columns)
	headers.hide_all()
	local slots = layout.order(slots_of(frame))
	local grid = layout.grid(#slots, columns)
	for index, slot in ipairs(slots) do
		local position = grid.positions[index]
		slot.button:ClearAllPoints()
		slot.button:SetPoint("BOTTOMRIGHT", frame.MoneyFrame, "TOPRIGHT", position.x, GRID_OFFSET_Y + position.y)
	end
	frame:SetSize(layout.resized(stock_width, stock_height, #slots, columns))
end

-- The section a slot belongs to: its item's type, junk ahead of it, or free
-- space when it holds nothing. A grey item is junk, and so is a marked one
-- while the marker is on.
local function section_of(slot, pinned_data)
	local info = C_Container.GetContainerItemInfo(slot.bag, slot.slot)
	if type(info) ~= "table" then return categories.FREE end
	local item_id, quality = info.itemID, info.quality
	if secret(item_id) or type(item_id) ~= "number" then return "misc" end
	local class_id = select(6, C_Item.GetItemInfoInstant(item_id))
	local grey = not secret(quality) and quality == 0
	local pinned = pinned_data ~= nil and pins.is_pinned(pinned_data, item_id)
	local arrived = module.get(id, "recent") == true and arrivals:has(item_id)
	return categories.of(class_id, grey or Everlook.bags.is_junk(item_id), pinned, arrived), item_id
end

-- Lays the slots out in sections under headers, in the order stock keeps them
-- in within each section. It reports whether it could: without the container
-- API nothing is known about the items, and the caller lays out a flat grid.
local function place_grouped(frame, columns)
	if type(C_Container) ~= "table" or type(C_Container.GetContainerItemInfo) ~= "function"
		or type(C_Item) ~= "table" or type(C_Item.GetItemInfoInstant) ~= "function" then
		return false
	end
	local slots = layout.order(slots_of(frame))
	local members = {}
	local pinned_data = module.get(id, "pins") == true and pins.data() or nil
	for index, slot in ipairs(slots) do
		slot.index = index
		local key, item_id = section_of(slot, pinned_data)
		slot.item_id = item_id
		members[key] = members[key] or {}
		members[key][#members[key] + 1] = slot
	end
	-- Recent items go newest first, and slots of one item stay in stock order.
	if members.recent then
		table.sort(members.recent, function(first, second)
			local first_rank, second_rank = arrivals:rank(first.item_id), arrivals:rank(second.item_id)
			if first_rank ~= second_rank then return first_rank < second_rank end
			return first.index < second.index
		end)
	end
	local wanted = {}
	for _, section in ipairs(categories.SECTIONS) do
		wanted[#wanted + 1] = { key = section.key, title = section.title, count = members[section.key] and #members[section.key] or 0 }
	end
	local grouped = layout.grouped(wanted, columns)
	for _, section in ipairs(grouped.sections) do
		for index, slot in ipairs(members[section.key]) do
			local position = section.positions[index]
			slot.button:ClearAllPoints()
			slot.button:SetPoint("BOTTOMRIGHT", frame.MoneyFrame, "TOPRIGHT", position.x, GRID_OFFSET_Y + position.y)
		end
	end
	headers.show(frame, frame.MoneyFrame, GRID_OFFSET_Y, grouped)
	frame:SetSize(layout.grouped_size(stock_width, stock_height, #slots, grouped))
	return true
end

local function place(frame, columns, grouped)
	if not frame.MoneyFrame or not stock_width then return end
	if grouped and place_grouped(frame, columns) then return end
	place_flat(frame, columns)
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
				text:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -5, 2)
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

local function grouping()
	return module.get(id, "group") == true
end

local function regroup(frame)
	changed = true
	place(frame, module.get(id, "columns"), true)
end

local function pointer_on_slot(frame)
	for _, button in frame:EnumerateValidItems() do
		if type(button.IsMouseOver) == "function" and button:IsMouseOver() then return true end
	end
	return false
end

-- A slot under the pointer must stay put: selling or using an item empties its slot, and a
-- regroup would slide the next item under the pointer for the click that follows. The regroup
-- waits for the pointer to leave the slots. The watcher exists only to ask that, and runs only
-- while a regroup waits.
local watcher

local function wait_for_pointer(frame)
	if not watcher then
		watcher = CreateFrame("Frame")
		watcher:SetScript("OnUpdate", function(self)
			if pointer_on_slot(frame) then return end
			self:Hide()
			if module.enabled(id) and grouping() and not marker.is_active() and frame:IsShown() then regroup(frame) end
		end)
	end
	watcher:Show()
end

-- Stock has just drawn the grid and sized the frame. Anything wanted that
-- stock does not do is done over it.
local function on_layout(frame)
	if not module.enabled(id) then return end
	remember_stock_size(frame)
	local columns, grouped = module.get(id, "columns"), grouping()
	changed = grouped or columns ~= layout.STOCK_COLUMNS
	if changed then place(frame, columns, grouped) end
end

-- Stock does not move slots when items arrive, so a grouped bag sorts them again. It waits
-- while marks are being made, and while the pointer is on a slot.
local function sort_sections(frame)
	if grouping() and not marker.is_active() then
		if pointer_on_slot(frame) then wait_for_pointer(frame) else regroup(frame) end
	end
end

-- A middle-click on a slot pins its item, or unpins it. The slot moves at once, though the
-- pointer is on it: the click asked for that.
local function pin_clicked(button, mouse_button)
	if mouse_button ~= "MiddleButton" then return end
	if not (module.enabled(id) and module.get(id, "pins") == true and grouping()) then return end
	local frame = combined_bag()
	if not frame or type(C_Container) ~= "table" or type(C_Container.GetContainerItemInfo) ~= "function" then return end
	local info = C_Container.GetContainerItemInfo(button:GetBagID(), button:GetID())
	if type(info) ~= "table" or pins.toggle(pins.data(), info.itemID) == nil then return end
	if type(frame.IsShown) == "function" and frame:IsShown() then regroup(frame) end
end

local function listen_for_pins(frame)
	for _, button in frame:EnumerateValidItems() do
		if not listening[button] and type(button.HookScript) == "function" then
			button:HookScript("OnMouseUp", pin_clicked)
			listening[button] = true
		end
	end
end

-- Stock has refreshed what the slots hold, which is when a label can change.
local function on_items(frame)
	if not module.enabled(id) then return end
	show_labels(frame, module.get(id, "item_level"))
	marker.apply(frame, module.get(id, "junk_marker"))
	if module.get(id, "pins") == true then listen_for_pins(frame) end
	sort_sections(frame)
end

-- The total of each item in the bags, which is what arrivals are told by.
local function bag_totals()
	if type(C_Container) ~= "table" or type(C_Container.GetContainerNumSlots) ~= "function"
		or type(C_Container.GetContainerItemInfo) ~= "function" then
		return nil
	end
	local totals = {}
	for bag = 0, NUM_BAG_SLOTS or 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if type(info) == "table" and not secret(info.itemID) and type(info.itemID) == "number" then
				local count = type(info.stackCount) == "number" and not secret(info.stackCount) and info.stackCount or 1
				totals[info.itemID] = (totals[info.itemID] or 0) + count
			end
		end
	end
	return totals
end

-- Looks at the bags and says whether something arrived since the last look.
local function look_at_bags()
	if not in_world or module.get(id, "recent") ~= true then return false end
	local totals = bag_totals()
	return totals ~= nil and arrivals:observe(totals)
end

local function on_event(event)
	if event == "PLAYER_ENTERING_WORLD" then
		if not in_world then
			in_world = true
			look_at_bags()
		end
		return
	end
	if not look_at_bags() then return end
	local frame = combined_bag()
	if frame and type(frame.IsShown) == "function" and frame:IsShown() then sort_sections(frame) end
end

-- Mark mode has ended, and the marks it made can move their items now.
marker.on_stop = function(frame)
	if not (module.enabled(id) and grouping()) or type(frame.IsShown) ~= "function" or not frame:IsShown() then return end
	regroup(frame)
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
	marker.apply(frame, enabled and module.get(id, "junk_marker"))
	if enabled and module.get(id, "pins") == true then listen_for_pins(frame) end
	-- Turned on in a running session, the bags can be read now.
	if enabled and not in_world and type(IsLoggedIn) == "function" and IsLoggedIn() then in_world = true end
	if enabled and module.get(id, "recent") == true then
		look_at_bags()
	else
		arrivals = recent.new()
	end
	local grouped = enabled and grouping()
	local shown = type(frame.IsShown) == "function" and frame:IsShown()
	if not shown then
		-- A closed bag is laid out from scratch by stock when it opens, and its headers must not outlast this.
		if not grouped then headers.hide_all() end
		changed = false
		return
	end
	if not changed then remember_stock_size(frame) end
	local columns = enabled and module.get(id, "columns") or layout.STOCK_COLUMNS
	local moved = grouped or columns ~= layout.STOCK_COLUMNS
	if changed or moved then
		place(frame, columns, grouped)
		changed = moved
	end
	show_labels(frame, enabled and module.get(id, "item_level"))
end

module.register({
	addon = addon_name, page = "interface", order = 90,
	id = id, name = "Bags",
	description = "Adds to the combined bag, which needs Combine all bags to be on in the game's settings. It keeps the bag's look, and its slots, search box and sort button stay the game's own. Turning this off puts the grid back as the game draws it, and a choice here does nothing until this is on.",
	options = {
		item_level = { name = "Show item level on gear", default = false, description = "Writes the item level of each weapon and piece of armor, including rings, trinkets and cloaks, at the bottom right of its slot, where a stack count would sit, in the color of its quality. Other items show nothing, and turning this off removes the numbers." },
		junk_marker = { name = "Mark items as junk", default = false, description = "Adds a coin button to the title row of the combined bag. Click it, then click items to mark or unmark them as junk, and click it again to stop. A marked item shows the junk coin, and every copy of that item is marked. Sell junk can sell marked items at a vendor when you turn that on there. Turning this off hides the button and the coins and keeps your marks." },
		group = { name = "Group items by type", default = false, description = "Sorts the slots of the combined bag into sections under headers: The Armory for weapons and armor, Adventure Prep for consumables, gems and item enhancements, Professions for trade goods, reagents and recipes, Miscellaneous for the rest, and Junk for grey items and, when Mark items as junk is on, the items you marked. Empty slots wait at the bottom as Free Space. The bag keeps its look, and its search box and sort button work as before, though sorting moves items between slots and the sections follow. Turning this off puts the grid back." },
		pins = { name = "Pinned items", default = false, description = "Middle-click an item in the combined bag to pin it, and middle-click it again to unpin it. Every copy of a pinned item sits in a Pinned section at the top of the bag, and the pin stays after you log out. It needs Group items by type to be on, and turning this off puts the items back under their types and keeps the pins." },
		recent = { name = "Recent items", default = false, description = "Items whose total in your bags goes up, whether looted, bought, taken from the mail or the bank, or taken off your character, wait in a Recent section just below Pinned, the newest first, twelve at most, until you log out or reload. Every copy of such an item is there, and junk and pinned items stay in their own sections. It needs Group items by type to be on, and turning this off puts the items back under their types and forgets the list." },
		columns = { name = "Columns", default = 10, min = 10, max = 16, step = 1, description = "How many slots sit in each row of the combined bag. Ten is how the game draws it, and more columns make the bag wider and shorter." },
	},
	events = { "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED" },
	on_event = on_event,
	apply = apply,
})

-- What another addon may ask of Bags. Only a marked item, while Bags and the
-- marker are both on, is junk. Anything else, including a bad id, is false.
Everlook.bags = {
	is_junk = function(item_id)
		if not (module.enabled(id) and module.get(id, "junk_marker") == true) then return false end
		return junk.is_marked(junk.data(), item_id)
	end,
}
