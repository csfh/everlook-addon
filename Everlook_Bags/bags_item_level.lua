local addon_name = ...
local Everlook = Everlook

local item_level = {}

local function readable(value)
	return not (issecretvalue and issecretvalue(value))
end

-- The text an item level label shows, and the quality that colours it. Only
-- weapons and armor carry one, which includes rings, trinkets and cloaks.
-- Anything missing, secret or not a number shows nothing.
function item_level.label(class_id, quality, level)
	local item_class = Enum and Enum.ItemClass
	if not item_class then return nil end
	if not (readable(class_id) and readable(quality) and readable(level)) then return nil end
	if class_id ~= item_class.Weapon and class_id ~= item_class.Armor then return nil end
	if type(quality) ~= "number" or type(level) ~= "number" or level <= 1 then return nil end
	return tostring(math.floor(level)), quality
end

Everlook.bags_item_level = item_level
