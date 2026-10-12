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
		env.IsLoggedIn = function() return true end
		local loaded = {}
		env.EventUtil = { ContinueOnAddOnLoaded = function(name, callback) loaded[name] = callback end }
		-- Every widget made through CreateFrame, so a test can find what the module added.
		local created = {}
		env.created = created
		env.CreateFrame = function(kind, _, parent)
			local widget = { kind = kind, parent = parent, events = {}, scripts = {}, hooks = {}, points = {}, textures = {}, shown = true, locked = false, level = 1 }
			function widget:RegisterEvent(event) self.events[event] = true end
			function widget:SetScript(name, callback) self.scripts[name] = callback end
			function widget:HookScript(name, callback) self.hooks[name] = callback end
			function widget:SetSize(width, height) self.width, self.height = width, height end
			function widget:SetPoint(...) self.points[#self.points + 1] = { ... } end
			function widget:ClearAllPoints() self.points = {} end
			function widget:EnableMouse(enabled) self.mouse = enabled end
			function widget:CreateFontString(_, layer, template)
				local text = { layer = layer, template = template, shown = true, points = {} }
				function text:SetPoint(...) self.points[#self.points + 1] = { ... } end
				function text:SetText(content) self.content = content end
				function text:ClearAllPoints() self.points = {} end
				function text:Show() self.shown = true end
				function text:Hide() self.shown = false end
				self.texts = self.texts or {}
				self.texts[#self.texts + 1] = text
				return text
			end
			function widget:SetAllPoints(target) self.all_points = target end
			function widget:SetFrameLevel(level) self.level = level end
			function widget:GetFrameLevel() return self.level end
			function widget:RegisterForClicks(...) self.clicks = { ... } end
			function widget:SetHighlightTexture(path) self.highlight = path end
			function widget:LockHighlight() self.locked = true end
			function widget:UnlockHighlight() self.locked = false end
			function widget:Show() self.shown = true end
			function widget:Hide() self.shown = false end
			function widget:IsShown() return self.shown end
			function widget:CreateTexture(_, layer, _, sublevel)
				local texture = { layer = layer, sublevel = sublevel, shown = true }
				function texture:SetAtlas(atlas, use_size) self.atlas, self.use_size = atlas, use_size end
				function texture:SetPoint(...) self.point = { ... } end
				function texture:SetHeight(height) self.height = height end
				function texture:Show() self.shown = true end
				function texture:Hide() self.shown = false end
				self.textures[#self.textures + 1] = texture
				return texture
			end
			created[#created + 1] = widget
			return widget
		end
		local tooltip = { lines = {}, shown = false }
		function tooltip:SetOwner(owner, anchor) self.owner, self.anchor, self.lines, self.shown = owner, anchor, {}, false end
		function tooltip:SetText(text) self.lines[#self.lines + 1] = text end
		function tooltip:AddLine(text) self.lines[#self.lines + 1] = text end
		function tooltip:SetBagItem(bag, slot) self.bag_item = { bag, slot }; return true end
		function tooltip:Show() self.shown = true end
		function tooltip:Hide() self.shown = false end
		env.GameTooltip = tooltip
		env.hooksecurefunc = function(target, method, callback)
			if type(target) == "string" then
				local original, hook = env[target], method
				env[target] = function(...)
					original(...)
					hook(...)
				end
				return
			end
			local original = target[method]
			target[method] = function(self, ...)
				original(self, ...)
				callback(self, ...)
			end
		end
		env.Enum = { ItemClass = {
			Consumable = 0, Weapon = 2, Gem = 3, Armor = 4, Reagent = 5, Tradegoods = 7, ItemEnhancement = 8,
			Recipe = 9, Questitem = 12, Key = 13, Miscellaneous = 15, Profession = 19,
		} }
		for key, value in pairs(extra or {}) do env[key] = value end
		local addon = {}
		-- world.lua shares the namespace as the global Everlook.
		env.Everlook = addon
		for _, file in ipairs({ "module", "bags_layout", "bags_item_level", "bags_junk", "bags_categories", "bags_pins", "bags_recent", "bags_folds", "bags_headers", "bags_sidebar", "bags_marker", "bags" }) do
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

		-- Sections read top down and slots left to right, but the grid is anchored at
		-- its bottom right corner, so everything is an offset up and to the left of it.
		local grouped = layout.grouped({
			{ key = "armory", title = "The Armory", count = 12 },
			{ key = "prep", title = "Adventure Prep", count = 0 },
			{ key = "junk", title = "Junk", count = 3 },
		}, 10)
		check("a section with no slots is left out", #grouped.sections == 2 and grouped.sections[1].key == "armory" and grouped.sections[2].key == "junk")
		check("a section keeps its title and count", grouped.sections[2].title == "Junk" and grouped.sections[2].count == 3)
		local armory, junk = grouped.sections[1], grouped.sections[2]
		check("the bottom section starts at the anchor with its first slot on the left of a full row",
			junk.positions[1].x == -9 * 42 and junk.positions[1].y == 0)
		check("slots in a row run to the right", junk.positions[3].x == -9 * 42 + 2 * 42 and junk.positions[3].y == 0)
		check("a header sits just above its section's top row", junk.header_y == 37 + 4)
		check("the section above clears the one below it, its header and a gap",
			armory.positions[11].x == -9 * 42 and armory.positions[11].y == 61 + 10)
		check("a section's first slot is on its top row", armory.positions[1].x == -9 * 42 and armory.positions[1].y == 61 + 10 + 42)
		check("a full top row ends at the right edge", armory.positions[10].x == 0 and armory.positions[10].y == 61 + 10 + 42)
		check("a short last row fills from the left", armory.positions[12].x == -9 * 42 + 42 and armory.positions[12].y == 61 + 10)
		check("the upper header sits above its two rows", armory.header_y == 71 + 79 + 4)
		check("the grouped grid is as tall as its sections, headers and gaps", grouped.height == 71 + 20 + 4 + 79)
		check("the grouped grid is as wide as the columns", grouped.width == 10 * ITEM + 9 * SPACING)
		check("a header is twenty pixels tall", layout.HEADER_HEIGHT == 20)

		local wide_grouped = layout.grouped({ { key = "misc", title = "Miscellaneous", count = 14 } }, 12)
		check("twelve columns put the first slot of two rows eleven slots left",
			wide_grouped.sections[1].positions[1].x == -11 * 42 and wide_grouped.sections[1].positions[1].y == 42)
		check("twelve columns put the thirteenth slot on the bottom row", wide_grouped.sections[1].positions[13].x == -11 * 42 and wide_grouped.sections[1].positions[13].y == 0)
		check("twelve columns make a wider grid", wide_grouped.width == 12 * ITEM + 11 * SPACING)
		check("a lone section is a header over its rows", wide_grouped.height == 20 + 4 + 79 and wide_grouped.sections[1].header_y == 79 + 4)
		check("no sections make an empty grid", #layout.grouped({}, 10).sections == 0 and layout.grouped({}, 10).height == 0)

		-- The frame is the stock size with the grid's share swapped for the grouped grid's.
		width, height = layout.grouped_size(400, 600, 15, grouped)
		check("grouping grows the frame by what headers and gaps add to the rows", width == 400 and height == 600 + 174 - 79)
		local wide_width, wide_height = layout.grouped_size(400, 600, 14, wide_grouped)
		check("twelve grouped columns widen the frame", wide_width == 400 + 84 and wide_height == 600 + (20 + 4 + 79) - 79)

		-- A list of sections on the left widens the frame and, when it has more rows than the grid, makes it taller.
		check("the list is 130 wide with a gap of 8 and its rows are 22 tall", layout.SIDEBAR_WIDTH == 130 and layout.SIDEBAR_GAP == 8 and layout.SIDEBAR_ROW_HEIGHT == 22)
		width, height = layout.grouped_size(400, 600, 15, grouped, 3)
		check("a list adds its width and its gap to the frame", width == 400 + 130 + 8)
		check("a short list leaves the height to the grid", height == 600 + 174 - 79)
		width, height = layout.grouped_size(400, 600, 15, grouped, 9)
		check("a long list sets the height", height == 600 + 9 * 22 - 79)
		width, height = layout.grouped_size(400, 600, 15, grouped, nil)
		check("no list adds nothing", width == 400 and height == 600 + 174 - 79)
		-- A folded section keeps its header and gives up its rows. A hidden one gives up everything.
		local folded = layout.grouped({
			{ key = "armory", title = "The Armory", count = 12 },
			{ key = "prep", title = "Adventure Prep", count = 5, state = "collapsed" },
			{ key = "junk", title = "Junk", count = 3, state = "hidden" },
			{ key = "free", title = "Free Space", count = 2 },
		}, 10)
		check("a hidden section is left out and a folded one stays", #folded.sections == 3 and folded.sections[2].key == "prep" and folded.sections[3].key == "free")
		check("a folded section has no slots to place but keeps its count and says it is folded",
			#folded.sections[2].positions == 0 and folded.sections[2].count == 5 and folded.sections[2].collapsed == true)
		check("a folded section's header sits at its bottom, and it is one header tall", folded.sections[2].header_y == 61 + 10 and folded.sections[3].collapsed ~= true)
		check("the section above a folded one clears the header, and a hidden section adds no gap",
			folded.sections[1].positions[11].y == 61 + 10 + 20 + 10 and folded.height == 61 + 10 + 20 + 10 + 103)
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

	-- Sorting items into sections: the presets, with junk ahead of the item's type.
	do
		local addon = load_bags()
		local categories = addon.bags_categories
		local keys, titles = {}, {}
		for _, section in ipairs(categories.SECTIONS) do
			keys[#keys + 1] = section.key
			titles[#titles + 1] = section.title
		end
		check("sections run from pinned down to free space, junk just above it", table.concat(keys, " ") == "pinned recent armory prep professions misc junk free")
		check("sections carry the preset names",
			table.concat(titles, "|") == "Pinned|Recent|The Armory|Adventure Prep|Professions|Miscellaneous|Junk|Free Space")
		check("a pinned item is in pinned whatever its type", categories.of(4, false, true, false) == "pinned" and categories.of(nil, false, true, true) == "pinned")
		check("a pinned item that is junk stays pinned", categories.of(4, true, true, false) == "pinned")
		check("a recent item is in recent whatever its type", categories.of(4, false, false, true) == "recent" and categories.of(nil, false, false, true) == "recent")
		check("junk stays junk though it is recent", categories.of(4, true, false, true) == "junk")
		check("anything but exactly true is not pinned or recent", categories.of(4, false, "yes", 1) == "armory")
		check("a weapon is in the armory", categories.of(2, false) == "armory")
		check("armor is in the armory", categories.of(4, false) == "armory")
		check("a consumable is in adventure prep", categories.of(0, false) == "prep")
		check("a gem is in adventure prep", categories.of(3, false) == "prep")
		check("an item enhancement is in adventure prep", categories.of(8, false) == "prep")
		for label, class_id in pairs({ ["trade goods"] = 7, ["a reagent"] = 5, ["a recipe"] = 9, ["a profession item"] = 19 }) do
			check(label .. " is in professions", categories.of(class_id, false) == "professions")
		end
		check("a quest item is miscellaneous", categories.of(12, false) == "misc")
		check("a key is miscellaneous", categories.of(13, false) == "misc")
		check("an item class nobody sorts is miscellaneous", categories.of(15, false) == "misc" and categories.of(99, false) == "misc")
		check("an item with no class is miscellaneous", categories.of(nil, false) == "misc")
		check("a class that is not a number is miscellaneous", categories.of("4", false) == "misc")
		check("junk beats the item's type", categories.of(4, true) == "junk" and categories.of(0, true) == "junk" and categories.of(nil, true) == "junk")
		check("anything but junk of exactly true is not junk", categories.of(4, nil) == "armory" and categories.of(4, "yes") == "armory" and categories.of(4, 1) == "armory")
		check("an empty slot is free space", categories.FREE == "free")
		local secret = {}
		local guarded = load_bags({ issecretvalue = function(value) return value == secret end }).bags_categories
		check("a secret class is miscellaneous", guarded.of(secret, false) == "misc")
		check("a secret class that is junk is still junk", guarded.of(secret, true) == "junk")
		local no_enum = load_bags({ Enum = false }).bags_categories
		check("without the item class names every item is miscellaneous", no_enum.of(4, false) == "misc" and no_enum.of(2, false) == "misc")
	end

	-- The pin store: item ids the player pinned, kept in the saved settings.
	do
		local addon, env = load_bags()
		local pins = addon.bags_pins
		local data = {}
		check("pinning an item says it is now pinned", pins.toggle(data, 6948) == true and pins.is_pinned(data, 6948))
		check("pinning it again unpins it and leaves nothing behind", pins.toggle(data, 6948) == false and not pins.is_pinned(data, 6948) and next(data) == nil)
		check("an item that was never pinned is not pinned", not pins.is_pinned(data, 2589))
		for label, bad in pairs({ none = false, zero = 0, negative = -5, fraction = 1.5, text = "6948", infinity = math.huge, table = {} }) do
			check("an id that is " .. label .. " pins nothing", pins.toggle(data, bad) == nil and next(data) == nil and not pins.is_pinned(data, bad))
		end
		check("a missing id pins nothing", pins.toggle(data, nil) == nil and not pins.is_pinned(data, nil))
		local secret = {}
		local guarded = load_bags({ issecretvalue = function(value) return value == secret end }).bags_pins
		check("a secret id pins nothing", guarded.toggle({}, secret) == nil and not guarded.is_pinned({ [secret] = true }, secret))
		local saved = pins.data()
		check("the pin table lives with the Bags settings and survives being asked for again",
			saved == env.EverlookDB.qol.bags.pinned and pins.data() == saved)
		check("pins and junk marks are kept apart", env.EverlookDB.qol.bags.junk == nil or env.EverlookDB.qol.bags.junk ~= saved)
	end

	-- The recent list: what arrived in the bags this session, from the item totals now and before.
	do
		local addon = load_bags()
		local recent = addon.bags_recent
		local list = recent.new()
		check("the first look at the bags is the baseline and makes nothing recent", list:observe({ [100] = 5, [200] = 1 }) == false and #list:items() == 0)
		check("an unchanged bag adds nothing", list:observe({ [100] = 5, [200] = 1 }) == false and #list:items() == 0)
		check("a bigger total puts the item first and says the list changed", list:observe({ [100] = 6, [200] = 1 }) == true and list:items()[1] == 100)
		check("an item that was not in the bags before is recent", list:observe({ [100] = 6, [200] = 1, [300] = 1 }) == true and list:items()[1] == 300 and list:items()[2] == 100)
		check("an item asks for its place in the list", list:rank(300) == 1 and list:rank(100) == 2 and list:rank(200) == nil)
		check("has says whether an item is in the list", list:has(100) and not list:has(200))
		check("a smaller total adds nothing", list:observe({ [100] = 2, [200] = 1, [300] = 1 }) == false and list:items()[1] == 300)
		check("a split stack of the same total adds nothing", list:observe({ [100] = 2, [200] = 1, [300] = 1 }) == false)
		check("an item that arrives again moves to the front", list:observe({ [100] = 3, [200] = 1, [300] = 1 }) == true and list:items()[1] == 100 and #list:items() == 2)
		local items = list:items()
		items[1] = 999
		check("the list handed out is a copy", list:items()[1] == 100)

		local crowd = recent.new()
		crowd:observe({})
		for id = 1, 13 do crowd:observe({ [id] = 1 }) ; crowd:observe({}) end
		check("the list holds twelve, the newest first", #crowd:items() == recent.LIMIT and recent.LIMIT == 12 and crowd:items()[1] == 13 and crowd:items()[12] == 2)

		local odd = recent.new()
		odd:observe({ [100] = 1 })
		check("a total that is not a table is ignored", odd:observe(nil) == false and odd:observe("bags") == false)
		check("a count that is not a number is ignored", odd:observe({ [100] = "2", [200] = true }) == false and #odd:items() == 0)
		local secret = {}
		local guard = load_bags({ issecretvalue = function(value) return value == secret end }).bags_recent.new()
		guard:observe({ [100] = 1 })
		check("a secret count is ignored", guard:observe({ [100] = secret }) == false and #guard:items() == 0)
		check("a secret id is ignored", guard:observe({ [secret] = 4 }) == false and #guard:items() == 0)
		check("an id that is not a whole positive number is ignored", guard:observe({ [0] = 1, [-3] = 1, [1.5] = 1 }) == false and #guard:items() == 0)
	end

	-- The fold store: section keys the player folded, kept in the saved settings.
	do
		local addon, env = load_bags()
		local folds = addon.bags_folds
		local data = {}
		check("folding a section says it is folded", folds.toggle(data, "junk") == true and folds.is_folded(data, "junk"))
		check("folding it again opens it and leaves nothing behind", folds.toggle(data, "junk") == false and not folds.is_folded(data, "junk") and next(data) == nil)
		check("a section never folded is open", not folds.is_folded(data, "misc"))
		for label, bad in pairs({ none = false, number = 4, empty = "", table = {}, long = string.rep("x", 40) }) do
			check("a key that is " .. label .. " folds nothing", folds.toggle(data, bad) == nil and next(data) == nil and not folds.is_folded(data, bad))
		end
		check("a missing key folds nothing", folds.toggle(data, nil) == nil)
		local secret = {}
		local guarded = load_bags({ issecretvalue = function(value) return value == secret end }).bags_folds
		check("a secret key folds nothing", guarded.toggle({}, secret) == nil)
		local saved = folds.data()
		check("the fold table lives with the Bags settings and survives being asked for again", saved == env.EverlookDB.qol.bags.folded and folds.data() == saved)
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
		local scale = found and found.options.scale
		check("window scale starts at a hundred percent and runs from seventy to a hundred and ten", scale and scale.default == 100 and scale.min == 70 and scale.max == 110 and scale.step == 5)
		check("pinned items start off", found and found.options.pins and found.options.pins.default == false)
		check("recent items start off", found and found.options.recent and found.options.recent.default == false)
		check("it listens for the world loading and for the bags changing", found and found.events and found.events[1] == "PLAYER_ENTERING_WORLD" and found.events[2] == "BAG_UPDATE_DELAYED")
	end

	-- Applying and undoing, on a stand-in for the stock frame.
	local function stand_in(slot_total, gear)
		local points_log = {}
		local frame = { MoneyFrame = { name = "money" }, CloseButton = { name = "close" }, width = 400, height = 600, buttons = {}, layouts = 0, hooks = {} }
		function frame:HookScript(name, callback) self.hooks[name] = callback end
		function frame:GetFrameLevel() return 5 end
		function frame:Hide() self.shown_flag = false; if self.hooks.OnHide then self.hooks.OnHide(self) end end
		function frame:SetSize(width, height) self.width, self.height = width, height end
		function frame:SetScale(scale) self.scale = scale end
		function frame:GetScale() return self.scale end
		function frame:GetWidth() return self.width end
		function frame:GetHeight() return self.height end
		function frame:IsShown() return true end
		function frame:EnumerateValidItems() return ipairs(self.buttons) end
		for index = 1, slot_total do
			local button = { slot = index, points = {}, texts = {} }
			function button:GetBagID() return 0 end
			function button:GetID() return self.slot end
			function button:IsExtended() return false end
			function button:IsMouseOver() return self.mouse_over == true end
			function button:SetAlpha(alpha) self.alpha = alpha end
			function button:GetAlpha() return self.alpha or 1 end
			function button:EnableMouse(enabled) self.mouse = enabled end
			function button:HookScript(name, callback) self.hooks = self.hooks or {}; self.hooks[name] = callback end
			function button:GetFrameLevel() return 10 end
			function button:CreateTexture(_, layer, _, sublevel)
				local texture = { layer = layer, sublevel = sublevel, shown = true }
				function texture:SetAtlas(atlas, use_size) self.atlas, self.use_size = atlas, use_size end
				function texture:SetPoint(...) self.point = { ... } end
				function texture:Show() self.shown = true end
				function texture:Hide() self.shown = false end
				self.textures = self.textures or {}
				self.textures[#self.textures + 1] = texture
				return texture
			end
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
			if entry then info[index] = { itemID = 1000 + index, hyperlink = "link" .. index, quality = entry.quality, class = entry.class, level = entry.level, stackCount = 1 } end
		end
		frame.scale = 0.9
		local env_extra = {
			ContainerFrameCombinedBags = frame,
			-- What stock does on opening: it sets the scale that fits the screen.
			UpdateContainerFrameAnchors = function() frame.scale = frame.stock_scale or 0.9 end,
			C_Container = {
				GetContainerItemInfo = function(bag, slot) if bag == 0 then return info[slot] end end,
				GetContainerNumSlots = function(bag) return bag == 0 and slot_total or 0 end,
			},
			NUM_BAG_SLOTS = 4,
			C_Item = {
				GetItemInfoInstant = function(item_id) return item_id, "", "", "", 0, info[item_id - 1000].class, 0 end,
				GetDetailedItemLevelInfo = function(link) return info[tonumber(link:match("%d+"))].level end,
			},
			ColorManager = { GetColorDataForItemQuality = function(quality) return { r = quality / 10, g = 0.5, b = 0.25 } end },
			C_Texture = { GetAtlasInfo = function(atlas)
				if atlas == "Options_HorizontalDivider" then return { width = 330, height = 3 } end
				if atlas == "campaign_headericon_open" or atlas == "campaign_headericon_closed" then return { width = 14, height = 14 } end
			end },
		}
		return frame, env_extra, points_log, info
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

	-- Group by type: the slots sit under headers, on a stand-in for the stock frame.
	local function group_setup(slot_total, entries, options)
		local gear = {}
		for slot, entry in pairs(entries) do gear[slot] = entry end
		local frame, extra, _, info = stand_in(slot_total, gear)
		for key, value in pairs(options or {}) do extra[key] = value end
		local addon, env, loaded = load_bags(extra)
		loaded["Everlook_Bags"]()
		addon.module.set("bags", "enabled", true)
		return addon, env, frame, info
	end
	local function headers_of(env, frame)
		local found = {}
		for _, widget in ipairs(env.created) do
			if widget.parent == frame and widget.kind == "Button" and widget.texts then found[#found + 1] = widget end
		end
		return found
	end
	local function header_named(env, frame, title)
		for _, widget in ipairs(headers_of(env, frame)) do
			if widget.texts and widget.texts[1].content == title then return widget end
		end
	end
	local function at(button, x, y)
		local point = button.points[1]
		return point ~= nil and point[1] == "BOTTOMRIGHT" and point[4] == x and point[5] == y + 4
	end
	do
		-- Six slots: armor, a potion, a weapon, a grey, and two empty.
		local entries = {
			{ class = 4, quality = 4, level = 270 }, { class = 0, quality = 1, level = 1 }, { class = 2, quality = 3, level = 200 },
			{ class = 15, quality = 0, level = 1 },
		}
		local addon, env, frame, info = group_setup(6, entries)
		check("group by type starts off", (function()
			for _, module in ipairs(addon.module.modules) do
				if module.id == "bags" then return module.options.group and module.options.group.default == false end
			end
		end)())
		frame:UpdateItemLayout()
		check("with grouping off the slots are in the stock grid and no header exists", at(frame.buttons[2], -42, 0) and #headers_of(env, frame) == 0)

		addon.module.set("bags", "group", true)
		check("the armor and the weapon share the top section, left to right", at(frame.buttons[1], -378, 213) and at(frame.buttons[3], -336, 213))
		check("the potion sits in adventure prep below it", at(frame.buttons[2], -378, 142))
		check("the grey item is in junk, though the marker is off", at(frame.buttons[4], -378, 71))
		check("the empty slots are free space at the bottom", at(frame.buttons[5], -378, 0) and at(frame.buttons[6], -336, 0))
		check("slots keep the stock anchor frame and corner", frame.buttons[1].points[1][2] == frame.MoneyFrame and frame.buttons[1].points[1][3] == "TOPRIGHT")
		check("a button has one anchor", #frame.buttons[1].points == 1)
		check("the frame grows by the headers and gaps the sections add", frame.height == 600 + 274 - 37 and frame.width == 400)
		local shown = {}
		for _, header in ipairs(headers_of(env, frame)) do
			if header.shown then shown[#shown + 1] = header.texts[1].content .. " " .. header.texts[2].content end
		end
		table.sort(shown)
		check("a header per section that has slots, with its count",
			table.concat(shown, "|") == "Adventure Prep 1|Free Space 2|Junk 1|The Armory 2")
		local armory = header_named(env, frame, "The Armory")
		local point = armory.points[1]
		check("a header sits above its section, over the grid's width",
			point[1] == "BOTTOMRIGHT" and point[2] == frame.MoneyFrame and point[3] == "TOPRIGHT" and point[4] == 0 and point[5] == 4 + 213 + 37 + 4
			and armory.width == 415 and armory.height == 20)
		check("a header lets mouse clicks through to the slots while sections cannot be folded", armory.mouse == false)
		check("the title is in the game's gold heading font", armory.texts[1].template == "GameFontNormal")
		check("the count is in the game's small highlight font", armory.texts[2].template == "GameFontHighlightSmall")
		check("the rule under a header is the game's divider", armory.textures[1] and armory.textures[1].atlas == "Options_HorizontalDivider" and armory.textures[1].height == 3)

		-- Things change in the bag: a weapon lands in the first empty slot.
		info[5] = { itemID = 1005, hyperlink = "link5", quality = 3, class = 2, level = 200 }
		frame:UpdateItems()
		check("an item that lands in an empty slot joins its section on the next refresh", at(frame.buttons[5], -294, 213) and at(frame.buttons[6], -378, 0))
		check("the header counts follow", header_named(env, frame, "The Armory").texts[2].content == "3" and header_named(env, frame, "Free Space").texts[2].content == "1")
		check("a section that fills its slots away loses its header", (function()
			info[2] = nil
			frame:UpdateItems()
			return not header_named(env, frame, "Adventure Prep").shown
		end)())
		check("a refresh does not pile anchors on a button", #frame.buttons[1].points == 1)

		-- The game lays the grid out again: grouping is put back over it.
		frame:UpdateItemLayout()
		check("a layout pass by the game is grouped again, over the grid the game drew",
			at(frame.buttons[1], -378, 142) and at(frame.buttons[2], -378, 0) and frame.height == 600 + 203 - 37 and #frame.buttons[1].points == 1)

		-- Turning it off at ten columns must put stock's grid back, though the columns are stock's.
		addon.module.set("bags", "group", false)
		check("turning grouping off puts every slot where stock draws it", at(frame.buttons[6], -5 * 42, 0) and at(frame.buttons[2], -42, 0))
		check("turning grouping off restores the stock size", frame.width == 400 and frame.height == 600)
		check("turning grouping off hides every header", (function()
			for _, header in ipairs(headers_of(env, frame)) do if header.shown then return false end end
			return true
		end)())
		addon.module.set("bags", "group", true)
		check("turning it back on groups again and shows the headers", at(frame.buttons[1], -378, 142) and header_named(env, frame, "The Armory").shown)
		addon.module.set("bags", "enabled", false)
		check("disabling the module puts the grid and size back and hides the headers",
			at(frame.buttons[2], -42, 0) and frame.height == 600 and not header_named(env, frame, "The Armory").shown)
		frame:UpdateItemLayout()
		check("a disabled module leaves the layout the game draws", at(frame.buttons[2], -42, 0) and frame.height == 600)
	end

	do
		-- A slot under the pointer stays put: using or selling an item must not slide the next one under it.
		local entries = { { class = 4, quality = 4, level = 270 }, { class = 4, quality = 4, level = 270 }, { class = 0, quality = 1, level = 1 } }
		local addon, env, frame, info = group_setup(4, entries)
		addon.module.set("bags", "group", true)
		local function watcher_of()
			for _, widget in ipairs(env.created) do
				if widget.parent == nil and widget.kind == "Frame" and widget.scripts.OnUpdate then return widget end
			end
		end
		check("armor fills the top row from the left", at(frame.buttons[1], -378, 142) and at(frame.buttons[2], -336, 142))
		check("nothing watches the pointer until a refresh has to wait", watcher_of() == nil)
		frame.buttons[1].mouse_over = true
		info[1] = nil
		frame:UpdateItems()
		check("a refresh with the pointer on a slot leaves every slot where it is", at(frame.buttons[1], -378, 142) and at(frame.buttons[2], -336, 142))
		local watcher = watcher_of()
		check("something now waits for the pointer to leave the slots", watcher ~= nil and watcher.shown and watcher.scripts.OnUpdate ~= nil)
		watcher.scripts.OnUpdate(watcher)
		check("it keeps waiting while the pointer is still on a slot", at(frame.buttons[2], -336, 142) and watcher.shown)
		frame.buttons[1].mouse_over = false
		watcher.scripts.OnUpdate(watcher)
		check("the slots are sorted once the pointer is off them", at(frame.buttons[2], -378, 142) and at(frame.buttons[3], -378, 71) and at(frame.buttons[1], -378, 0))
		check("and it stops waiting", not watcher.shown)

		-- Off the slots, say on the sort button, a refresh does not wait.
		info[2] = nil
		frame:UpdateItems()
		check("with the pointer off the slots a refresh sorts at once", at(frame.buttons[3], -378, 71) and at(frame.buttons[2], -336, 0) and not watcher.shown)

		-- Waiting must not outlive grouping.
		info[2] = { itemID = 1002, hyperlink = "link2", quality = 4, class = 4, level = 270 }
		frame.buttons[3].mouse_over = true
		frame:UpdateItems()
		check("the slots wait again under the pointer", watcher.shown)
		addon.module.set("bags", "group", false)
		frame.buttons[3].mouse_over = false
		watcher.scripts.OnUpdate(watcher)
		check("a wait that ends after grouping was turned off leaves the stock grid alone", at(frame.buttons[2], -42, 0) and at(frame.buttons[4], -126, 0))
	end
	do
		-- The section list: a click on a row shows that section alone.
		local entries = {
			{ class = 4, quality = 4, level = 270 }, { class = 4, quality = 4, level = 270 }, { class = 0, quality = 1, level = 1 },
			{ class = 15, quality = 0, level = 1 },
		}
		local addon, env, frame, info = group_setup(6, entries)
		addon.module.set("bags", "group", true)
		local function list_of()
			for _, widget in ipairs(env.created) do
				if widget.parent == frame and widget.kind == "Frame" then return widget end
			end
		end
		local function rows_of(list)
			local found = {}
			for _, widget in ipairs(env.created) do
				if widget.parent == list and widget.kind == "Button" then found[#found + 1] = widget end
			end
			return found
		end
		check("the section list starts off", (function()
			for _, module in ipairs(addon.module.modules) do
				if module.id == "bags" then return module.options.sidebar and module.options.sidebar.default == false end
			end
		end)())
		check("with the list off there is none and the frame is as wide as before", list_of() == nil and frame.width == 400)
		addon.module.set("bags", "sidebar", true)
		local list = list_of()
		check("the list is a child of the bag, left of the grid and level with its bottom",
			list ~= nil and list.points[1][1] == "BOTTOMRIGHT" and list.points[1][2] == frame.MoneyFrame and list.points[1][3] == "TOPRIGHT"
			and list.points[1][4] == -(415 + 8) and list.points[1][5] == 4)
		check("the list is 130 wide and as tall as its rows", list.width == 130 and list.height == 5 * 22)
		check("the list does not take the mouse itself", list.mouse == false)
		local rows = rows_of(list)
		local names = {}
		for _, row in ipairs(rows) do names[#names + 1] = row.texts[1].content .. " " .. row.texts[2].content end
		check("a row for everything and one per section that has slots, with counts",
			table.concat(names, "|") == "All Items 4|The Armory 2|Adventure Prep 1|Junk 1|Free Space 2")
		check("rows stack from the top of the list", rows[1].points[1][1] == "TOPLEFT" and rows[1].points[1][5] == 0 and rows[3].points[1][5] == -2 * 22)
		check("the row for everything is the one marked", rows[1].locked == true and rows[3].locked == false)
		check("the frame is wider by the list and its gap", frame.width == 400 + 138 and frame.height == 600 + 274 - 37)
		check("grouping itself is unchanged", at(frame.buttons[1], -378, 213) and at(frame.buttons[3], -378, 142))

		rows[3].scripts.OnClick(rows[3])
		check("a click on a row shows that section alone, at the bottom of the grid", at(frame.buttons[3], -378, 0))
		check("every other slot is parked, clear and not clickable", (function()
			for _, index in ipairs({ 1, 2, 4, 5, 6 }) do
				local button = frame.buttons[index]
				if not (at(button, 0, 0) and button.alpha == 0 and button.mouse == false) then return false end
			end
			return true
		end)())
		check("only that section keeps its header", header_named(env, frame, "Adventure Prep").shown and not header_named(env, frame, "The Armory").shown
			and not header_named(env, frame, "Junk").shown and not header_named(env, frame, "Free Space").shown)
		check("the frame is as tall as the list needs", frame.height == 600 + 5 * 22 - 37)
		check("the chosen row is marked and the others are not", rows[3].locked == true and rows[1].locked == false)
		check("the counts do not change", rows[2].texts[2].content == "2" and rows[1].texts[2].content == "4")

		rows[3].scripts.OnClick(rows[3])
		check("a click on the chosen row shows everything again", at(frame.buttons[3], -378, 142) and at(frame.buttons[1], -378, 213) and frame.buttons[1].alpha == 1 and rows[1].locked == true)
		rows[2].scripts.OnClick(rows[2])
		rows[1].scripts.OnClick(rows[1])
		check("a click on the row for everything shows everything", at(frame.buttons[1], -378, 213) and frame.buttons[2].mouse == true)

		-- A section that empties out while it is the one shown: everything is shown again.
		rows[3].scripts.OnClick(rows[3])
		info[3] = nil
		frame:UpdateItems()
		check("the section shown alone empties and everything comes back", at(frame.buttons[1], -378, 142) and frame.buttons[1].alpha == 1 and rows[1].locked == true)

		-- Folding does not hide the section shown alone.
		info[3] = { itemID = 1003, hyperlink = "link3", quality = 1, class = 0, level = 1, stackCount = 1 }
		addon.module.set("bags", "fold", true)
		env.EverlookDB.qol.bags.folded = { prep = true }
		frame:UpdateItems()
		rows = rows_of(list)
		rows[3].scripts.OnClick(rows[3])
		check("the section shown alone is open though it is folded", at(frame.buttons[3], -378, 0) and frame.buttons[3].alpha == 1)
		rows[1].scripts.OnClick(rows[1])
		addon.module.set("bags", "fold", false)

		rows[3].scripts.OnClick(rows[3])
		addon.module.set("bags", "sidebar", false)
		check("turning the list off hides it, shows everything and shrinks the frame", not list.shown and at(frame.buttons[1], -378, 213) and frame.buttons[1].alpha == 1 and frame.width == 400)
		addon.module.set("bags", "sidebar", true)
		check("turning it back on starts with everything shown", list.shown and at(frame.buttons[1], -378, 213) and rows[1].locked == true)
		addon.module.set("bags", "group", false)
		check("turning grouping off hides the list and brings the stock grid back", not list.shown and frame.width == 400 and at(frame.buttons[2], -42, 0))
		addon.module.set("bags", "group", true)
		addon.module.set("bags", "enabled", false)
		check("turning the module off hides the list", not list.shown and frame.width == 400)
	end
	do
		-- Window scale: a share of the size the game gives the bag.
		local frame, extra = stand_in(4)
		local addon, env, loaded = load_bags(extra)
		loaded["Everlook_Bags"]()
		addon.module.set("bags", "enabled", true)
		check("at a hundred percent the game's scale is left alone", frame.scale == 0.9)
		addon.module.set("bags", "scale", 80)
		check("eighty percent makes the open bag eighty percent of the game's scale", math.abs(frame.scale - 0.72) < 1e-9)
		env.UpdateContainerFrameAnchors()
		check("when the game sets its scale again, ours goes over it, without piling up", math.abs(frame.scale - 0.72) < 1e-9)
		frame.stock_scale = 0.5
		env.UpdateContainerFrameAnchors()
		check("a different scale from the game is taken as the new base", math.abs(frame.scale - 0.4) < 1e-9)
		frame.stock_scale = nil
		env.UpdateContainerFrameAnchors()
		addon.module.set("bags", "scale", 110)
		check("a new choice is taken from the game's scale, not the last one", math.abs(frame.scale - 0.99) < 1e-9)
		addon.module.set("bags", "scale", 100)
		check("a hundred percent gives the game's scale back", frame.scale == 0.9)
		addon.module.set("bags", "scale", 70)
		addon.module.set("bags", "enabled", false)
		check("turning the module off gives the game's scale back", frame.scale == 0.9)
		env.UpdateContainerFrameAnchors()
		check("a disabled module leaves what the game sets", frame.scale == 0.9)
	end
	do
		local frame, extra = stand_in(4)
		extra.UpdateContainerFrameAnchors = nil
		local addon, _, loaded = load_bags(extra)
		loaded["Everlook_Bags"]()
		addon.module.set("bags", "enabled", true)
		check("without the game's anchoring function a scale choice does not fail", pcall(addon.module.set, "bags", "scale", 80))
	end
	do
		-- Folding: a click on a header folds its section down to the header.
		local entries = {
			{ class = 4, quality = 4, level = 270 }, { class = 4, quality = 4, level = 270 }, { class = 0, quality = 1, level = 1 },
			{ class = 15, quality = 0, level = 1 },
		}
		local addon, env, frame = group_setup(6, entries)
		addon.module.set("bags", "group", true)
		local prep = header_named(env, frame, "Adventure Prep")
		check("fold sections starts off", (function()
			for _, module in ipairs(addon.module.modules) do
				if module.id == "bags" then return module.options.fold and module.options.fold.default == false end
			end
		end)())
		check("without the option a header is not clickable and shows no arrow", prep.mouse == false and #(prep.textures or {}) <= 1)
		addon.module.set("bags", "fold", true)
		check("with the option a header takes clicks", prep.mouse == true and prep.scripts.OnClick ~= nil)
		check("each header shows the open arrow while its section is open", (function()
			local arrow
			for _, texture in ipairs(prep.textures) do if texture.atlas == "campaign_headericon_open" then arrow = texture end end
			return arrow ~= nil and arrow.shown
		end)())
		frame.buttons[3].alpha = 0.6
		prep.scripts.OnClick(prep)
		check("a click folds the section and the choice is saved", env.EverlookDB.qol.bags.folded.prep == true)
		check("the folded slot is parked at the grid corner, clear and not clickable",
			at(frame.buttons[3], 0, 0) and frame.buttons[3].alpha == 0 and frame.buttons[3].mouse == false)
		check("the sections below and above close up, the folded header between them",
			at(frame.buttons[5], -378, 0) and at(frame.buttons[4], -378, 71) and at(frame.buttons[1], -378, 172))
		check("the frame is as tall as the folded sections", frame.height == 600 + 233 - 37)
		check("the folded header still shows its count and the closed arrow", prep.shown and prep.texts[2].content == "1" and (function()
			for _, texture in ipairs(prep.textures) do if texture.atlas == "campaign_headericon_closed" and texture.shown then return true end end
		end)())
		check("the folded header sits at the bottom of its place", prep.points[1][5] == 4 + 142)
		prep.scripts.OnClick(prep)
		check("a second click opens it and the slot is back, solid and clickable",
			at(frame.buttons[3], -378, 142) and frame.buttons[3].alpha == 0.6 and frame.buttons[3].mouse == true and next(env.EverlookDB.qol.bags.folded) == nil)

		prep.scripts.OnClick(prep)
		addon.module.set("bags", "fold", false)
		check("turning folding off opens every section, keeps the fold and stops the header taking clicks",
			at(frame.buttons[3], -378, 142) and frame.buttons[3].alpha == 0.6 and env.EverlookDB.qol.bags.folded.prep == true and prep.mouse == false)
		prep.scripts.OnClick(prep)
		check("a click that still arrives with folding off does nothing", env.EverlookDB.qol.bags.folded.prep == true)
		addon.module.set("bags", "fold", true)
		check("turning it back on brings the fold back", at(frame.buttons[3], 0, 0))
		addon.module.set("bags", "group", false)
		check("turning grouping off brings a folded slot back to the stock grid", at(frame.buttons[3], -84, 0) and frame.buttons[3].alpha == 0.6 and frame.buttons[3].mouse == true)
		addon.module.set("bags", "group", true)
		addon.module.set("bags", "enabled", false)
		check("turning the module off brings it back too", at(frame.buttons[3], -84, 0) and frame.buttons[3].alpha == 0.6)
	end
	do
		-- Pinned items: a middle-click pins the item, and every copy of it sits in the Pinned section.
		local entries = { { class = 4, quality = 4, level = 270 }, { class = 4, quality = 4, level = 270 }, { class = 0, quality = 1, level = 1 } }
		local addon, env, frame = group_setup(5, entries)
		local function middle_click(button) button.hooks.OnMouseUp(button, "MiddleButton") end
		addon.module.set("bags", "group", true)
		check("with pins off no slot listens for a middle-click", frame.buttons[3].hooks == nil)
		addon.module.set("bags", "pins", true)
		check("with pins on every slot listens", frame.buttons[3].hooks and frame.buttons[3].hooks.OnMouseUp ~= nil and frame.buttons[1].hooks.OnMouseUp ~= nil)
		local first_hook = frame.buttons[3].hooks.OnMouseUp
		addon.module.set("bags", "columns", 12)
		addon.module.set("bags", "columns", 10)
		frame:UpdateItems()
		check("a slot is hooked once however often the bag refreshes", frame.buttons[3].hooks.OnMouseUp == first_hook)
		check("nothing is pinned to begin with", #(function() local found = {} for _, h in ipairs(headers_of(env, frame)) do if h.shown and h.texts[1].content == "Pinned" then found[#found + 1] = h end end return found end)() == 0)

		frame.buttons[3].mouse_over = true
		frame.buttons[3].hooks.OnMouseUp(frame.buttons[3], "LeftButton")
		check("a left click pins nothing", next(env.EverlookDB.qol.bags or {}) == nil or next(env.EverlookDB.qol.bags.pinned or {}) == nil)
		middle_click(frame.buttons[3])
		check("a middle-click pins the item and it is saved by item id", env.EverlookDB.qol.bags.pinned[1003] == true)
		check("the pinned item moves to the top section at once, though the pointer is on it",
			at(frame.buttons[3], -378, 142) and at(frame.buttons[1], -378, 71) and at(frame.buttons[2], -336, 71) and at(frame.buttons[4], -378, 0))
		check("the pinned section has a header and a count", header_named(env, frame, "Pinned").shown and header_named(env, frame, "Pinned").texts[2].content == "1")
		check("the section the item left loses its header", not header_named(env, frame, "Adventure Prep").shown)
		frame.buttons[3].mouse_over = false
		middle_click(frame.buttons[3])
		check("a second middle-click unpins it and it goes back to its type", at(frame.buttons[3], -378, 71) and at(frame.buttons[1], -378, 142) and next(env.EverlookDB.qol.bags.pinned) == nil)

		middle_click(frame.buttons[3])
		addon.module.set("bags", "pins", false)
		check("turning pins off puts the item back under its type and keeps the pin", at(frame.buttons[3], -378, 71) and env.EverlookDB.qol.bags.pinned[1003] == true)
		middle_click(frame.buttons[3])
		check("with pins off a middle-click does nothing", env.EverlookDB.qol.bags.pinned[1003] == true and at(frame.buttons[3], -378, 71))
		addon.module.set("bags", "pins", true)
		check("turning pins back on brings the pin back", at(frame.buttons[3], -378, 142))
		addon.module.set("bags", "group", false)
		middle_click(frame.buttons[3])
		check("with grouping off a middle-click does nothing", env.EverlookDB.qol.bags.pinned[1003] == true and at(frame.buttons[3], -84, 0))
		addon.module.set("bags", "group", true)
		addon.module.set("bags", "enabled", false)
		middle_click(frame.buttons[2])
		check("with Bags off a middle-click does nothing", env.EverlookDB.qol.bags.pinned[1002] == nil)
	end
	do
		-- Recent items: what arrived in the bags this session.
		local entries = { { class = 4, quality = 4, level = 270 }, { class = 4, quality = 4, level = 270 }, { class = 0, quality = 1, level = 1 } }
		local addon, env, frame, info = group_setup(6, entries)
		local function bags_changed()
			for _, widget in ipairs(env.created) do
				if widget.parent == nil and widget.kind == "Frame" and widget.scripts.OnEvent then widget.scripts.OnEvent(widget, "BAG_UPDATE_DELAYED") return end
			end
			error("no module frame")
		end
		addon.module.set("bags", "group", true)
		addon.module.set("bags", "recent", true)
		check("what was in the bags when recent turned on is not recent", at(frame.buttons[1], -378, 142) and at(frame.buttons[3], -378, 71))
		info[4] = { itemID = 1004, hyperlink = "link4", quality = 3, class = 2, level = 200, stackCount = 1 }
		bags_changed()
		check("a new item goes to the recent section at the top", at(frame.buttons[4], -378, 213) and at(frame.buttons[1], -378, 142) and at(frame.buttons[3], -378, 71) and at(frame.buttons[5], -378, 0))
		check("the recent section has a header and a count", header_named(env, frame, "Recent").shown and header_named(env, frame, "Recent").texts[2].content == "1")
		check("the list is not saved", type(env.EverlookDB.qol.bags.recent) ~= "table")

		info[5] = { itemID = 1005, hyperlink = "link5", quality = 0, class = 15, level = 1, stackCount = 1 }
		bags_changed()
		check("a grey arrival is junk, not recent", at(frame.buttons[5], -378, 71) and at(frame.buttons[4], -378, 284) and header_named(env, frame, "Junk").shown)
		info[6] = { itemID = 1006, hyperlink = "link6", quality = 4, class = 4, level = 280, stackCount = 1 }
		bags_changed()
		check("the newest arrival comes first in the recent section", at(frame.buttons[6], -378, 213) and at(frame.buttons[4], -336, 213))
		check("an item that is still there but did not arrive stays under its type", at(frame.buttons[1], -378, 142) and at(frame.buttons[3], -378, 71))

		addon.module.set("bags", "pins", true)
		frame.buttons[6].hooks.OnMouseUp(frame.buttons[6], "MiddleButton")
		check("a pinned item is pinned, not recent", at(frame.buttons[6], -378, 284) and at(frame.buttons[4], -378, 213))

		addon.module.set("bags", "recent", false)
		check("turning recent off puts its items under their types", at(frame.buttons[4], -294, 142) and at(frame.buttons[6], -378, 213))
		check("with recent off a change in the bags does not fail", pcall(bags_changed) and at(frame.buttons[4], -294, 142))
		addon.module.set("bags", "recent", true)
		check("turning recent back on starts a new list, so nothing is recent yet", at(frame.buttons[4], -294, 142))
	end
	do
		-- At login the bags are not filled when Everlook loads: what is in them then was always there.
		local entries = {}
		local addon, env, frame, info = group_setup(4, entries, { IsLoggedIn = function() return false end })
		local function fire(event)
			for _, widget in ipairs(env.created) do
				if widget.parent == nil and widget.kind == "Frame" and widget.scripts.OnEvent then widget.scripts.OnEvent(widget, event) end
			end
		end
		addon.module.set("bags", "group", true)
		addon.module.set("bags", "recent", true)
		-- The game fills the bags after Everlook has loaded.
		info[1] = { itemID = 1001, hyperlink = "link1", quality = 4, class = 4, level = 270, stackCount = 1 }
		info[2] = { itemID = 1002, hyperlink = "link2", quality = 4, class = 4, level = 270, stackCount = 1 }
		fire("BAG_UPDATE_DELAYED")
		check("a change before the world is entered is not looked at", not header_named(env, frame, "Recent"))
		fire("PLAYER_ENTERING_WORLD")
		fire("BAG_UPDATE_DELAYED")
		check("what was in the bags on entering the world is not recent", not header_named(env, frame, "Recent"))
		info[3] = { itemID = 1003, hyperlink = "link3", quality = 3, class = 2, level = 200, stackCount = 1 }
		fire("BAG_UPDATE_DELAYED")
		check("an arrival after that is recent", header_named(env, frame, "Recent") and header_named(env, frame, "Recent").shown)
		fire("PLAYER_ENTERING_WORLD")
		frame:UpdateItems()
		check("a later loading screen keeps the list", header_named(env, frame, "Recent").shown and header_named(env, frame, "Recent").texts[2].content == "1")
	end
	do
		-- What arrives while recent is off is not recent when it is turned on.
		local entries = { { class = 4, quality = 4, level = 270 }, { class = 4, quality = 4, level = 270 } }
		local addon, env, frame, info = group_setup(3, entries)
		addon.module.set("bags", "group", true)
		local function bags_changed()
			for _, widget in ipairs(env.created) do
				if widget.parent == nil and widget.kind == "Frame" and widget.scripts.OnEvent then widget.scripts.OnEvent(widget, "BAG_UPDATE_DELAYED") end
			end
		end
		bags_changed()
		info[3] = { itemID = 1003, hyperlink = "link3", quality = 3, class = 2, level = 200, stackCount = 1 }
		bags_changed()
		addon.module.set("bags", "recent", true)
		check("an arrival while recent was off is not recent once it is on", at(frame.buttons[3], -294, 0) and not header_named(env, frame, "Recent"))
	end
	do
		-- Junk marks decide the section, and a mark made in mark mode waits for the mode to end.
		local entries = { { class = 4, quality = 4, level = 270 }, { class = 0, quality = 1, level = 1 }, { class = 0, quality = 1, level = 1 } }
		local addon, env, frame = group_setup(3, entries)
		addon.module.set("bags", "group", true)
		addon.bags_junk.toggle(addon.bags_junk.data(), 1002)
		frame:UpdateItems()
		check("a mark does nothing to the sections while the marker is off",
			at(frame.buttons[2], -378, 0) and at(frame.buttons[3], -336, 0) and at(frame.buttons[1], -378, 71))
		addon.module.set("bags", "junk_marker", true)
		check("a marked item moves into junk, below the sections of its type", at(frame.buttons[2], -378, 0) and at(frame.buttons[3], -378, 71) and at(frame.buttons[1], -378, 142))

		local coin
		for _, widget in ipairs(env.created) do if widget.parent == frame and widget.kind == "Button" and not widget.texts then coin = widget end end
		coin.scripts.OnClick(coin)
		local overlay
		for _, widget in ipairs(env.created) do if widget.parent == frame.buttons[3] and widget.kind == "Button" then overlay = widget end end
		overlay.scripts.OnClick(overlay)
		check("a mark made in mark mode does not move the slot under the cursor", at(frame.buttons[3], -378, 71) and addon.bags.is_junk(1003))
		frame:UpdateItems()
		check("a refresh during mark mode leaves the slots where they are", at(frame.buttons[3], -378, 71))
		coin.scripts.OnClick(coin)
		check("ending mark mode groups the new mark", at(frame.buttons[2], -378, 0) and at(frame.buttons[3], -336, 0) and at(frame.buttons[1], -378, 71))
	end
	do
		-- Wider than stock: the grouped grid is as wide as the columns.
		local entries = { { class = 4, quality = 4, level = 270 }, { class = 4, quality = 4, level = 270 } }
		local addon, env, frame = group_setup(14, entries)
		addon.module.set("bags", "columns", 12)
		addon.module.set("bags", "group", true)
		check("free slots fill a row of twelve", at(frame.buttons[3], -11 * 42, 0) and at(frame.buttons[14], 0, 0))
		check("grouped slots follow the column count", at(frame.buttons[1], -11 * 42, 61 + 10) and at(frame.buttons[2], -10 * 42, 61 + 10))
		check("the frame is as wide as twelve columns", frame.width == 400 + 84)
		check("the header spans twelve columns", header_named(env, frame, "The Armory").width == 12 * 37 + 11 * 5)
		addon.module.set("bags", "group", false)
		check("ungrouped again, twelve columns are still twelve", at(frame.buttons[13], 0, 42) and frame.width == 400 + 84)
	end
	do
		-- A locked slot sits last among the empty ones.
		local addon, env, frame = group_setup(3, { { class = 4, quality = 4, level = 270 } })
		frame.buttons[2].IsExtended = function() return true end
		addon.module.set("bags", "group", true)
		check("a locked slot comes after the free slots", at(frame.buttons[3], -378, 0) and at(frame.buttons[2], -336, 0))
	end
	do
		-- Slots in several bags: stock order within a section.
		local containers = {
			["0:1"] = { itemID = 1001, hyperlink = "link1", quality = 4 },
			["1:2"] = { itemID = 1002, hyperlink = "link2", quality = 4 },
		}
		local addon, env, frame = group_setup(3, { { class = 4, quality = 4, level = 270 }, { class = 4, quality = 4, level = 270 } },
			{ C_Container = { GetContainerItemInfo = function(bag, slot) return containers[bag .. ":" .. slot] end } })
		frame.buttons[2].GetBagID = function() return 1 end
		addon.module.set("bags", "group", true)
		check("within a section the later bag comes first, as in stock", at(frame.buttons[2], -378, 71) and at(frame.buttons[1], -336, 71) and at(frame.buttons[3], -378, 0))
	end
	do
		-- Missing pieces of the game: leave the stock grid alone.
		local addon, env, frame = group_setup(4, { { class = 4, quality = 4, level = 270 } }, { C_Container = false })
		check("without the container API grouping does not fail", pcall(addon.module.set, "bags", "group", true))
		check("without the container API the slots are in a flat grid and no header shows", at(frame.buttons[2], -42, 0) and #headers_of(env, frame) == 0)
		local second_addon, second_env, second_frame = group_setup(4, { { class = 4, quality = 4, level = 270 } }, { C_Texture = false })
		second_addon.module.set("bags", "group", true)
		check("without the atlas lookup headers still show, with no rule", header_named(second_env, second_frame, "The Armory").shown
			and header_named(second_env, second_frame, "The Armory").textures[1] == nil)
	end
	do
		-- Disabling with the bag closed: stock lays it out fresh on opening, so nothing of ours may be left showing.
		local addon, env, frame = group_setup(4, { { class = 4, quality = 4, level = 270 } })
		addon.module.set("bags", "group", true)
		frame.IsShown = function() return false end
		addon.module.set("bags", "group", false)
		check("turning grouping off with the bag closed hides the headers", not header_named(env, frame, "The Armory").shown)
		addon.module.set("bags", "group", true)
		addon.module.set("bags", "enabled", false)
		check("turning the module off with the bag closed hides the headers", not header_named(env, frame, "The Armory").shown)
	end
	do
		-- One hook however often it is applied.
		local addon, _, frame = group_setup(4, { { class = 4, quality = 4, level = 270 } })
		addon.module.set("bags", "group", true)
		addon.module.set("bags", "columns", 12)
		addon.module.set("bags", "columns", 10)
		frame:UpdateItemLayout()
		check("applying again does not stack anchors", #frame.buttons[2].points == 1)
	end

	-- The junk store: item ids the player marked, kept in the saved settings.
	do
		local addon = load_bags()
		local junk = addon.bags_junk
		local data = {}
		check("marking an item says it is now marked", junk.toggle(data, 2589) == true and junk.is_marked(data, 2589))
		check("marking it again unmarks it", junk.toggle(data, 2589) == false and not junk.is_marked(data, 2589))
		check("an unmarked item is not in the store", next(data) == nil)
		check("an item that was never marked is not marked", not junk.is_marked(data, 6948))
		for label, bad in pairs({ none = false, zero = 0, negative = -5, fraction = 1.5, text = "2589", infinity = math.huge, table = {} }) do
			local before = junk.toggle(data, bad)
			check("an id that is " .. label .. " marks nothing", before == nil and next(data) == nil and not junk.is_marked(data, bad))
		end
		check("a missing id marks nothing", junk.toggle(data, nil) == nil and not junk.is_marked(data, nil))
		local secret = {}
		local guarded = load_bags({ issecretvalue = function(value) return value == secret end })
		check("a secret id marks nothing", guarded.bags_junk.toggle({}, secret) == nil and not guarded.bags_junk.is_marked({ [secret] = true }, secret))
		local first = junk.data()
		check("asking for the saved table again gives the same table", first == addon.bags_junk.data())
	end
	do
		local addon, env = load_bags()
		local data = addon.bags_junk.data()
		check("the junk table lives with the Bags settings and survives being asked for again",
			data == env.EverlookDB.qol.bags.junk and addon.bags_junk.data() == data)
	end

	-- Registration of the marker option.
	do
		local addon = load_bags()
		local found
		for _, module in ipairs(addon.module.modules) do
			if module.id == "bags" then found = module end
		end
		check("the junk marker is an option that starts off", found.options.junk_marker and found.options.junk_marker.default == false)
	end

	-- Mark mode, on a stand-in for the stock frame.
	local function buttons_with(created, parent)
		local found = {}
		for _, widget in ipairs(created) do
			if widget.parent == parent then found[#found + 1] = widget end
		end
		return found
	end
	local function junk_coin(button)
		for _, texture in ipairs(button.textures or {}) do
			if texture.atlas == "bags-junkcoin" and texture.shown then return texture end
		end
	end
	local function marker_setup(options)
		local gear = { { class = 0, quality = 1, level = 1 }, { class = 0, quality = 1, level = 1 }, { class = 4, quality = 4, level = 270 } }
		local frame, extra = stand_in(4, gear)
		if options and options.no_close_button then frame.CloseButton = nil end
		local addon, env, loaded = load_bags(extra)
		loaded["Everlook_Bags"]()
		addon.module.set("bags", "enabled", true)
		return addon, env, frame
	end
	do
		local addon, env, frame = marker_setup()
		check("turning the module on adds no button while the marker is off", #buttons_with(env.created, frame) == 0)
		addon.module.set("bags", "junk_marker", true)
		local coin_buttons = buttons_with(env.created, frame)
		check("turning the marker on adds one coin button to the bag", #coin_buttons == 1)
		local coin = coin_buttons[1]
		local point = coin.points[1]
		check("the coin button sits in the title row, just left of the close button",
			point[1] == "RIGHT" and point[2] == frame.CloseButton and point[3] == "LEFT" and point[4] == -2 and point[5] == 0)
		check("the coin button is a small square", coin.width == 22 and coin.height == 22)
		check("the coin button sits well above the bag's own children, so the title bar's menu button cannot take its click", coin.level == 25)
		check("the coin button draws the game's junk coin", coin.textures[1] and coin.textures[1].atlas == "bags-junkcoin")
		check("there are no click overlays until mark mode is on", #buttons_with(env.created, frame.buttons[1]) == 0)
		check("the coin button is not pressed until it is clicked", coin.locked == false)

		coin.scripts.OnClick(coin)
		check("clicking the coin starts mark mode and shows it pressed", coin.locked == true)
		for index, button in ipairs(frame.buttons) do
			local overlays = buttons_with(env.created, button)
			check("slot " .. index .. " gets one click overlay in mark mode", #overlays == 1 and overlays[1].shown and overlays[1].all_points == button)
		end
		check("an overlay sits above its slot", buttons_with(env.created, frame.buttons[1])[1].level == 15)

		local first = buttons_with(env.created, frame.buttons[1])[1]
		check("a slot with an item has no coin until it is marked", junk_coin(frame.buttons[1]) == nil and not addon.bags.is_junk(1001))
		first.scripts.OnClick(first)
		check("clicking an overlay marks that item", addon.bags.is_junk(1001) == true)
		local mark = junk_coin(frame.buttons[1])
		check("a marked item shows the junk coin in the top left", mark ~= nil and mark.point[1] == "TOPLEFT" and mark.point[2] == frame.buttons[1] and mark.point[4] == 1)
		check("the other items stay unmarked", junk_coin(frame.buttons[2]) == nil and not addon.bags.is_junk(1002))
		first.scripts.OnClick(first)
		check("clicking again unmarks it and takes the coin off", not addon.bags.is_junk(1001) and junk_coin(frame.buttons[1]) == nil)

		local empty = buttons_with(env.created, frame.buttons[4])[1]
		empty.scripts.OnClick(empty)
		check("clicking an empty slot marks nothing", next(env.EverlookDB.qol.bags.junk) == nil)

		first.scripts.OnClick(first)
		first.scripts.OnEnter(first)
		check("hovering an overlay shows that item's own tooltip with what a click does",
			env.GameTooltip.bag_item[1] == 0 and env.GameTooltip.bag_item[2] == 1 and env.GameTooltip.owner == first
			and env.GameTooltip.shown and env.GameTooltip.lines[#env.GameTooltip.lines]:find("not junk", 1, true) ~= nil)
		first.scripts.OnLeave(first)
		check("leaving it hides the tooltip", not env.GameTooltip.shown)

		coin.scripts.OnClick(coin)
		check("clicking the coin again ends mark mode", coin.locked == false)
		for index, button in ipairs(frame.buttons) do
			check("slot " .. index .. "'s overlay is hidden when the mode ends", not buttons_with(env.created, button)[1].shown)
		end
		check("the marked item keeps its coin after the mode ends", junk_coin(frame.buttons[1]) ~= nil)

		coin.scripts.OnClick(coin)
		frame:Hide()
		check("closing the bag ends mark mode", coin.locked == false and not buttons_with(env.created, frame.buttons[2])[1].shown)

		-- A marked item moved to another slot: the coin follows it on the next refresh.
		frame.buttons[1].moved = true
		env.C_Container.GetContainerItemInfo = function(bag, slot)
			if bag ~= 0 then return nil end
			if slot == 2 then return { itemID = 1001, hyperlink = "link1", quality = 1 } end
			if slot == 1 then return nil end
			if slot == 3 then return { itemID = 1003, hyperlink = "link3", quality = 4 } end
		end
		frame:UpdateItems()
		check("the coin follows a marked item to the slot it moved to", junk_coin(frame.buttons[2]) ~= nil and junk_coin(frame.buttons[1]) == nil)

		addon.module.set("bags", "junk_marker", false)
		check("turning the marker off hides the coin button, the coins and any overlay", coin.shown == false and junk_coin(frame.buttons[2]) == nil)
		check("turning the marker off keeps what was marked", env.EverlookDB.qol.bags.junk[1001] == true)
		check("with the marker off nothing counts as junk", addon.bags.is_junk(1001) == false)
		addon.module.set("bags", "junk_marker", true)
		check("turning it back on brings the button, the coins and the marks back", coin.shown == true and junk_coin(frame.buttons[2]) ~= nil and addon.bags.is_junk(1001) == true)

		addon.module.set("bags", "enabled", false)
		check("turning the module off hides the button and the coins", coin.shown == false and junk_coin(frame.buttons[2]) == nil)
		check("with the module off nothing counts as junk, though the marks are kept", addon.bags.is_junk(1001) == false and env.EverlookDB.qol.bags.junk[1001] == true)
	end
	do
		-- Mark mode must not outlive the option that turns it on.
		local addon, env, frame = marker_setup()
		addon.module.set("bags", "junk_marker", true)
		local coin = buttons_with(env.created, frame)[1]
		coin.scripts.OnClick(coin)
		addon.module.set("bags", "junk_marker", false)
		check("turning the marker off ends mark mode", coin.locked == false and not buttons_with(env.created, frame.buttons[1])[1].shown)
	end
	do
		local addon, env, frame = marker_setup({ no_close_button = true })
		check("a bag with no close button gets no coin button and no error", pcall(addon.module.set, "bags", "junk_marker", true) and #buttons_with(env.created, frame) == 0)
	end
	do
		-- The public lookup other addons use.
		local addon = marker_setup()
		check("is_junk is false for an item nobody marked", addon.bags.is_junk(1001) == false)
		for label, bad in pairs({ none = false, text = "1001", zero = 0 }) do
			check("is_junk is false for an id that is " .. label, addon.bags.is_junk(bad) == false)
		end
		check("is_junk with no argument is false", addon.bags.is_junk() == false)
	end
end
