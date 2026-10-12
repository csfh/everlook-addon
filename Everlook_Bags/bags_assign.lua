local addon_name = ...
local Everlook = Everlook
local junk = Everlook.bags_junk

-- Which of the custom sections the player put each item in, as item id -> 1, 2
-- or 3. Like a junk mark or a pin it is on the item and every copy of it.
local assign = {}
local SECTIONS = 3

local function section_number(value)
	return type(value) == "number" and value >= 1 and value <= SECTIONS and value == math.floor(value) and value or nil
end

function assign.of(data, item_id)
	if not junk.valid(item_id) then return nil end
	return section_number(data[item_id])
end

-- Moves the item to the next of the sections in use, `available` being their
-- numbers in order, and out of them all after the last. An item in a section
-- that is no longer in use starts again at the first. Returns where the item is
-- now, or nil for none.
function assign.cycle(data, item_id, available)
	if not junk.valid(item_id) or #available == 0 then return assign.of(data, item_id) end
	local current = assign.of(data, item_id)
	local target
	if not current then
		target = available[1]
	else
		local found = false
		for index, number in ipairs(available) do
			if number == current then
				found = true
				target = available[index + 1]
			end
		end
		if not found then target = available[1] end
	end
	data[item_id] = target
	return target
end

-- The saved table, kept with the rest of the Bags settings. Its key is not an option's name.
function assign.data()
	EverlookDB = EverlookDB or {}
	EverlookDB.qol = EverlookDB.qol or {}
	EverlookDB.qol.bags = EverlookDB.qol.bags or {}
	EverlookDB.qol.bags.assigned = EverlookDB.qol.bags.assigned or {}
	return EverlookDB.qol.bags.assigned
end

Everlook.bags_assign = assign
