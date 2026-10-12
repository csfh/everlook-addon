local addon_name = ...
local Everlook = Everlook
local junk = Everlook.bags_junk

-- What is remembered about each character's bags and bank, so a tooltip can say
-- where else an item is. A scan keeps item, count and quality of each filled
-- slot by bag and slot, and nothing else.
local alts = {
	BAGS = { 0, 1, 2, 3, 4, 5 },
	CHARACTER_BANK = { 6, 7, 8, 9, 10, 11 },
	WARBAND_BANK = { 12, 13, 14, 15, 16 },
}

local function secret(value)
	return issecretvalue and issecretvalue(value)
end

-- { [bag] = { [slot] = { item_id, count, quality } } } for the given bags, or
-- nil when the client has no container API.
function alts.scan(bag_ids)
	if type(C_Container) ~= "table" or type(C_Container.GetContainerNumSlots) ~= "function"
		or type(C_Container.GetContainerItemInfo) ~= "function" then
		return nil
	end
	local scanned = {}
	for _, bag in ipairs(bag_ids) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if type(info) == "table" and junk.valid(info.itemID) then
				local count = type(info.stackCount) == "number" and not secret(info.stackCount) and info.stackCount or 1
				local quality = type(info.quality) == "number" and not secret(info.quality) and info.quality or 1
				scanned[bag] = scanned[bag] or {}
				scanned[bag][slot] = { info.itemID, count, quality }
			end
		end
	end
	return scanned
end

-- How many of an item a scan holds.
function alts.count(scanned, item_id)
	if type(scanned) ~= "table" then return 0 end
	local total = 0
	for _, slots in pairs(scanned) do
		for _, entry in pairs(slots) do
			if entry[1] == item_id then total = total + entry[2] end
		end
	end
	return total
end

-- The characters other than `current` that have the item, the one with most first, and
-- how many are in the warband bank.
function alts.others(root, current, item_id)
	local found = {}
	if type(root) ~= "table" or not junk.valid(item_id) then return found, 0 end
	for key, character in pairs(root.characters or {}) do
		if key ~= current then
			local in_bags, in_bank = alts.count(character.bags, item_id), alts.count(character.bank, item_id)
			if in_bags + in_bank > 0 then
				found[#found + 1] = { name = character.name or key, realm = character.realm, bags = in_bags, bank = in_bank }
			end
		end
	end
	table.sort(found, function(first, second)
		local first_total, second_total = first.bags + first.bank, second.bags + second.bank
		if first_total ~= second_total then return first_total > second_total end
		return first.name < second.name
	end)
	return found, alts.count(root.warband and root.warband.bank, item_id)
end

function alts.key(name, realm)
	if type(name) ~= "string" or name == "" or type(realm) ~= "string" or realm == "" then return nil end
	return name .. "-" .. realm
end

-- The saved tables, kept with the rest of the Bags settings. The key is not an option's name.
function alts.data()
	EverlookDB = EverlookDB or {}
	EverlookDB.qol = EverlookDB.qol or {}
	EverlookDB.qol.bags = EverlookDB.qol.bags or {}
	local root = EverlookDB.qol.bags.remembered or {}
	EverlookDB.qol.bags.remembered = root
	root.characters = root.characters or {}
	return root
end

Everlook.bags_alts = alts
