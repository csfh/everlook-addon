local _, Everlook = ...

Everlook.drops = {}

-- COMBAT_LOG_EVENT_UNFILTERED cannot be registered by addons on this client.
-- Opening a creature's loot window is the kill and the drop we can still see.

local public = Everlook.public

-- Spells whose result opens a loot window that no creature dropped. The loot
-- source on those windows is an item, and may be unreadable, so the cast
-- itself is the signal that keeps the target from being credited.
local NON_CREATURE_LOOT = {
	[1804] = true, -- Pick Lock
	[13262] = true, -- Disenchant
	[31252] = true, -- Prospecting
	[51005] = true, -- Milling
}
-- Spells whose loot window is on a creature, yet is not the kill's drop:
-- skinning opens the corpse a second time, and picking a pocket opens a mob
-- that is still alive. The window is counted as its own kind, never as a kill.
local CREATURE_LOOT_KIND = {
	[921] = "pickpocket",
	[8613] = "skin",
	[8617] = "skin",
	[8618] = "skin",
	[10768] = "skin",
}
local CAST_WINDOW = 10
local RESULT_WINDOW = 3
-- Corpses already counted this session, so reopening one adds nothing.
local COUNTED_CORPSES = 128

local item_loot_until = 0
local creature_loot_until = 0
local creature_loot_kind
local counted, counted_order, counted_next = {}, {}, 0

local function clock()
	return type(GetTime) == "function" and public(GetTime()) or nil
end

-- A cast that starts holds the window open for its channel, one that lands
-- shortens it to the moment its loot appears, and one that fails closes it.
function Everlook.drops.note_cast(spellId, phase)
	local now = clock()
	local kind = CREATURE_LOOT_KIND[spellId]
	if not (now and (NON_CREATURE_LOOT[spellId] or kind)) then
		return
	end
	local until_time = phase == "failed" and 0 or now + (phase == "landed" and RESULT_WINDOW or CAST_WINDOW)
	if kind then
		creature_loot_until = until_time
		creature_loot_kind = kind
	else
		item_loot_until = until_time
	end
end

-- The kind of creature window the last cast opened, once: "skin", "pickpocket" or nil.
local function creature_loot_open()
	local now = clock()
	if now and now <= creature_loot_until then
		creature_loot_until = 0
		return creature_loot_kind
	end
	return nil
end

-- Whether this window is the first on that corpse. A corpse the client does not
-- name cannot be told apart, so it counts as it always has.
local function first_window(guid, windows)
	if type(guid) ~= "string" or not Everlook.world.usable(guid) then
		return true
	end
	if windows[guid] then
		return true
	end
	if counted[guid] then
		return false
	end
	windows[guid] = true
	counted[guid] = true
	counted_next = counted_next % COUNTED_CORPSES + 1
	local evicted = counted_order[counted_next]
	if evicted then
		counted[evicted] = nil
	end
	counted_order[counted_next] = guid
	return true
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
local kill_row = { kills = 1, loots = 1, pickpockets = 0, skins = 0, empties = 0 }
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
	local windows = {}
	local creature_kind = creature_loot_open()
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
			elseif itemId and npcId and creature_kind then
				if not killed[npcId] then
					killed[npcId] = true
					kill_row.npcId = npcId
					kill_row.kills = 0
					kill_row.loots = 0
					kill_row.pickpockets = creature_kind == "pickpocket" and 1 or 0
					kill_row.skins = creature_kind == "skin" and 1 or 0
					kill_row.empties = 0
					Everlook.world.count("kills", kill_row)
				end
			elseif itemId and npcId and first_window(guid, windows) then
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
					kill_row.empties = 0
					Everlook.world.count("kills", kill_row)
					Everlook.npcs.record("npc", "loot")
					Everlook.npcs.record("target", "loot")
				end
			end
		end
	end
end

-- A kill with nothing to loot never opens a loot window, so it never reaches the count a drop chance is out of.
-- A death is counted as such only when it is surely the player's own: the creature was the player's target, was
-- not tapped by someone else, and the player was fighting; and only when the game says, a second later, that the
-- corpse holds nothing and may be looted. A death the client hides, or a client missing any of these functions, counts nothing.
local DEATH_DELAY = 1
local DIED_KEPT = 128
local died, died_order, died_next = {}, {}, 0
local empty_row = { kills = 0, loots = 0, pickpockets = 0, skins = 0, empties = 1 }

local function remember_death(guid)
	if died[guid] then return false end
	died[guid] = true
	died_next = died_next % DIED_KEPT + 1
	local evicted = died_order[died_next]
	if evicted then died[evicted] = nil end
	died_order[died_next] = guid
	return true
end

local function mine(guid)
	if type(UnitGUID) ~= "function" or type(UnitIsTapDenied) ~= "function" or type(UnitAffectingCombat) ~= "function" then return false end
	if public(UnitGUID("target")) ~= guid then return false end
	return public(UnitIsTapDenied("target")) == false and public(UnitAffectingCombat("player")) == true
end

function Everlook.drops.note_death(guid)
	guid = public(guid)
	if type(guid) ~= "string" or type(CanLootUnit) ~= "function" or not (C_Timer and type(C_Timer.After) == "function") then return end
	local npcId = Everlook.npcs.creature_id(guid)
	if not npcId or not mine(guid) or not remember_death(guid) then return end
	-- Kill credit asks who died just now.
	Everlook.drops.last_kill = { npcId = npcId, at = type(GetTime) == "function" and public(GetTime()) or nil, used = false }
	C_Timer.After(DEATH_DELAY, function()
		if counted[guid] then return end
		-- On build 70374 an empty corpse of the player's own kill answered (hasLoot false, canLoot true); a creature
		-- someone else killed answered (false, false), and one with loot the player may not take (true, false).
		local ok, has_loot, can_loot = pcall(CanLootUnit, guid)
		if ok and public(has_loot) == false and public(can_loot) == true then
			empty_row.npcId = npcId
			Everlook.world.count("kills", empty_row)
		end
	end)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("LOOT_OPENED")
-- Not every client has this event, and registering one it lacks raises an error.
if frame.RegisterEvent then pcall(frame.RegisterEvent, frame, "UNIT_DIED") end
-- Only the player's own casts matter, so the client sends no one else's.
for _, event in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED" }) do
	if frame.RegisterUnitEvent then
		frame:RegisterUnitEvent(event, "player")
	else
		frame:RegisterEvent(event)
	end
end
local CAST_PHASES = {
	UNIT_SPELLCAST_SENT = "sent",
	UNIT_SPELLCAST_SUCCEEDED = "landed",
	UNIT_SPELLCAST_INTERRUPTED = "failed",
	UNIT_SPELLCAST_FAILED = "failed",
}
frame:SetScript("OnEvent", function(_, event, unit, second, third, fourth)
	if event == "LOOT_OPENED" then
		Everlook.drops.scan()
	elseif event == "UNIT_DIED" then
		Everlook.drops.note_death(unit)
	elseif public(unit) == "player" then
		-- SENT carries the spell as its fourth value, the others as their third.
		local phase = CAST_PHASES[event]
		Everlook.drops.note_cast(public(phase == "sent" and fourth or third), phase)
	end
end)
