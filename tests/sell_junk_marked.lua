-- Sell junk with items the player marked in Bags, using the real Bags module.
-- Marked items go through the same checks as a grey item, except the grey quality.
return function(root, check, load_qol)
	-- One vendor visit. `setup` can change the world after the Bags settings are in place and
	-- before the vendor opens. `during` runs after the vendor opened and before the first sale.
	local function visit(setup, during)
		local addon, env, event, _, tickers = load_qol()
		local slots = {
			{ itemID = 1, quality = 0, stackCount = 1 },
			{ itemID = 2, quality = 1, stackCount = 1 },
			{ itemID = 3, quality = 1, stackCount = 1 },
		}
		local sold = {}
		env.NUM_BAG_SLOTS = 0
		local prices = { [1] = 10, [2] = 10, [3] = 10 }
		env.C_Item = {
			GetItemInfo = function(item_id)
				return "Item", nil, 1, 1, 0, "Miscellaneous", "Junk", 20, "", 1, prices[item_id], 15, 0, 0, 0, nil, false
			end,
		}
		env.C_Container = {
			GetContainerNumSlots = function() return #slots end,
			GetContainerItemInfo = function(_, slot) return slots[slot] end,
			UseContainerItem = function(_, slot) sold[#sold + 1] = slot; slots[slot] = nil end,
		}
		addon.say = function() end
		addon.module.set("sell_junk", "enabled", true)
		addon.module.set("sell_junk", "marked_junk", true)
		addon.module.set("bags", "enabled", true)
		addon.module.set("bags", "junk_marker", true)
		-- The player marked item 3 in Bags.
		addon.bags_junk.toggle(addon.bags_junk.data(), 3)
		local world = { slots = slots, prices = prices, addon = addon, env = env, rows = {} }
		addon.world = { row = function(_, item_id) return world.rows[item_id] end }
		if setup then setup(world) end
		event("MERCHANT_SHOW")
		if during then during(world) end
		for _ = 1, 8 do
			for _, ticker in ipairs(tickers) do
				if not ticker.cancelled then ticker.callback() end
			end
		end
		table.sort(sold)
		return table.concat(sold, ","), world
	end

	check("a grey item and a marked item sell, and an unmarked white item stays", (visit()) == "1,3")
	check("without the option only the grey item sells", (visit(function(w) w.addon.module.set("sell_junk", "marked_junk", false) end)) == "1")
	check("the option is off until it is turned on", (function()
		local addon = load_qol()
		for _, module in ipairs(addon.module.modules) do
			if module.id == "sell_junk" then return module.options.marked_junk and module.options.marked_junk.default == false end
		end
	end)())
	check("with Bags off a marked item stays", (visit(function(w) w.addon.module.set("bags", "enabled", false) end)) == "1")
	check("with the marker off a marked item stays", (visit(function(w) w.addon.module.set("bags", "junk_marker", false) end)) == "1")
	check("with no Bags table a marked item stays and grey still sells", (visit(function(w) w.addon.bags = nil end)) == "1")
	check("with no is_junk function a marked item stays", (visit(function(w) w.addon.bags = {} end)) == "1")
	check("an answer that is not exactly true sells nothing extra", (visit(function(w) w.addon.bags = { is_junk = function() return "yes" end } end)) == "1")
	check("an answer of true for an item sells it", (visit(function(w) w.addon.bags = { is_junk = function(item_id) return item_id == 2 end } end)) == "1,2")
	check("holding Shift when the vendor opens sells nothing", (visit(function(w) w.env.IsShiftKeyDown = function() return true end end)) == "")
	check("an item unmarked after the vendor opened is not sold", (visit(nil, function(w) w.addon.bags_junk.toggle(w.addon.bags_junk.data(), 3) end)) == "1")
	check("turning Bags off during the visit stops a marked sale but not a grey one", (visit(nil, function(w) w.addon.module.set("bags", "enabled", false) end)) == "1")
	check("turning the option off during the visit stops a marked sale", (visit(nil, function(w) w.addon.module.set("sell_junk", "marked_junk", false) end)) == "1")
	check("a marked item with no sell price stays", (visit(function(w) w.prices[3] = nil end)) == "1")
	check("a marked locked item stays", (visit(function(w) w.slots[3].isLocked = true end)) == "1")
	check("a marked item the game says has no value stays", (visit(function(w) w.slots[3].hasNoValue = true end)) == "1")
	check("a marked quest starter stays in the bag", (visit(function(w) w.rows[3] = { startsQuestId = 99 } end)) == "1")
	check("a marked recipe stays in the bag", (visit(function(w) w.rows[3] = { teachesSpellId = 5 } end)) == "1")
	check("a marked crafting reagent stays in the bag", (visit(function(w) w.rows[3] = { isCraftingReagent = true } end)) == "1")
	check("a marked item with several copies in a stack sells the stack", (function()
		local result = visit(function(w) w.slots[3].stackCount = 5 end)
		return result == "1,3"
	end)())
end
