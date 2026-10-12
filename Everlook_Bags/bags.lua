local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local layout = Everlook.bags_layout
local item_level = Everlook.bags_item_level
local junk = Everlook.bags_junk
local categories = Everlook.bags_categories
local pins = Everlook.bags_pins
local assign = Everlook.bags_assign
local alts = Everlook.bags_alts
local recent = Everlook.bags_recent
local folds = Everlook.bags_folds
local sidebar = Everlook.bags_sidebar
local headers = Everlook.bags_headers
local marker = Everlook.bags_marker
local id = "bags"

-- Stock anchors the grid's bottom right corner 4 pixels above the money frame.
local GRID_OFFSET_Y = 4
-- Stock draws a stack count in this font, 5 pixels in from the bottom right. Gear never
-- stacks, so the item level takes the same place and cannot collide with a count.
local LABEL_FONT = "NumberFontNormal"

-- The names a custom section can be given. There is no way to type one, so each section takes
-- one of these, and "off" leaves the section unused.
local CUSTOM_NAMES = {
	{ "off", "Off" }, { "keep", "Keep" }, { "sell", "Sell" }, { "mail", "Mail" }, { "bank", "Bank" },
	{ "crafting", "Crafting" }, { "swaps", "Gear Swaps" }, { "quests", "Quests" }, { "food", "Food and Drink" }, { "potions", "Potions" },
}
local CUSTOM_COUNT = 3

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
-- Whether the bank is open, which is the only time its contents can be read.
local bank_open = false
local tooltip_hooked = false
-- The item each tooltip last showed other characters' items for, so a refresh does not add them twice.
local told = setmetatable({}, { __mode = "k" })
local clear_hooked = setmetatable({}, { __mode = "k" })
local MOST_CHARACTERS_NAMED = 5
-- A slot that is folded away keeps its place at the grid's corner, clear and deaf to the mouse. What it
-- was before is kept, so it can be put back exactly.
local parked = setmetatable({}, { __mode = "k" })
-- The section the list has been asked to show alone. It lasts the session, and only while the list is on.
local solo
-- Slots that already listen for a middle-click. A listener cannot be taken off, so it checks the settings.
local listening = setmetatable({}, { __mode = "k" })

local function secret(value)
	return issecretvalue and issecretvalue(value)
end

-- The scale the game gave the bag on its last anchoring pass, and whether this module has
-- changed it since. A share of the game's scale is taken from the first, never from the second.
local stock_scale
local scaled = false

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
local function unpark_all()
	for button, was in pairs(parked) do
		button:SetAlpha(was.alpha)
		button:EnableMouse(true)
		parked[button] = nil
	end
end

local function park(button, frame)
	if not parked[button] then parked[button] = { alpha = button:GetAlpha() } end
	button:SetAlpha(0)
	button:EnableMouse(false)
	button:ClearAllPoints()
	button:SetPoint("BOTTOMRIGHT", frame.MoneyFrame, "TOPRIGHT", 0, GRID_OFFSET_Y)
end

