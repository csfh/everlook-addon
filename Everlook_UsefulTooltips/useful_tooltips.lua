local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "useful_tooltips"
local hooked = false
local seen = setmetatable({}, { __mode = "k" })

local function add_lookup(tooltip, kind, entry_id)
	if not module.get(id, "lookup") or not Everlook.world or not Everlook.world.lookup then return end
	if type(entry_id) ~= "number" then return end
	local lines = Everlook.world.lookup(kind, entry_id)
	for index = 1, #lines do
		tooltip:AddLine(lines[index], 0.8, 0.8, 0.8)
	end
end

local function once(tooltip, key)
	if seen[tooltip] == key then return false end
	seen[tooltip] = key
	if tooltip.HasScript and tooltip:HasScript("OnTooltipCleared") and not tooltip.everlook_qol_clear then
		tooltip.everlook_qol_clear = true
		tooltip:HookScript("OnTooltipCleared", function(self) seen[self] = nil end)
	end
	return true
end

local function item(tooltip, data)
	if not module.enabled(id) then return end
	local item_id = data and data.id
	if issecretvalue and issecretvalue(item_id) then return end
	if not item_id and tooltip.GetItem then
		local _, link = tooltip:GetItem()
		item_id = Everlook.items.id_from_link(link)
	end
	if type(item_id) ~= "number" or not once(tooltip, "item:" .. item_id) then return end
	if module.get(id, "item_ids") then tooltip:AddLine("Item ID: " .. item_id, 0.6, 0.8, 1) end
	add_lookup(tooltip, "item", item_id)
	if C_Item and C_Item.GetItemInfo then
		local price = select(11, C_Item.GetItemInfo(item_id))
		if type(price) == "number" and price > 0 and GetCoinTextureString then
			if module.get(id, "vendor_price") then tooltip:AddLine("Vendor: " .. GetCoinTextureString(price), 0.8, 0.8, 0.8) end
			if module.get(id, "stack_total") and C_Item.GetItemCount then
				local count = C_Item.GetItemCount(item_id, false)
				if count and count > 1 then tooltip:AddLine("In bags: " .. count .. " (" .. GetCoinTextureString(price * count) .. ")", 0.8, 0.8, 0.8) end
			end
		end
	end
end

local function unit(tooltip)
	if not module.enabled(id) or not tooltip.GetUnit or not UnitGUID then return end
	local _, token = tooltip:GetUnit()
	local npc_id = token and Everlook.npcs.creature_id(UnitGUID(token))
	if not npc_id and token and Everlook.world and Everlook.world.guid_id and UnitGUID then
		local guid = UnitGUID(token)
		local object_id = Everlook.world.guid_id(guid, "GameObject")
		if object_id and once(tooltip, "object:" .. object_id) then
			add_lookup(tooltip, "object", object_id)
		end
		return
	end
	if npc_id and once(tooltip, "npc:" .. npc_id) then
		if module.get(id, "npc_ids") then tooltip:AddLine("NPC ID: " .. npc_id, 0.6, 0.8, 1) end
		add_lookup(tooltip, "npc", npc_id)
	end
end

local function install(enabled)
	if not enabled or hooked then return end
	if TooltipDataProcessor and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, item)
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, unit)
		hooked = true
	elseif GameTooltip and GameTooltip.HasScript and GameTooltip:HasScript("OnTooltipSetItem") then
		GameTooltip:HookScript("OnTooltipSetItem", item)
		GameTooltip:HookScript("OnTooltipSetUnit", unit)
		hooked = true
	end
end

module.register({
	addon = addon_name, page = "tooltips", order = 10,
	id = id, name = "Useful tooltips", description = "Adds item and creature ids, a vendor price, a bag count, and recorded vendors, drops, spells, quests, and object contents to the matching tooltip. An id the client hides adds nothing, player and spell tooltips stay as they are, each line has its own option, and turning this off leaves them off the next tooltip.",
	options = {
		item_ids = { name = "Show item IDs", default = true, description = "Adds the item id to an item tooltip, and other tooltips stay as they are. Vendor value, bag quantity, and places you have seen stay on their own options, and an id the client hides adds no line." },
		npc_ids = { name = "Show NPC IDs", default = true, description = "Adds the NPC id to a creature or vehicle tooltip. Players, objects, and item tooltips stay as they are, places you have seen stay on their own option, and an id the client hides adds no line." },
		vendor_price = { name = "Show vendor value per item", default = true, description = "Adds the price a vendor pays for one of the item. An item with no sell price gets no line, other tooltips stay as they are, the bag total stays on its own option, and an id the client hides adds no line." },
		stack_total = { name = "Show bag quantity and total vendor value", default = true, description = "On an item tooltip, adds the number in your bags and what a vendor would pay for all of them, once you have more than one and the item sells. The bank is left out, a single copy or an item with no sell price gets no line, and the price of one item stays on its own option." },
		lookup = { name = "Show vendors, drops, spells, quests, and object contents you have seen", default = true, description = "Adds up to three lines on an item, creature, vehicle, or object tooltip for vendors, drops, spells, quests, and object contents you have already recorded. Players and spell tooltips stay without those lines, an id the client hides adds none, and the ids and sell price stay on their own options." },
	},
	apply = install, events = { "ADDON_LOADED" }, on_event = function() install(true) end,
})
