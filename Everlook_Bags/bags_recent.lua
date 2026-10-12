local addon_name = ...
local Everlook = Everlook
local junk = Everlook.bags_junk

-- What arrived in the bags this session, newest first. The list is kept by
-- comparing the total of each item in the bags with the total last time, so a
-- stack that is split, merged or moved from slot to slot is not an arrival, and
-- looting, buying or taking an item out of the mail is. It is never saved.
local recent = { LIMIT = 12 }

local list = {}
list.__index = list

local function secret(value)
	return issecretvalue and issecretvalue(value)
end

-- The totals worth keeping: whole positive item ids with a real count.
local function clean(totals)
	local kept = {}
	for item_id, count in pairs(totals) do
		if junk.valid(item_id) and not secret(count) and type(count) == "number" then kept[item_id] = count end
	end
	return kept
end

-- Takes the item totals of the bags now, as item id -> count. The first look is
-- the baseline. Returns true when the list changed.
function list:observe(totals)
	if type(totals) ~= "table" then return false end
	local now = clean(totals)
	local before = self.last
	self.last = now
	if not before then return false end
	local arrived = {}
	for item_id, count in pairs(now) do
		if count > (before[item_id] or 0) then arrived[#arrived + 1] = item_id end
	end
	if #arrived == 0 then return false end
	-- Several arrivals in one look go in a fixed order, so the list does not depend on pairs.
	table.sort(arrived, function(first, second) return first > second end)
	for _, item_id in ipairs(arrived) do
		for index, known in ipairs(self.order) do
			if known == item_id then table.remove(self.order, index); break end
		end
		table.insert(self.order, 1, item_id)
	end
	while #self.order > recent.LIMIT do table.remove(self.order) end
	return true
end

function list:items()
	local copy = {}
	for index, item_id in ipairs(self.order) do copy[index] = item_id end
	return copy
end

-- The place of an item in the list, 1 being the newest, or nil.
function list:rank(item_id)
	for index, known in ipairs(self.order) do
		if known == item_id then return index end
	end
end

function list:has(item_id)
	return self:rank(item_id) ~= nil
end

function recent.new()
	return setmetatable({ order = {} }, list)
end

Everlook.bags_recent = recent
