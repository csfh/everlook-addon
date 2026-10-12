local addon_name = ...
local Everlook = Everlook

-- The sections group by type puts the combined bag's slots under, top to bottom.
-- Junk is ahead of an item's type, and free space is the empty slots, which the
-- caller finds because an empty slot has no item to ask about.
local categories = { FREE = "free" }

categories.SECTIONS = {
	{ key = "pinned", title = "Pinned" },
	{ key = "recent", title = "Recent" },
	{ key = "armory", title = "The Armory" },
	{ key = "prep", title = "Adventure Prep" },
	{ key = "professions", title = "Professions" },
	{ key = "misc", title = "Miscellaneous" },
	{ key = "junk", title = "Junk" },
	{ key = categories.FREE, title = "Free Space" },
}

-- The item classes each preset takes, by the game's own names. A class named
-- here that the client lacks is skipped, and any other class is miscellaneous.
local PRESETS = {
	armory = { "Weapon", "Armor" },
	prep = { "Consumable", "Gem", "ItemEnhancement" },
	professions = { "Reagent", "Tradegoods", "Recipe", "Profession" },
}

local function secret(value)
	return issecretvalue and issecretvalue(value)
end

local function preset_of(class_id)
	local names = Enum and Enum.ItemClass
	if type(names) ~= "table" then return nil end
	for key, members in pairs(PRESETS) do
		for _, name in ipairs(members) do
			if names[name] == class_id then return key end
		end
	end
end

-- The section of an item of this class. A pin of exactly true puts it in pinned, whatever
-- else it is. Otherwise junk of exactly true is junk, then a recent item of exactly true is
-- recent, and any other item goes by its class.
function categories.of(class_id, junk, pinned, recent)
	if pinned == true then return "pinned" end
	if junk == true then return "junk" end
	if recent == true then return "recent" end
	if secret(class_id) or type(class_id) ~= "number" then return "misc" end
	return preset_of(class_id) or "misc"
end

Everlook.bags_categories = categories
