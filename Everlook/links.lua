local _, Everlook = ...

-- Pages on the Everlook site, by the kind of game id they take. The routes are
-- on the website. The data browser and the Site links module share them.
Everlook.links = {}

local base = "https://everlook.ing"
local paths = {
	item = "/database/items/", spell = "/database/spells/", npc = "/database/npcs/",
	object = "/database/objects/", quest = "/quests/",
}

function Everlook.links.url(kind, entry_id)
	local path = paths[kind]
	if not path or type(entry_id) ~= "number" or entry_id < 1 or entry_id % 1 ~= 0 then return end
	return base .. path .. string.format("%d", entry_id)
end
