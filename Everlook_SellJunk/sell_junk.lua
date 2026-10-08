local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "sell_junk"
local ticker, queue, pending, merchant_open
local total = 0
local next_result = 0

local function item_price(item_id)
	if not C_Item or not C_Item.GetItemInfo then return end
	return select(11, C_Item.GetItemInfo(item_id))
end

-- GetItemSpell also matches use effects, so a recipe is the Recipe item class
-- or a stored teachesSpellId. The stored row decides when it has a name, a
-- reagent flag, and a class. Otherwise GetItemInfo does, and an item neither
-- one can classify stays in the bag.
local function recipe_class()
	local item_class = Enum and Enum.ItemClass
	if type(item_class) == "table" and type(item_class.Recipe) == "number" then
		return item_class.Recipe
	end
	return 9
end

local function stored_item(item_id)
	local world = Everlook.world
	if not world or type(world.row) ~= "function" then return end
	local row = world.row("items", item_id)
	if type(row) == "table" then return row end
end

local function flag(value)
	if value == true or value == false then return value end
end

local function sellable(info)
	local item_id = info.itemID
	local row = stored_item(item_id)
	local quest_id = info.questID
	if type(quest_id) == "number" and quest_id > 0 and quest_id == math.floor(quest_id) and info.isActive == false then
		return false
	end
	quest_id = row and row.startsQuestId
	if type(quest_id) == "number" and quest_id > 0 and quest_id == math.floor(quest_id) then return false end
	local spell_id = row and row.teachesSpellId
	if type(spell_id) == "number" and spell_id > 0 and spell_id == math.floor(spell_id) then return false end
	local row_reagent = flag(row and row.isCraftingReagent)
	if row_reagent == true then return false end
	local row_class = row and row.classId
	if type(row_class) == "number" and row_class == recipe_class() then return false end
	local filled = type(row) == "table" and type(row.name) == "string" and row.name ~= ""
		and row_reagent ~= nil and type(row_class) == "number"
	if filled then return true end
	if not C_Item or type(C_Item.GetItemInfo) ~= "function" then return false end
	local name, _, _, _, _, _, _, _, _, _, _, class_id, _, _, _, _, live_reagent = C_Item.GetItemInfo(item_id)
	if type(name) ~= "string" or name == "" then return false end
	if row_reagent == nil and flag(live_reagent) ~= false then return false end
	if type(row_class) ~= "number" and (type(class_id) ~= "number" or class_id == recipe_class()) then
		return false
	end
	return true
end

local function confirm_sale()
	if not pending then return end
	local info = C_Container.GetContainerItemInfo(pending.bag, pending.slot)
	local remaining = info and info.itemID == pending.item_id and info.stackCount or 0
	if remaining < pending.count then
		total = total + pending.price * (pending.count - remaining)
		pending = nil
	else
		pending.waits = pending.waits + 1
		if pending.waits >= 20 then pending = nil end
	end
end

local function report_island(proceeds)
	if not Everlook.island or type(Everlook.island.notify) ~= "function" or not module.enabled("smart_island")
		or not module.enabled(id) or not module.get("smart_island", "source_sell") then return end
	next_result = next_result + 1
	local ok, result = pcall(Everlook.island.notify, {
		source = "everlook.sell_junk", key = "sale:" .. next_result, kind = "money", stack = "sale", severity = "success",
		text = "Junk sold", money = proceeds,
	})
	if not ok and geterrorhandler then geterrorhandler()(type(result) == "string" and result or "Everlook junk notice failed") end
end

local function stop()
	if ticker then ticker:Cancel(); ticker = nil end
	if not (issecretvalue and issecretvalue(total)) and type(total) == "number" and total > 0 then
		if Everlook.say then Everlook.say("Sold junk for " .. (GetCoinTextureString and GetCoinTextureString(total) or tostring(total) .. " copper") .. ".") end
		report_island(total)
	end
	queue, pending, total = nil, nil, 0
end

local function tick()
	if not merchant_open or not module.enabled(id) or module.paused() then stop(); return end
	confirm_sale()
	if pending then return end
	while queue and #queue > 0 do
		local slot = table.remove(queue, 1)
		local info = C_Container.GetContainerItemInfo(slot.bag, slot.slot)
		if info and info.itemID == slot.item_id and info.quality == 0 and not info.isLocked
			and not info.hasNoValue and sellable(info) then
			local price = item_price(info.itemID)
			if type(price) == "number" and price > 0 then
				pending = { bag = slot.bag, slot = slot.slot, item_id = info.itemID, count = info.stackCount, price = price, waits = 0 }
				C_Container.UseContainerItem(slot.bag, slot.slot)
				return
			end
		end
	end
	stop()
end

local function start()
	stop()
	if module.paused() or not C_Container or not C_Timer or not C_Timer.NewTicker then return end
	queue = {}
	for bag = 0, NUM_BAG_SLOTS or 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.quality == 0 and not info.hasNoValue then
				queue[#queue + 1] = { bag = bag, slot = slot, item_id = info.itemID }
			end
		end
	end
	if #queue > 0 then ticker = C_Timer.NewTicker(0.15, tick) end
end

module.register({
	addon = addon_name, page = "vendors", order = 10,
	id = id, name = "Sell junk",
	description = "Sells grey items when a vendor opens, and says what that junk brought in once selling stops. A quest starter, a recipe, a crafting reagent, a locked item, or a grey it cannot classify stays in the bag, an item with no sell price stays too, nothing sold or a total the client hides stays quiet, turning this on while the vendor is already open waits for the next one, closing the vendor, holding Shift, or turning this off stops the rest of that visit, and nothing happens when the client cannot sell from the bags.",
	events = { "MERCHANT_SHOW", "MERCHANT_CLOSED" },
	on_event = function(event)
		merchant_open = event == "MERCHANT_SHOW"
		if merchant_open then start() else confirm_sale(); stop() end
	end,
	apply = function(enabled) if not enabled then stop() end end,
})
