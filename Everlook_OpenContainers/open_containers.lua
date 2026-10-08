local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "open_containers"
local ticker, pending
local loot_open, taking_loot = false, false
local quiet = {}
local busy_frames = { "MerchantFrame", "BankFrame", "MailFrame", "TradeFrame", "GuildBankFrame", "AuctionHouseFrame" }

-- UseContainerItem also sells, banks and attaches an item to mail. All of
-- those contexts must be closed before use, and checked again before loot.
local function api_ready()
	return type(C_Container) == "table"
		and type(C_Container.GetContainerNumSlots) == "function"
		and type(C_Container.GetContainerItemInfo) == "function"
		and type(C_Container.UseContainerItem) == "function"
		and type(C_Item) == "table" and type(C_Item.GetItemGUID) == "function"
		and type(C_Item.DoesItemExist) == "function"
		and type(ItemLocation) == "table" and type(ItemLocation.CreateFromBagAndSlot) == "function"
		and type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function"
		and type(IsShiftKeyDown) == "function" and type(InCombatLockdown) == "function"
		and type(CursorHasItem) == "function" and type(GetCursorInfo) == "function"
		and type(SpellCanTargetItem) == "function" and type(SpellCanTargetItemID) == "function"
		and type(GetNumLootItems) == "function" and type(GetLootSlotInfo) == "function"
		and type(GetLootSourceInfo) == "function" and type(LootSlot) == "function"
		and type(LootFrame) == "table" and type(LootFrame.IsShown) == "function"
end

local function blocked()
	if not api_ready() or module.paused() or InCombatLockdown() then return true end
	if CursorHasItem() or GetCursorInfo() ~= nil or SpellCanTargetItem() or SpellCanTargetItemID() then return true end
	for index = 1, #busy_frames do
		local frame = _G[busy_frames[index]]
		if type(frame) == "table" and type(frame.IsShown) == "function" and frame:IsShown() then return true end
	end
	return false
end

local function secret(value)
	return type(issecretvalue) == "function" and issecretvalue(value)
end

local function loot_count()
	local count = GetNumLootItems()
	if secret(count) or type(count) ~= "number" then return end
	return count
end

local function item_guid(bag, slot)
	local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
	if not C_Item.DoesItemExist(location) then return end
	local guid = C_Item.GetItemGUID(location)
	if secret(guid) or type(guid) ~= "string" or guid == "" then return end
	return guid
end

local function own_slot(slot, guid)
	local sources = { GetLootSourceInfo(slot) }
	if #sources == 0 then return false end
	for index = 1, #sources, 2 do
		if secret(sources[index]) or sources[index] ~= guid then return false end
	end
	return true
end

local function take_loot(guid)
	local count = loot_count()
	if not count then return end
	taking_loot = true
	for slot = count, 1, -1 do
		if not loot_open or blocked() then break end
		local texture, _, _, _, _, locked = GetLootSlotInfo(slot)
		if not secret(texture) and not secret(locked) and texture and not locked and own_slot(slot, guid) then
			LootSlot(slot)
		end
	end
	taking_loot = false
end

local function stack_count(info)
	if secret(info.stackCount) or type(info.stackCount) ~= "number" then return end
	return info.stackCount
end

local function bag_count()
	local bags = NUM_BAG_SLOTS or 4
	if type(NUM_REAGENTBAG_SLOTS) == "number" and NUM_REAGENTBAG_SLOTS > 0 then
		bags = bags + NUM_REAGENTBAG_SLOTS
	end
	return bags
end

local function find_container()
	for bag = 0, bag_count() do
		local slots = C_Container.GetContainerNumSlots(bag)
		if secret(slots) or type(slots) ~= "number" then return end
		for slot = 1, slots do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if type(info) == "table" and not secret(info.hasLoot) and not secret(info.isLocked)
				and info.hasLoot and not info.isLocked then
				local guid = item_guid(bag, slot)
				local count = stack_count(info)
				if guid and count and quiet[guid] ~= count then return bag, slot, guid, count end
			end
		end
	end
end

local function stop()
	if ticker then ticker:Cancel(); ticker = nil end
	pending = nil
end

local function tick()
	if not module.enabled(id) or not api_ready() then stop(); return end
	if taking_loot or blocked() then return end
	-- Polling never establishes ownership of a loot window. Only LOOT_OPENED
	-- from an item, followed by a matching source GUID, permits taking loot.
	local count = loot_count()
	if not count or loot_open or count > 0 or LootFrame:IsShown() then return end
	if pending then
		if item_guid(pending.bag, pending.slot) ~= pending.guid then
			pending = nil
		else
			pending.waits = pending.waits + 1
			if pending.waits < 3 then return end
			quiet[pending.guid] = pending.count
			pending = nil
		end
	end
	local bag, slot, guid, count = find_container()
	if not bag then stop(); return end
	pending = { bag = bag, slot = slot, guid = guid, count = count, waits = 0 }
	C_Container.UseContainerItem(bag, slot)
end

local function start()
	if not module.enabled(id) or not api_ready() or taking_loot then return end
	if not ticker then ticker = C_Timer.NewTicker(0.2, tick) end
	tick()
end

module.register({
	addon = addon_name, page = "loot", order = 20,
	id = id,
	name = "Open containers",
	description = "Opens clam shells, crates, and other containers in your bags, then takes what is inside when that loot came from the container. A slot the server has locked is skipped, a locked box or a container that does not open a loot window stays in the bag, that same unchanged stack is not tried again while another stack of the same item still opens, a merchant, bank, guild bank, mail, trade, or auction window pauses it, and so do combat, Shift, and holding an item or aiming a spell at one, loot from another source stays for you, turning this off stops the scan, and nothing happens when the client cannot open bags or take the loot.",
	events = {
		"BAG_UPDATE_DELAYED", "LOOT_OPENED", "LOOT_CLOSED", "PLAYER_REGEN_ENABLED",
		"MERCHANT_CLOSED", "BANKFRAME_CLOSED", "MAIL_CLOSED", "TRADE_CLOSED",
	},
	on_event = function(event, _, from_item)
		if event == "LOOT_OPENED" then
			loot_open = true
			local opened = pending
			pending = nil
			if not opened then return end
			-- An unchanged stack is not reopened after manual loot, an inventory
			-- error or a rejected window. Another stack of the same item is distinct.
			quiet[opened.guid] = opened.count
			if not secret(from_item) and from_item == true and not blocked() then take_loot(opened.guid) end
			return
		end
		if event == "LOOT_CLOSED" then loot_open = false end
		start()
	end,
	apply = function(enabled)
		if not enabled then quiet = {}; loot_open = false; stop(); return end
		start()
	end,
})