local function place_flat(frame, columns)
	headers.hide_all()
	sidebar.hide()
	unpark_all()
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
-- The custom sections the player has named, by number, and the numbers in order.
local function custom_in_use()
	local labels, numbers = {}, {}
	for number = 1, CUSTOM_COUNT do
		local chosen = module.get(id, "custom" .. number)
		for _, name in ipairs(CUSTOM_NAMES) do
			if name[1] == chosen and chosen ~= "off" then
				labels[number] = name[2]
				numbers[#numbers + 1] = number
			end
		end
	end
	return labels, numbers
end

local function section_of(slot, pinned_data, assigned_data, labels)
	local info = C_Container.GetContainerItemInfo(slot.bag, slot.slot)
	if type(info) ~= "table" then return categories.FREE end
	local item_id, quality = info.itemID, info.quality
	if secret(item_id) or type(item_id) ~= "number" then return "misc" end
	local class_id = select(6, C_Item.GetItemInfoInstant(item_id))
	local grey = not secret(quality) and quality == 0
	local pinned = pinned_data ~= nil and pins.is_pinned(pinned_data, item_id)
	local arrived = module.get(id, "recent") == true and arrivals:has(item_id)
	local number = assigned_data and assign.of(assigned_data, item_id)
	local custom = number and labels[number] and "custom" .. number or nil
	return categories.of(class_id, grey or Everlook.bags.is_junk(item_id), pinned, arrived, custom), item_id
end

-- The expansion an item belongs to, which only the full item lookup knows, or nil.
local function expansion_of(item_id)
	if type(C_Item.GetItemInfo) ~= "function" then return nil end
	return (select(15, C_Item.GetItemInfo(item_id)))
end

-- Lays the slots out in sections under headers, in the order stock keeps them
-- in within each section. It reports whether it could: without the container
-- API nothing is known about the items, and the caller lays out a flat grid.
-- Clicks on a section's header and on a row of the list, set once regroup exists.
local on_fold, on_solo

local function place_grouped(frame, columns)
	if type(C_Container) ~= "table" or type(C_Container.GetContainerItemInfo) ~= "function"
		or type(C_Item) ~= "table" or type(C_Item.GetItemInfoInstant) ~= "function" then
		return false
	end
	local slots = layout.order(slots_of(frame))
	local members = {}
	local pinned_data = module.get(id, "pins") == true and pins.data() or nil
	local fold_on = module.get(id, "fold") == true
	local fold_data = fold_on and folds.data() or nil
	local nesting = module.get(id, "expansions") == true
	local labels, numbers = custom_in_use()
	local assigned_data = #numbers > 0 and assign.data() or nil
	for index, slot in ipairs(slots) do
		slot.index = index
		local base, item_id = section_of(slot, pinned_data, assigned_data, labels)
		local key = base
		slot.item_id, slot.base = item_id, base
		if nesting and item_id then
			local expansion = expansion_of(item_id)
			key = categories.sub_key(base, expansion)
			if key ~= base then slot.expansion = expansion end
		end
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
	local list_on = module.get(id, "sidebar") == true
	-- A section that has emptied out cannot be shown alone, so everything is shown again.
	if solo and not (members[solo] and #members[solo] > 0) then solo = nil end
	local shown_alone = list_on and solo or nil
	-- Each kind of section, and under it the expansions its items come from, newest first.
	local wanted = {}
	for _, section in ipairs(categories.SECTIONS) do
		local keys = {}
		for key, list in pairs(members) do
			if list[1].base == section.key then keys[#keys + 1] = key end
		end
		table.sort(keys, function(first, second)
			return categories.newer_first(members[first][1].expansion, members[second][1].expansion)
		end)
		for _, key in ipairs(keys) do
			local state = fold_on and folds.is_folded(fold_data, key) and "collapsed" or nil
			if shown_alone then state = key ~= shown_alone and "hidden" or nil end
			local title = categories.sub_title(section.key, section.title, members[key][1].expansion)
			local number = tonumber(key:match("^custom(%d)$"))
			if number and labels[number] then title = labels[number] end
			wanted[#wanted + 1] = { key = key, title = title, count = #members[key], state = state }
		end
	end
	local grouped = layout.grouped(wanted, columns)
	unpark_all()
	local placed = {}
	for _, section in ipairs(grouped.sections) do
		placed[section.key] = true
		for index, slot in ipairs(members[section.key]) do
			local position = section.positions[index]
			if position then
				slot.button:ClearAllPoints()
				slot.button:SetPoint("BOTTOMRIGHT", frame.MoneyFrame, "TOPRIGHT", position.x, GRID_OFFSET_Y + position.y)
			else
				park(slot.button, frame)
			end
		end
	end
	for key, parked_slots in pairs(members) do
		if not placed[key] then
			for _, slot in ipairs(parked_slots) do park(slot.button, frame) end
		end
	end
	headers.show(frame, frame.MoneyFrame, GRID_OFFSET_Y, grouped, fold_on and on_fold or nil)
	local list_rows
	if list_on then
		local entries, items = {}, 0
		for _, section in ipairs(wanted) do
			entries[#entries + 1] = { key = section.key, title = section.title, count = section.count }
			if section.key ~= categories.FREE then items = items + section.count end
		end
		table.insert(entries, 1, { key = sidebar.ALL, title = "All Items", count = items })
		sidebar.show(frame, frame.MoneyFrame, GRID_OFFSET_Y, grouped.width, entries, shown_alone or sidebar.ALL, on_solo)
		list_rows = #entries
	else
		sidebar.hide()
	end
	frame:SetSize(layout.grouped_size(stock_width, stock_height, #slots, grouped, list_rows))
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

on_fold = function(key)
	if not (module.enabled(id) and module.get(id, "fold") == true and grouping()) then return end
	local frame = combined_bag()
	if not frame or folds.toggle(folds.data(), key) == nil then return end
	if type(frame.IsShown) == "function" and frame:IsShown() then regroup(frame) end
end

on_solo = function(key)
	if not (module.enabled(id) and module.get(id, "sidebar") == true and grouping()) then return end
	local frame = combined_bag()
	if not frame then return end
	if key == sidebar.ALL or key == solo then solo = nil else solo = key end
	if type(frame.IsShown) == "function" and frame:IsShown() then regroup(frame) end
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

-- A middle-click on a slot pins its item, or unpins it, and with Ctrl moves it to the next custom
-- section in use. The slot moves at once, though the pointer is on it: the click asked for that.
local function slot_clicked(button, mouse_button)
	if mouse_button ~= "MiddleButton" then return end
	if not (module.enabled(id) and grouping()) then return end
	local frame = combined_bag()
	if not frame or type(C_Container) ~= "table" or type(C_Container.GetContainerItemInfo) ~= "function" then return end
	local info = C_Container.GetContainerItemInfo(button:GetBagID(), button:GetID())
	if type(info) ~= "table" then return end
	local with_ctrl = type(IsControlKeyDown) == "function" and IsControlKeyDown() == true
	if with_ctrl then
		local _, numbers = custom_in_use()
		if #numbers == 0 or not junk.valid(info.itemID) then return end
		assign.cycle(assign.data(), info.itemID, numbers)
	elseif module.get(id, "pins") == true then
		if pins.toggle(pins.data(), info.itemID) == nil then return end
	else
		return
	end
	if type(frame.IsShown) == "function" and frame:IsShown() then regroup(frame) end
end

local function wants_clicks()
	if module.get(id, "pins") == true then return true end
	local _, numbers = custom_in_use()
	return #numbers > 0
end

local function listen_for_clicks(frame)
	for _, button in frame:EnumerateValidItems() do
		if not listening[button] and type(button.HookScript) == "function" then
			button:HookScript("OnMouseUp", slot_clicked)
			listening[button] = true
		end
	end
end

-- Stock has refreshed what the slots hold, which is when a label can change.
local function on_items(frame)
	if not module.enabled(id) then return end
	show_labels(frame, module.get(id, "item_level"))
	marker.apply(frame, module.get(id, "junk_marker"))
	if wants_clicks() then listen_for_clicks(frame) end
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

local function current_key()
	if type(UnitName) ~= "function" or type(GetRealmName) ~= "function" then return nil end
	return alts.key(UnitName("player"), GetRealmName())
end

-- Writes down what this character has in its bags and, while the bank is open, in its bank
-- and the warband bank. A closed bank is left as it was last written.
local function remember_items()
	if not in_world or module.get(id, "remember") ~= true then return end
	local key = current_key()
	local scanned = key and alts.scan(alts.BAGS)
	if not scanned then return end
	local root = alts.data()
	local entry = root.characters[key] or {}
	root.characters[key] = entry
	entry.name, entry.realm = UnitName("player"), GetRealmName()
	entry.class = type(UnitClass) == "function" and select(2, UnitClass("player")) or entry.class
	entry.time = type(GetServerTime) == "function" and GetServerTime() or entry.time
	entry.bags = scanned
	if bank_open then
		local bank, warband = alts.scan(alts.CHARACTER_BANK), alts.scan(alts.WARBAND_BANK)
		if bank then entry.bank = bank end
		if warband then root.warband = { time = entry.time, bank = warband } end
	end
end

local function say_where_else(tooltip, data)
	if not (module.enabled(id) and module.get(id, "remember") == true) then return end
	local item_id = data and data.id
	if not junk.valid(item_id) or told[tooltip] == item_id then return end
	local others, warband = alts.others(alts.data(), current_key(), item_id)
	if #others == 0 and warband == 0 then return end
	told[tooltip] = item_id
	if type(tooltip.HasScript) == "function" and tooltip:HasScript("OnTooltipCleared") and not clear_hooked[tooltip] then
		clear_hooked[tooltip] = true
		tooltip:HookScript("OnTooltipCleared", function(self) told[self] = nil end)
	end
	local function line(left, right)
		if type(tooltip.AddDoubleLine) == "function" then
			tooltip:AddDoubleLine(left, right, 1, 1, 1, 0.7, 0.7, 0.7)
		else
			tooltip:AddLine(left .. ": " .. right)
		end
	end
	for index, other in ipairs(others) do
		if index > MOST_CHARACTERS_NAMED then
			tooltip:AddLine("and " .. (#others - MOST_CHARACTERS_NAMED) .. " more")
			break
		end
		local parts = {}
		if other.bags > 0 then parts[#parts + 1] = other.bags .. " in bags" end
		if other.bank > 0 then parts[#parts + 1] = other.bank .. " in bank" end
		line(other.name, table.concat(parts, ", "))
	end
	if warband > 0 then line("Warband bank", tostring(warband)) end
end

local function hook_tooltips()
	if tooltip_hooked or type(TooltipDataProcessor) ~= "table" or type(TooltipDataProcessor.AddTooltipPostCall) ~= "function"
		or type(Enum) ~= "table" or type(Enum.TooltipDataType) ~= "table" then
		return
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, say_where_else)
	tooltip_hooked = true
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
			remember_items()
		end
		return
	elseif event == "BANKFRAME_OPENED" then
		bank_open = true
		remember_items()
		return
	elseif event == "BANKFRAME_CLOSED" then
		bank_open = false
		return
	end
	remember_items()
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
local function scale_share()
	return module.get(id, "scale") / 100
end

-- Puts the bag at a share of the game's scale, or back at the game's own.
local function set_scale(frame, share)
	if not scaled then stock_scale = frame:GetScale() end
	if type(stock_scale) ~= "number" then return end
	if share == 1 and not scaled then return end
	frame:SetScale(stock_scale * share)
	scaled = share ~= 1
end

-- The game has just set the bag's scale and anchors, and scale is part of both.
local function on_anchors()
	local frame = combined_bag()
	if not frame or type(frame.GetScale) ~= "function" or type(frame.SetScale) ~= "function" then return end
	scaled = false
	if not module.enabled(id) then return end
	set_scale(frame, scale_share())
end

local function install(frame)
	if hooked or type(hooksecurefunc) ~= "function" then return end
	if type(frame.UpdateItemLayout) ~= "function" or type(frame.UpdateItems) ~= "function" then return end
	hooksecurefunc(frame, "UpdateItemLayout", on_layout)
	hooksecurefunc(frame, "UpdateItems", on_items)
	if type(_G.UpdateContainerFrameAnchors) == "function" then hooksecurefunc("UpdateContainerFrameAnchors", on_anchors) end
	hooked = true
end

local function apply(enabled)
	-- Turned on in a running session, the bags can be read now.
	if enabled and not in_world and type(IsLoggedIn) == "function" and IsLoggedIn() then in_world = true end
	if enabled then hook_tooltips() end
	if enabled then remember_items() end
	local frame = combined_bag()
	if not frame then return end
	if enabled then install(frame) end
	marker.apply(frame, enabled and module.get(id, "junk_marker"))
	if enabled and wants_clicks() then listen_for_clicks(frame) end
	if not (enabled and module.get(id, "sidebar") == true) then solo = nil end
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
	if type(frame.GetScale) == "function" and type(frame.SetScale) == "function" then
		set_scale(frame, enabled and scale_share() or 1)
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
		remember = { name = "Remember items on all characters", default = false, description = "Writes down what each character has in its bags and bank, and the warband bank, whenever you log in with this on, change your bags or open the bank, so an item's tooltip can say where else you have it, such as Mage: 7 in bags, 3 in bank, and how many sit in the warband bank. It names the five characters with most and counts the rest. Only item ids and counts are kept, in your saved settings. The bank is written down only while it is open, and turning this off stops writing and keeps what was kept." },
		scale = { name = "Window scale", default = 100, min = 70, max = 110, step = 5, description = "Makes the combined bag a share of the size the game gives it, in percent. The game still shrinks a bag that does not fit the screen, and this goes on top of that. A hundred is how the game draws it." },
		expansions = { name = "Nest by expansion", default = false, description = "Splits the Armory, Adventure Prep, Professions and Miscellaneous sections by the expansion their items belong to, the newest first, each with its own header. An item the game cannot place in an expansion stays under the section's own header, after the others. It needs Group items by type to be on, and turning this off makes each of them one section again." },
		sidebar = { name = "Section list", default = false, description = "Adds a list of the sections to the left of the grouped bag, a row for everything and one for each section with its name and how many slots it holds. Click a row to show only that section, and click it again, or the row for everything, to show them all. The counts do not change with the search box. It needs Group items by type to be on, and turning this off shows every section again." },
		fold = { name = "Fold sections", default = false, description = "Click the header of a section in the grouped bag to fold it down to its header, which keeps its count and shows an arrow, and click again to open it. Which sections are folded is saved. It needs Group items by type to be on, and turning this off opens every section and keeps the folds." },
		custom1 = { name = "Custom section 1", default = "off", choices = CUSTOM_NAMES, description = "Gives the grouped bag a section of your own, named from this list. Hold Ctrl and middle-click an item to put it in the next of your custom sections that is in use, and again to move it on, and out of them all after the last. Every copy of the item goes with it, and it stays in the section after you log out. The section sits under Recent and over the types, and an item pinned stays pinned. It needs Group items by type to be on, and Off leaves the section unused and its items under their types." },
		custom2 = { name = "Custom section 2", default = "off", choices = CUSTOM_NAMES, description = "A second section of your own. See Custom section 1." },
		custom3 = { name = "Custom section 3", default = "off", choices = CUSTOM_NAMES, description = "A third section of your own. See Custom section 1." },
		pins = { name = "Pinned items", default = false, description = "Middle-click an item in the combined bag to pin it, and middle-click it again to unpin it. Every copy of a pinned item sits in a Pinned section at the top of the bag, and the pin stays after you log out. It needs Group items by type to be on, and turning this off puts the items back under their types and keeps the pins." },
		recent = { name = "Recent items", default = false, description = "Items whose total in your bags goes up, whether looted, bought, taken from the mail or the bank, or taken off your character, wait in a Recent section just below Pinned, the newest first, twelve at most, until you log out or reload. Every copy of such an item is there, and junk and pinned items stay in their own sections. It needs Group items by type to be on, and turning this off puts the items back under their types and forgets the list." },
		columns = { name = "Columns", default = 10, min = 10, max = 16, step = 1, description = "How many slots sit in each row of the combined bag. Ten is how the game draws it, and more columns make the bag wider and shorter." },
	},
	events = { "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED" },
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
