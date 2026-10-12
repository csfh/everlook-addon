local addon_name = ...
local Everlook = Everlook

-- The items the player marked as junk, as item id -> true. An id marks every
-- copy of the item, so a mark outlives the bag slot the item was in.
local junk = {}

local function valid(item_id)
	if issecretvalue and issecretvalue(item_id) then return false end
	return type(item_id) == "number" and item_id > 0 and item_id < math.huge and item_id == math.floor(item_id)
end

function junk.valid(item_id)
	return valid(item_id)
end

function junk.is_marked(data, item_id)
	return valid(item_id) and data[item_id] == true
end

-- Marks the item, or unmarks it when it was marked. Returns the new state, or
-- nil for an id this store will not hold.
function junk.toggle(data, item_id)
	if not valid(item_id) then return nil end
	if data[item_id] then
		data[item_id] = nil
		return false
	end
	data[item_id] = true
	return true
end

-- The saved table, kept with the rest of the Bags settings.
function junk.data()
	EverlookDB = EverlookDB or {}
	EverlookDB.qol = EverlookDB.qol or {}
	EverlookDB.qol.bags = EverlookDB.qol.bags or {}
	EverlookDB.qol.bags.junk = EverlookDB.qol.bags.junk or {}
	return EverlookDB.qol.bags.junk
end

Everlook.bags_junk = junk
