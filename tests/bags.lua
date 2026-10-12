-- The combined bag module: the grid it lays out, the item level it labels gear
-- with, its registration, and how it applies and undoes a layout on a stand-in
-- for the stock frame. How the stock frame behaves in the game is not tested here.
return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)
	local ITEM, SPACING = 37, 5

	local function load_bags(extra)
		local env = setmetatable({}, { __index = _G })
		env._G = env
		env.EverlookDB = {}
		env.IsShiftKeyDown = function() return false end
		local loaded = {}
		env.EventUtil = { ContinueOnAddOnLoaded = function(name, callback) loaded[name] = callback end }
		env.CreateFrame = function()
			local frame = { events = {} }
			function frame:RegisterEvent(event) self.events[event] = true end
			function frame:SetScript() end
			return frame
		end
		env.hooksecurefunc = function(target, method, callback)
			local original = target[method]
			target[method] = function(self, ...)
				original(self, ...)
				callback(self, ...)
			end
		end
		env.Enum = { ItemClass = { Weapon = 2, Armor = 4, Consumable = 0 } }
		for key, value in pairs(extra or {}) do env[key] = value end
		local addon = {}
		-- world.lua shares the namespace as the global Everlook.
		env.Everlook = addon
		for _, file in ipairs({ "module", "bags_layout", "bags_item_level", "bags" }) do
			local chunk = assert(loadfile(source(file)))
			setfenv(chunk, env)
			chunk(file == "bags" and "Everlook_Bags" or "Everlook", addon)
		end
		return addon, env, loaded
	end

	-- The grid, as the stock combined bag draws it: ten columns, 37 pixel slots
	-- with 5 between, filled from the bottom right towards the top left.
	do
		local addon = load_bags()
		local layout = addon.bags_layout
		check("the layout knows the stock column count", layout and layout.STOCK_COLUMNS == 10)
		local grid = layout.grid(25, 10)
		check("twenty-five slots in ten columns take three rows", grid.rows == 3)
		check("the first slot sits at the anchor", grid.positions[1].x == 0 and grid.positions[1].y == 0)
		check("the second slot sits one slot to the left", grid.positions[2].x == -(ITEM + SPACING) and grid.positions[2].y == 0)
		check("the tenth slot ends the first row", grid.positions[10].x == -9 * (ITEM + SPACING) and grid.positions[10].y == 0)
		check("the eleventh slot starts the next row up", grid.positions[11].x == 0 and grid.positions[11].y == ITEM + SPACING)
		check("the last slot is on the third row", grid.positions[25].x == -4 * (ITEM + SPACING) and grid.positions[25].y == 2 * (ITEM + SPACING))
		check("the grid is as wide as ten slots and their gaps", grid.width == 10 * ITEM + 9 * SPACING)
		check("the grid is as tall as three rows and their gaps", grid.height == 3 * ITEM + 2 * SPACING)
		check("every slot gets a place", #grid.positions == 25)
		local wide = layout.grid(25, 14)
		check("more columns make fewer rows", wide.rows == 2 and wide.positions[15].x == 0 and wide.positions[15].y == ITEM + SPACING)
		check("more columns make a wider grid", wide.width == 14 * ITEM + 13 * SPACING)
		check("a single column stacks the slots", layout.grid(3, 1).positions[3].y == 2 * (ITEM + SPACING) and layout.grid(3, 1).positions[3].x == 0)

		-- The stock frame is the base: a different column count moves only the grid's share of its size.
		local width, height = layout.resized(400, 600, 25, 10)
		check("the stock column count leaves the frame size as it was", width == 400 and height == 600)
		width, height = layout.resized(400, 600, 25, 14)
		check("four more columns widen the frame by four slots", width == 400 + 4 * (ITEM + SPACING))
		check("fewer rows make the frame shorter by the rows lost", height == 600 - (ITEM + SPACING))

		-- The order stock gives the slots: bags from the last to the first, and
		-- slots from the first up, with a locked slot after the rest.
		local ordered = layout.order({
			{ bag = 0, slot = 2 }, { bag = 1, slot = 1 }, { bag = 0, slot = 1 },
			{ bag = 4, slot = 3, extended = true }, { bag = 4, slot = 1 },
		})
		local sequence = {}
		for _, entry in ipairs(ordered) do sequence[#sequence + 1] = entry.bag .. ":" .. entry.slot end
		check("slots run from the last bag down, then up through each bag, and a locked slot comes last",
			table.concat(sequence, " ") == "4:1 1:1 0:1 0:2 4:3")
		local input = { { bag = 0, slot = 2 }, { bag = 0, slot = 1 } }
		layout.order(input)
		check("ordering leaves the list it was given alone", input[1].slot == 2)
	end

	-- The item level label: gear only, in the item's quality.
	do
		local addon = load_bags()
		local item_level = addon.bags_item_level
		local text, quality = item_level.label(4, 4, 276)
		check("armor shows its item level in its quality", text == "276" and quality == 4)
		text = item_level.label(2, 3, 201)
		check("a weapon shows its item level", text == "201")
		check("a consumable shows none", item_level.label(0, 1, 50) == nil)
		check("an item that is not gear shows none however high its level", item_level.label(7, 5, 600) == nil)
		check("gear with no level shows none", item_level.label(4, 4, nil) == nil)
		check("a level of one shows none", item_level.label(4, 1, 1) == nil)
		check("a missing quality shows none", item_level.label(4, nil, 100) == nil)
		check("a missing class shows none", item_level.label(nil, 4, 100) == nil)
		check("a level that is not a number shows none", item_level.label(4, 4, "276") == nil)
		local secret = {}
		local guarded = load_bags({ issecretvalue = function(value) return value == secret end })
		check("a secret level shows none", guarded.bags_item_level.label(4, 4, secret) == nil)
		check("a secret class shows none", guarded.bags_item_level.label(secret, 4, 100) == nil)
		check("a secret quality shows none", guarded.bags_item_level.label(4, secret, 100) == nil)
		local no_enum = load_bags({ Enum = false })
		check("without the item class names nothing is gear", no_enum.bags_item_level.label(4, 4, 276) == nil)
	end

	-- Registration.
	do
		local addon = load_bags()
		local found
		for _, module in ipairs(addon.module.modules) do
			if module.id == "bags" then found = module end
		end
		check("the bags module registers", found ~= nil)
		check("it sits on the Interface page", found and found.page == "interface")
		check("it starts disabled", found and not addon.module.enabled("bags"))
		check("item level on gear starts off", found and found.options.item_level and found.options.item_level.default == false)
		local columns = found and found.options.columns
		check("columns start at the stock ten", columns and columns.default == 10)
		check("columns run from ten to sixteen", columns and columns.min == 10 and columns.max == 16 and columns.step == 1)
		check("it names its own addon", found and found.addon == "Everlook_Bags")
	end

	-- Applying and undoing, on a stand-in for the stock frame.
	local function stand_in(slot_total, gear)
		local points_log = {}
		local frame = { MoneyFrame = { name = "money" }, width = 400, height = 600, buttons = {}, layouts = 0 }
		function frame:SetSize(width, height) self.width, self.height = width, height end
		function frame:GetWidth() return self.width end
		function frame:GetHeight() return self.height end
		function frame:IsShown() return true end
		function frame:EnumerateValidItems() return ipairs(self.buttons) end
		for index = 1, slot_total do
			local button = { slot = index, points = {}, texts = {} }
			function button:GetBagID() return 0 end
			function button:GetID() return self.slot end
			function button:IsExtended() return false end
			function button:ClearAllPoints() self.points = {} end
			function button:SetPoint(...) self.points[#self.points + 1] = { ... } end
			function button:CreateFontString(_, _, template)
				local text = { template = template, shown = true, content = nil }
				function text:SetPoint(...) self.point = { ... } end
				function text:SetDrawLayer(layer, sublevel) self.layer, self.sublevel = layer, sublevel end
				function text:SetText(content) self.content = content end
				function text:SetTextColor(red, green, blue) self.color = { red, green, blue } end
				function text:Show() self.shown = true end
				function text:Hide() self.shown = false end
				self.texts[#self.texts + 1] = text
				return text
			end
			frame.buttons[index] = button
		end
		-- What stock does on a layout pass: a ten column grid of its own, then the size it wants.
		function frame:UpdateItemLayout()
			self.layouts = self.layouts + 1
			self:SetSize(400, 600)
			for index, button in ipairs(self.buttons) do
				button:ClearAllPoints()
				button:SetPoint("BOTTOMRIGHT", self.MoneyFrame, "TOPRIGHT",
					-((index - 1) % 10) * 42, 4 + math.floor((index - 1) / 10) * 42)
			end
		end
		function frame:UpdateItems() end
		local info = {}
		for index = 1, slot_total do
			local entry = gear and gear[index]
			if entry then info[index] = { itemID = 1000 + index, hyperlink = "link" .. index, quality = entry.quality, class = entry.class, level = entry.level } end
		end
		local env_extra = {
			ContainerFrameCombinedBags = frame,
			C_Container = { GetContainerItemInfo = function(bag, slot) if bag == 0 then return info[slot] end end },
			C_Item = {
				GetItemInfoInstant = function(item_id) return item_id, "", "", "", 0, info[item_id - 1000].class, 0 end,
				GetDetailedItemLevelInfo = function(link) return info[tonumber(link:match("%d+"))].level end,
			},
			ColorManager = { GetColorDataForItemQuality = function(quality) return { r = quality / 10, g = 0.5, b = 0.25 } end },
		}
		return frame, env_extra, points_log
	end
	local function anchor(button) return button.points[1] end

	do
		local frame, extra = stand_in(25)
		local addon, _, loaded = load_bags(extra)
		loaded["Everlook_Bags"]()
		check("a disabled module leaves the stock layout alone", anchor(frame.buttons[2]) == nil)
		frame:UpdateItemLayout()
		check("a disabled module leaves the stock grid in place", anchor(frame.buttons[11])[5] == 4 + 42 and frame.width == 400)

		addon.module.set("bags", "enabled", true)
		check("enabling at ten columns changes nothing on screen", anchor(frame.buttons[11])[5] == 4 + 42 and frame.width == 400 and frame.height == 600)
		addon.module.set("bags", "columns", 14)
		check("fourteen columns put the fifteenth slot on the second row",
			anchor(frame.buttons[15])[4] == 0 and anchor(frame.buttons[15])[5] == 4 + 42)
		check("slots keep the stock anchor frame and corner",
			anchor(frame.buttons[3])[1] == "BOTTOMRIGHT" and anchor(frame.buttons[3])[2] == frame.MoneyFrame and anchor(frame.buttons[3])[3] == "TOPRIGHT")
		check("fourteen columns widen the open frame and shorten it by a row", frame.width == 400 + 4 * 42 and frame.height == 600 - 42)
		check("a button has one anchor, not a pile of them", #frame.buttons[3].points == 1)

		frame:UpdateItemLayout()
		check("a layout pass by the game is laid out again at fourteen columns",
			anchor(frame.buttons[15])[5] == 4 + 42 and frame.width == 400 + 4 * 42 and frame.height == 600 - 42)

		addon.module.set("bags", "columns", 10)
		check("going back to ten columns puts every slot where stock does",
			anchor(frame.buttons[11])[4] == 0 and anchor(frame.buttons[11])[5] == 4 + 42 and anchor(frame.buttons[10])[4] == -9 * 42)
		check("going back to ten columns restores the stock size", frame.width == 400 and frame.height == 600)

		addon.module.set("bags", "columns", 12)
		addon.module.set("bags", "enabled", false)
		check("disabling puts the open frame and its slots back as stock draws them",
			frame.width == 400 and frame.height == 600 and anchor(frame.buttons[11])[4] == 0 and anchor(frame.buttons[11])[5] == 4 + 42)
		frame:UpdateItemLayout()
		check("a disabled module no longer changes the layout the game draws", frame.width == 400 and anchor(frame.buttons[12])[4] == -1 * 42)
	end

	do
		-- The hook is installed once however often the module is applied.
		local frame, extra = stand_in(12)
		local addon, _, loaded = load_bags(extra)
		loaded["Everlook_Bags"]()
		addon.module.set("bags", "enabled", true)
		addon.module.set("bags", "columns", 12)
		addon.module.set("bags", "columns", 13)
		addon.module.set("bags", "columns", 12)
		frame:UpdateItemLayout()
		check("applying the module again does not stack the layout hook", #frame.buttons[12].points == 1 and frame.width == 400 + 2 * 42)
	end

	do
		-- Item level labels.
		local gear = { { class = 4, quality = 4, level = 276 }, { class = 0, quality = 1, level = 1 }, { class = 2, quality = 3, level = 201 } }
		local frame, extra = stand_in(3, gear)
		local addon, _, loaded = load_bags(extra)
		loaded["Everlook_Bags"]()
		addon.module.set("bags", "enabled", true)
		frame:UpdateItems()
		check("item level is off by default and adds no text", #frame.buttons[1].texts == 0)
		addon.module.set("bags", "item_level", true)
		check("turning item level on labels gear at once", frame.buttons[1].texts[1] and frame.buttons[1].texts[1].content == "276" and frame.buttons[1].texts[1].shown)
		check("the label uses the stock stack count's font", frame.buttons[1].texts[1].template == "NumberFontNormal")
		local point = frame.buttons[1].texts[1].point
		check("the label sits where the stack count does, at the bottom right of the slot",
			point[1] == "BOTTOMRIGHT" and point[2] == frame.buttons[1] and point[3] == "BOTTOMRIGHT" and point[4] == -5 and point[5] == 2)
		check("the label takes the item's quality colour", frame.buttons[1].texts[1].color[1] == 0.4 and frame.buttons[1].texts[1].color[2] == 0.5)
		check("an item that is not gear has no label", frame.buttons[2].texts[1] == nil or not frame.buttons[2].texts[1].shown)
		check("a weapon is labelled", frame.buttons[3].texts[1].content == "201")
		check("each button gets one text however often it is refreshed", (function() frame:UpdateItems(); frame:UpdateItems(); return #frame.buttons[1].texts == 1 end)())

		-- The item in a slot changes: the label follows, and an empty slot loses it.
		gear[1] = nil
		extra.C_Container.GetContainerItemInfo = function(bag, slot) if bag == 0 and gear[slot] then return { itemID = 1000 + slot, hyperlink = "link" .. slot, quality = gear[slot].quality } end end
		frame:UpdateItems()
		check("a slot that empties loses its label", not frame.buttons[1].texts[1].shown)

		addon.module.set("bags", "item_level", false)
		check("turning item level off hides every label", not frame.buttons[3].texts[1].shown)
		addon.module.set("bags", "item_level", true)
		check("turning it back on shows them again", frame.buttons[3].texts[1].shown and frame.buttons[3].texts[1].content == "201")
		addon.module.set("bags", "enabled", false)
		check("disabling the module hides every label", not frame.buttons[3].texts[1].shown)
	end

	do
		-- Missing pieces of the game: the module does nothing and says nothing.
		local frame, extra = stand_in(12)
		extra.ContainerFrameCombinedBags = nil
		local addon, _, loaded = load_bags(extra)
		loaded["Everlook_Bags"]()
		local ok = pcall(addon.module.set, "bags", "enabled", true)
		check("no combined bag frame in this client is skipped", ok)
		check("nothing was laid out without the frame", frame.layouts == 0)

		local second_frame, second_extra = stand_in(12)
		second_extra.C_Container = nil
		second_extra.C_Item = nil
		local second, _, second_loaded = load_bags(second_extra)
		second_loaded["Everlook_Bags"]()
		second.module.set("bags", "enabled", true)
		check("without the container API the item level option does not fail", pcall(second.module.set, "bags", "item_level", true))
		check("the layout still works without the container API", pcall(function() second_frame:UpdateItemLayout() end))
	end
end
