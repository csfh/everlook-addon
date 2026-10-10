local _, Everlook = ...

Everlook.drops = {}

-- COMBAT_LOG_EVENT_UNFILTERED cannot be registered by addons on this client.
-- Opening a creature's loot window is the kill and the drop we can still see.

local function public(value)
	if Everlook.world.usable(value) then
		return value
	end
end

-- Spells whose result opens a loot window that no creature dropped. The loot
-- source on those windows is an item, and may be unreadable, so the cast
-- itself is the signal that keeps the target from being credited.
local NON_CREATURE_LOOT = {
	[1804] = true, -- Pick Lock
	[13262] = true, -- Disenchant
	[31252] = true, -- Prospecting
	[51005] = true, -- Milling
}
local CAST_WINDOW = 10
local RESULT_WINDOW = 3

local item_loot_until = 0

local function clock()
	return type(GetTime) == "function" and public(GetTime()) or nil
end

-- A cast that starts holds the window open for its channel, one that lands
-- shortens it to the moment its loot appears, and one that fails closes it.
function Everlook.drops.note_cast(spellId, phase)
	local now = clock()
	if not (now and NON_CREATURE_LOOT[spellId]) then
		return
	end
	if phase == "failed" then
		item_loot_until = 0
	else
		item_loot_until = now + (phase == "landed" and RESULT_WINDOW or CAST_WINDOW)
	end
end

local function item_loot_open()
	local now = clock()
	if now and now <= item_loot_until then
		item_loot_until = 0
		return true
	end
	return false
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
	local foreign = false
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
			else
				local object = not objectId and Everlook.world.guid_id(source, "GameObject")
				if object then
					objectId = object
				elseif Everlook.world.usable(source) and type(source) == "string" then
					-- An Item or Player source: disenchanting, prospecting, milling,
					-- or opening a container. No creature dropped it.
					foreign = true
				end
			end
		end
	end
	if not npcId and not objectId and not foreign then
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
	if item_loot_open() then
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
frame:RegisterEvent("UNIT_SPELLCAST_SENT")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
frame:RegisterEvent("UNIT_SPELLCAST_FAILED")
local CAST_PHASES = {
	UNIT_SPELLCAST_SENT = "sent",
	UNIT_SPELLCAST_SUCCEEDED = "landed",
	UNIT_SPELLCAST_INTERRUPTED = "failed",
	UNIT_SPELLCAST_FAILED = "failed",
}
frame:SetScript("OnEvent", function(_, event, unit, second, third, fourth)
	if event == "LOOT_OPENED" then
		Everlook.drops.scan()
	elseif public(unit) == "player" then
		-- SENT carries the spell as its fourth value, the others as their third.
		local phase = CAST_PHASES[event]
		Everlook.drops.note_cast(public(phase == "sent" and fourth or third), phase)
	end
end)
