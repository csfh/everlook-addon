local addon_name = ...
local Everlook = Everlook
local junk = Everlook.bags_junk

-- The items the player pinned, as item id -> true. Like a junk mark, a pin is
-- on the item and every copy of it, not on a bag slot.
local pins = {}

function pins.is_pinned(data, item_id)
	return junk.valid(item_id) and data[item_id] == true
end

-- Pins the item, or unpins it when it was pinned. Returns the new state, or nil
-- for an id this store will not hold.
function pins.toggle(data, item_id)
	if not junk.valid(item_id) then return nil end
	if data[item_id] then
		data[item_id] = nil
		return false
	end
	data[item_id] = true
	return true
end

-- The saved table, kept with the rest of the Bags settings. Its key is not the option's name, which would share it.
function pins.data()
	EverlookDB = EverlookDB or {}
	EverlookDB.qol = EverlookDB.qol or {}
	EverlookDB.qol.bags = EverlookDB.qol.bags or {}
	EverlookDB.qol.bags.pinned = EverlookDB.qol.bags.pinned or {}
	return EverlookDB.qol.bags.pinned
end

Everlook.bags_pins = pins
