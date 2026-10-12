local addon_name = ...
local Everlook = Everlook

-- The sections group by type puts the combined bag's slots under, top to bottom.
-- Junk is ahead of an item's type, and free space is the empty slots, which the
-- caller finds because an empty slot has no item to ask about.
local categories = { FREE = "free" }

categories.SECTIONS = {
	{ key = "pinned", title = "Pinned" },
	{ key = "recent", title = "Recent" },
	{ key = "custom1", title = "Custom 1" },
	{ key = "custom2", title = "Custom 2" },
	{ key = "custom3", title = "Custom 3" },
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

local CUSTOM = { custom1 = true, custom2 = true, custom3 = true }

-- The section of an item of this class. A pin of exactly true puts it in pinned, whatever
-- else it is, then a custom section's own key puts it there. Otherwise junk of exactly true is junk, then a recent item of exactly true is
-- recent, and any other item goes by its class.
function categories.of(class_id, junk, pinned, recent, custom)
	if pinned == true then return "pinned" end
	if CUSTOM[custom] then return custom end
	if junk == true then return "junk" end
	if recent == true then return "recent" end
	if secret(class_id) or type(class_id) ~= "number" then return "misc" end
	return preset_of(class_id) or "misc"
end

-- Sections that split by the expansion their items belong to. Pinned, recent,
-- junk and free space are about something other than what an item is.
local NESTED = { armory = true, prep = true, professions = true, misc = true }

local function expansion_valid(expansion)
	return not secret(expansion) and type(expansion) == "number" and expansion >= 0
		and expansion < math.huge and expansion == math.floor(expansion)
end

-- The key of the section for an item of this section's kind from this expansion,
-- or the section's own key when it does not nest or the expansion is not known.
function categories.sub_key(key, expansion)
	if not NESTED[key] or not expansion_valid(expansion) then return key end
	return key .. ":" .. expansion
end

-- The title to match, naming the expansion when the game has a name for it.
function categories.sub_title(key, title, expansion)
	if not NESTED[key] or not expansion_valid(expansion) then return title end
	local names = _G
	local name = type(names) == "table" and names["EXPANSION_NAME" .. expansion]
	if type(name) ~= "string" or name == "" then return title end
	return title .. ": " .. name
end

-- Orders sections of one kind: the newer expansion first, none last.
function categories.newer_first(first, second)
	if first == second then return false end
	if first == nil then return false end
	if second == nil then return true end
	return first > second
end

Everlook.bags_categories = categories
