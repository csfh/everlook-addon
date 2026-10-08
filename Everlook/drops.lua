local _, Everlook = ...

Everlook.drops = {}

-- COMBAT_LOG_EVENT_UNFILTERED cannot be registered by addons on this client.
-- Opening a creature's loot window is the kill and the drop we can still see.

local function public(value)
	if Everlook.world.usable(value) then
		return value
	end
end

local function loot_is_item(slot)
	if GetLootSlotType then
		local slotType = GetLootSlotType(slot)
		local itemType = Enum and Enum.LootSlotType and Enum.LootSlotType.Item or 1
		return slotType == itemType
	end
	return Everlook.items.id_from_link(GetLootSlotLink and GetLootSlotLink(slot)) ~= nil
end

local function source_ids(slot)
	local npcId, objectId, guid
	if GetLootSourceInfo then
		local sources = { GetLootSourceInfo(slot) }
		guid = sources[1]
		for i = 1, #sources, 2 do
			local source = sources[i]
			local creature = Everlook.npcs.creature_id(source)
			if creature then
				if not npcId then
					npcId = creature
				end
			elseif not objectId then
				objectId = Everlook.world.guid_id(source, "GameObject")
			end
		end
	end
	if not npcId and not objectId then
		local npc = UnitGUID and UnitGUID("npc")
		npcId = Everlook.npcs.creature_id(npc)
			or Everlook.npcs.creature_id(UnitGUID and UnitGUID("target"))
		if not npcId then
			objectId = Everlook.world.guid_id(npc, "GameObject")
		end
	end
	return npcId, objectId, guid
end

-- One scratch row per kind. A later slot only changes the ids and counters.
local drop_row = { drops = 1 }
local kill_row = { kills = 1, loots = 1, pickpockets = 0, skins = 0 }
local object_row = { drops = 1 }

local function slot_loot(slot)
	local link = GetLootSlotLink and GetLootSlotLink(slot)
	local itemId = Everlook.items.id_from_link(link)
	if not itemId then
		return nil
	end
	local name
	local quantity = 1
	if GetLootSlotInfo then
		local _, lootName, lootQuantity = GetLootSlotInfo(slot)
		name = public(lootName)
		quantity = public(lootQuantity) or 1
	end
	return itemId, name, quantity
end

function Everlook.drops.scan()
	if IsFishingLoot and IsFishingLoot() then
		if Everlook.fishing and Everlook.fishing.scan then
			Everlook.fishing.scan()
		end
		return
	end
	if not GetNumLootItems then
		return
	end
	local killed = {}
	local opened = {}
	for slot = 1, GetNumLootItems() do
		if loot_is_item(slot) then
			local itemId, name, quantity = slot_loot(slot)
			local npcId, objectId, guid = source_ids(slot)
			if itemId and objectId then
				local key = objectId .. ":" .. itemId
				object_row.objectId = objectId
				object_row.itemId = itemId
				object_row.opens = opened[key] and 0 or 1
				object_row.quantity = quantity
				Everlook.world.count("objectLoot", object_row)
				opened[key] = true
				Everlook.objects.record(guid or (UnitGUID and UnitGUID("npc")), "loot")
				Everlook.items.record(itemId, "loot", name)
			elseif itemId and npcId then
				drop_row.npcId = npcId
				drop_row.itemId = itemId
				drop_row.quantity = quantity
				Everlook.world.count("drops", drop_row)
				Everlook.items.record(itemId, "loot", name)
				if not killed[npcId] then
					killed[npcId] = true
					kill_row.npcId = npcId
					kill_row.kills = 1
					kill_row.loots = 1
					-- The loot window does not say whether it was opened by skinning or
					-- pickpocketing. GetLootMethod is the party loot rule, so both
					-- counters stay at zero.
					kill_row.pickpockets = 0
					kill_row.skins = 0
					Everlook.world.count("kills", kill_row)
					Everlook.npcs.record("npc", "loot")
					Everlook.npcs.record("target", "loot")
				end
			end
		end
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("LOOT_OPENED")
frame:SetScript("OnEvent", function()
	Everlook.drops.scan()
end)
