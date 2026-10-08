local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "site_links"
local hooked
local seen = setmetatable({}, { __mode = "k" })

local function show(tooltip, kind, entry_id)
	local key = kind .. ":" .. entry_id
	if seen[tooltip] == key then return end
	seen[tooltip] = key
	if tooltip.HasScript and tooltip:HasScript("OnTooltipCleared") and not tooltip.everlook_link_clear then
		tooltip.everlook_link_clear = true
		tooltip:HookScript("OnTooltipCleared", function(self) seen[self] = nil end)
	end
	tooltip:AddLine("Everlook: " .. (Everlook.links.url(kind, entry_id):gsub("^https://", "")), 0.6, 0.8, 1)
end

-- Ids can be secret values, which cannot be formatted into a link.
local function usable(value)
	return type(value) == "number" and not (issecretvalue and issecretvalue(value))
end

local function item(tooltip, data)
	if not module.enabled(id) then return end
	local item_id = data and data.id
	if issecretvalue and issecretvalue(item_id) then return end
	if not item_id and tooltip.GetItem then
		local _, link = tooltip:GetItem()
		item_id = Everlook.items.id_from_link(link)
	end
	if usable(item_id) then show(tooltip, "item", item_id) end
end

local function spell(tooltip, data)
	if not module.enabled(id) then return end
	local spell_id = data and data.id
	if usable(spell_id) then show(tooltip, "spell", spell_id) end
end

local function unit(tooltip)
	if not module.enabled(id) or not tooltip.GetUnit or not UnitGUID then return end
	local _, token = tooltip:GetUnit()
	local npc_id = token and Everlook.npcs.creature_id(UnitGUID(token))
	if npc_id then show(tooltip, "npc", npc_id) end
end

local function apply(enabled)
	if not enabled or hooked or not TooltipDataProcessor or not Enum or not Enum.TooltipDataType then return end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, item)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, spell)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, unit)
	hooked = true
end

module.register({
	addon = addon_name, page = "tooltips", order = 20,
	id = id, name = "Everlook links",
	description = "Shows Everlook: everlook.ing and the page on an item, spell, creature, or vehicle tooltip, for you to type. A player, an object, and a quest stay without that line, an id the client hides gets no address, a tooltip already showing keeps its line, turning this off leaves the address off the next tooltip, and nothing happens when the client has no way to add the line.",
	apply = apply,
})
