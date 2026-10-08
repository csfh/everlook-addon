local _, Everlook = ...

Everlook.vendors = {}

local function public(value)
	if Everlook.world.usable(value) then
		return value
	end
end

-- One scratch row for the whole list. Callers read it before the next slot.
local info_row = {}

local function merchant_info(index)
	if not GetMerchantItemInfo then
		return nil
	end
	local name, _, price, quantity, numAvailable, _, _, extendedCost = GetMerchantItemInfo(index)
	name = public(name)
	price = public(price)
	if name == nil and price == nil then
		return nil
	end
	info_row.name = name
	info_row.price = price
	info_row.quantity = public(quantity)
	info_row.stock = public(numAvailable)
	info_row.extendedCost = extendedCost == true or extendedCost == 1
	return info_row
end

local function item_id(index)
	if GetMerchantItemID then
		local id = public(GetMerchantItemID(index))
		if type(id) == "number" then
			return id
		end
	end
	return Everlook.items.id_from_link(GetMerchantItemLink and GetMerchantItemLink(index))
end

-- Buying one item should not store every other offer again.
local offers = {}
local costs = {}

local function offer_changed(npcId, itemId, info)
	local by_item = offers[npcId]
	if not by_item then
		by_item = {}
		offers[npcId] = by_item
	end
	local price = info.price or false
	local quantity = info.quantity or false
	local stock = info.stock or false
	local extended = info.extendedCost and true or false
	local prev = by_item[itemId]
	if prev and prev[1] == price and prev[2] == quantity and prev[3] == stock and prev[4] == extended then
		return false
	end
	if not prev then
		prev = {}
		by_item[itemId] = prev
	end
	prev[1] = price
	prev[2] = quantity
	prev[3] = stock
	prev[4] = extended
	return true
end

local function cost_changed(npcId, itemId, position, amount, costItemId, currencyId)
	local by_item = costs[npcId]
	if not by_item then
		by_item = {}
		costs[npcId] = by_item
	end
	local by_position = by_item[itemId]
	if not by_position then
		by_position = {}
		by_item[itemId] = by_position
	end
	costItemId = costItemId or false
	currencyId = currencyId or false
	local prev = by_position[position]
	if prev and prev[1] == amount and prev[2] == costItemId and prev[3] == currencyId then
		return false
	end
	if not prev then
		prev = {}
		by_position[position] = prev
	end
	prev[1] = amount
	prev[2] = costItemId
	prev[3] = currencyId
	return true
end

local function store_costs(npcId, itemId, index)
	if not GetMerchantItemCostInfo or not GetMerchantItemCostItem then
		return
	end
	local count = public(GetMerchantItemCostInfo(index)) or 0
	if count == 0 then
		return
	end
	local ready = true
	local seen = 0
	for position = 1, count do
		local _, amount, link, currencyId = GetMerchantItemCostItem(index, position)
		amount = public(amount)
		currencyId = public(currencyId)
		if amount then
			seen = seen + 1
			local costItemId = Everlook.items.id_from_link(link)
			if not costItemId and type(currencyId) ~= "number" then
				ready = false
			end
			if cost_changed(npcId, itemId, position, amount, costItemId, currencyId) then
				Everlook.world.store("merchantCosts", {
					npcId = npcId,
					itemId = itemId,
					position = position,
					amount = amount,
					costItemId = costItemId,
					currencyId = currencyId,
				})
				if type(currencyId) == "number" then
					local name = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(currencyId)
					Everlook.world.store("currencies", {
						id = currencyId,
						name = type(name) == "table" and public(name.name) or nil,
						icon = type(name) == "table" and public(name.iconFileID) or nil,
					})
				end
				if costItemId then
					Everlook.items.record(costItemId, "merchant")
				end
			end
		else
			ready = false
		end
	end
	if ready and seen == count then
		costs[npcId][itemId].ready = true
	end
end

function Everlook.vendors.scan()
	local npcId = Everlook.npcs.creature_id(UnitGUID and UnitGUID("npc"))
	if not npcId or not GetMerchantNumItems then
		return
	end
	Everlook.npcs.record("npc", "merchant")
	local count = public(GetMerchantNumItems())
	if type(count) ~= "number" then
		return
	end
	for index = 1, count do
		local id = item_id(index)
		local info = merchant_info(index)
		if id and info then
			if offer_changed(npcId, id, info) then
				Everlook.world.store("vendors", {
					npcId = npcId,
					itemId = id,
					price = info.price,
					quantity = info.quantity,
					stock = info.stock,
					extendedCost = info.extendedCost,
				})
				if type(info.price) == "number" and info.price > 0 then
					Everlook.world.store("items", { id = id, buyPrice = info.price })
				end
			end
			-- A gold price has no currency list. A list already stored does not
			-- change when the stock does, so buying does not read it again.
			local known_cost = costs[npcId] and costs[npcId][id]
			if info.extendedCost and not (known_cost and known_cost.ready) then
				store_costs(npcId, id, index)
			end
			Everlook.items.record(id, "merchant", info.name)
		end
	end
end

-- Opening a merchant fires show and update together. One scan next tick
-- reads the settled list once. Without a timer each event scans immediately.
local scan_waiting = false

local function queue_scan()
	if scan_waiting then
		return
	end
	if not C_Timer or type(C_Timer.After) ~= "function" then
		Everlook.vendors.scan()
		return
	end
	scan_waiting = true
	C_Timer.After(0, function()
		scan_waiting = false
		Everlook.vendors.scan()
	end)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("MERCHANT_SHOW")
frame:RegisterEvent("MERCHANT_UPDATE")
frame:SetScript("OnEvent", function()
	queue_scan()
end)
