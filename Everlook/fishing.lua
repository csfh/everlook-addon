local _, Everlook = ...

Everlook.fishing = {}

local function public(value)
	if Everlook.world.usable(value) then
		return value
	end
end

-- One scratch row. A later catch of the same item on the same map only adds the counters.
local catch_row = { casts = 1, drops = 1 }

function Everlook.fishing.scan()
	if not GetNumLootItems then
		return
	end
	local location = Everlook.location.player(true)
	if not location then
		return
	end
	local seen = {}
	for slot = 1, GetNumLootItems() do
		local link = GetLootSlotLink and GetLootSlotLink(slot)
		local itemId = Everlook.items.id_from_link(link)
		if itemId and not seen[itemId] then
			seen[itemId] = true
			local quantity = 1
			local name
			if GetLootSlotInfo then
				local _, lootName, lootQuantity = GetLootSlotInfo(slot)
				name = public(lootName)
				quantity = public(lootQuantity) or 1
			end
			catch_row.mapId = location.mapId
			catch_row.areaId = location.mapId
			catch_row.itemId = itemId
			catch_row.quantity = quantity
			catch_row.areaName = location.subzone or location.zone
			Everlook.world.count("fishingLoot", catch_row)
			Everlook.items.record(itemId, "fishing", name)
		end
	end
end
