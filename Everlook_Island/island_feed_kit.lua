local Everlook = Everlook

-- What the island's feed addons share. A feed stays quiet until it has a
-- baseline, and rendering stays in the island.
local kit = {}
Everlook.island_feed_kit = kit

function kit.plain_number(value)
	if issecretvalue and issecretvalue(value) then return nil end
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return nil end
	return value
end

function kit.now()
	local value = GetTime and GetTime()
	return kit.plain_number(value) or 0
end

function kit.option(key)
	return Everlook.module.enabled("smart_island") and Everlook.module.get("smart_island", key) == true
end

-- False when combat kept the notice, so the feed holds its handle and tries again.
function kit.dismiss(handle)
	if not handle or not Everlook.island or not Everlook.island.dismiss then return true end
	local removed, reason = Everlook.island.dismiss(handle)
	return not (removed == nil and reason == "combat_locked")
end

function kit.notify(payload)
	if not Everlook.island or not Everlook.island.notify then return nil end
	local handle = Everlook.island.notify(payload)
	return handle
end

function kit.dismiss_map(handles)
	if not handles then return end
	local keys = {}
	for key in pairs(handles) do keys[#keys + 1] = key end
	for index = 1, #keys do
		local key = keys[index]
		if kit.dismiss(handles[key]) then handles[key] = nil end
	end
end

function kit.map_pending(handles)
	if not handles then return false end
	for _ in pairs(handles) do return true end
	return false
end

function kit.inspect_item(item_id)
	return function()
		if not GameTooltip or not GameTooltip.SetItemByID then return end
		if GameTooltip.SetOwner and UIParent then GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR") end
		GameTooltip:SetItemByID(item_id)
		if GameTooltip.Show then GameTooltip:Show() end
	end
end

-- Reputation, professions, mail and buffs have their own events. The timed
-- poll only backstops them, so it runs on a slower beat than the island's
-- one-second refresh. True when a poll that last ran at `last` is due again.
local SLOW_POLL = 5

function kit.due(last)
	local time = kit.now()
	return not (last and time >= last and time - last < SLOW_POLL)
end
