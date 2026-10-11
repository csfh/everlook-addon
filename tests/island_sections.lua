-- Sections: the public contract other addons build on, and how the panes draw them.
-- Every call goes through Everlook.island, the way an outside addon would make it.
return function(root, check, island_world, quest_world)
	local layout = dofile(root .. "/tests/layout.lua")

	-- The island is off until it is turned on.
	local function world()
		local addon, env, event, state, afters, tickers, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		return addon, env, event, state, afters, tickers, frames
	end

	local function open(addon, frames)
		addon.module.set("smart_island", "reduced_motion", true)
		local island_frame
		for _, frame in ipairs(frames) do if frame.name == "EverlookSmartIsland" then island_frame = frame end end
		island_frame.scripts.OnClick(island_frame, "LeftButton")
		layout.settle(frames)
		return island_frame
	end

	-- The island's own header and status cells are sections too, so a count is of what a test added.
	local function added(addon, base)
		return addon.smart_island.view().sections - (base or 0)
	end

	local function find_text(frames, text)
		for _, frame in ipairs(frames) do
			for _, region in ipairs(frame.regions or {}) do
				if region.text == text and region.shown ~= false then return region end
			end
		end
	end

	local function spec(overrides)
		local base = { source = "MyAddon", key = "bosses", region = "pane_b", title = "Bosses",
			blocks = { { kind = "row", row = { title = "Ragnaros", labels = { "3/8" } } } } }
		for name, value in pairs(overrides or {}) do base[name] = value end
		return base
	end

	do
		local addon, env = world()
		local api = env.Everlook.island
		check("the section call and a version are part of the public island, and its internals still are not",
			type(api.section) == "function" and type(api.react) == "function" and api.api == 2 and api.view == nil)

		local handle = api.section(spec())
		check("a section returns a number handle", type(handle) == "number")
		check("the same source and key updates the section and keeps its handle", api.section(spec({ title = "Raid" })) == handle
			and addon.smart_island.view().sections == 3)

		local function rejected(label, bad, reason)
			local result, why = api.section(bad)
			check("a section is rejected: " .. label, result == nil and why == reason)
		end
		rejected("no source", spec({ source = false }), "invalid_source")
		rejected("no key", spec({ key = "" }), "invalid_key")
		rejected("a region that does not exist", spec({ region = "footer" }), "invalid_region")
		rejected("an unknown field", spec({ colour = "red" }), "invalid_section")
		rejected("a title with a colour code", spec({ title = "|cffff0000Red|r" }), "invalid_title")
		rejected("an order below the built-in slots", spec({ order = 50 }), "invalid_order")
		rejected("an order past the inbox", spec({ order = 1000 }), "invalid_order")
		rejected("more than thirty blocks", spec({ blocks = (function() local list = {} for index = 1, 31 do list[index] = { kind = "gap" } end return list end)() }), "invalid_blocks")
		rejected("an unknown block kind", spec({ blocks = { { kind = "chart" } } }), "invalid_block")
		rejected("a text block with a texture escape", spec({ blocks = { { kind = "text", text = "|TInterface\\Icons\\x:16|t" } } }), "invalid_block")
		rejected("a row with an unknown tone", spec({ blocks = { { kind = "row", row = { title = "x", ring = { fraction = 0.5, tone = "pink" } } } } }), "invalid_row")
		rejected("a row ring past one", spec({ blocks = { { kind = "row", row = { title = "x", ring = { fraction = 2 } } } } }), "invalid_row")
		rejected("a row with four labels", spec({ blocks = { { kind = "row", row = { labels = { "a", "b", "c", "d" } } } } }), "invalid_row")
		rejected("an action with no callback", spec({ blocks = { { kind = "row", row = { title = "x" }, action = { id = "pin", label = "Pin" } } } }), "invalid_action_callback")
		rejected("an empty row", spec({ blocks = { { kind = "row", row = {} } } }), "invalid_row")
		local accepted = api.section(spec({ source = "Other", key = "gaps", blocks = { { kind = "heading", text = "Heading" }, { kind = "text", text = "One\nTwo" },
			{ kind = "gap", size = "section" }, { kind = "row", row = { icon = "quest", title = "Row", ring = { fraction = 0.5, tone = "success" }, badge = "9" },
				tooltip = { title = "Row", lines = { "More" } } } } }))
		check("every block kind is accepted, with a mark, a ring, a tooltip and line breaks", type(accepted) == "number")

		rejected("a meter past one", spec({ blocks = { { kind = "meter", label = "Raid", value = "9", fraction = 1.5 } } }), "invalid_block")
		rejected("a meter with a colour code in its value", spec({ blocks = { { kind = "meter", label = "Raid", value = "|cffff0000x|r", fraction = 0.5 } } }), "invalid_block")
		rejected("no cells", spec({ blocks = { { kind = "cells", cells = {} } } }), "invalid_block")
		rejected("seven cells", spec({ blocks = { { kind = "cells", cells = (function() local list = {} for index = 1, 7 do list[index] = { label = "a", value = "b" } end return list end)() } } }), "invalid_block")
		rejected("a cell with an unknown key", spec({ blocks = { { kind = "cells", cells = { { label = "a", value = "b", colour = "red" } } } } }), "invalid_block")
		check("a meter and cells with marks and rings are accepted", api.section(spec({ key = "figures", blocks = {
			{ kind = "meter", label = "Raid", value = "3/8", fraction = 0.375, tone = "warning" },
			{ kind = "cells", cells = { { icon = "money", label = "Gold", value = "12g" }, { icon = "repair", label = "Gear", value = "40%", ring = { fraction = 0.4, tone = "error" } } } } } })) ~= nil)
		rejected("a table row with a missing value", spec({ blocks = { { kind = "table", title = "T", columns = { "Hour", "Day" }, rows = { { "Total", "1" } } } } }), "invalid_block")
		rejected("a table with four columns", spec({ blocks = { { kind = "table", title = "T", columns = { "a", "b", "c", "d" }, rows = { { "x", "1", "2", "3", "4" } } } } }), "invalid_block")
		rejected("a table with nine rows", spec({ blocks = { { kind = "table", title = "T", columns = { "a" }, rows = (function() local list = {} for index = 1, 9 do list[index] = { "r", "1" } end return list end)() } } }), "invalid_block")
		check("a table with columns, rows, a footer, an action and a state is accepted", api.section(spec({ key = "table", blocks = {
			{ kind = "table", title = "Experience", columns = { "Hour", "Day" }, rows = { { "Total", "1,200", "20,000" }, { "Quests", "800", "9,000" } },
				footer = "Rested 20%", open = true, action = { id = "fold", label = "Show only the total", on_click = function() end } } } })) ~= nil)
		local builtin = api.section(spec({ source = "everlook_quests", key = "first", order = 10 }))
		check("one of our own sources may take a slot below 100", type(builtin) == "number")

		-- Updating and dismissing use the same two functions as a notice.
		check("update replaces a section's blocks and keeps its handle",
			api.update(handle, { blocks = { { kind = "text", text = "Phase two" } } }) == handle)
		check("update keeps what it was not given", addon.island_section ~= nil and addon.smart_island.view().sections == 7)
		local _, no_region = api.update(handle, { region = "pane_a" })
		local _, no_source = api.update(handle, { source = "Else" })
		local _, bad_field = api.update(handle, { blocks = { { kind = "chart" } } })
		check("update refuses to move a section or rename its source, and checks the blocks",
			no_region == "invalid_update" and no_source == "invalid_update" and bad_field == "invalid_block")
		check("dismiss removes a section once", api.dismiss(handle) == true and api.dismiss(handle) == false and addon.smart_island.view().sections == 6)
		local _, unknown = api.update(handle, { title = "Gone" })
		check("a dismissed section's handle is unknown to update", unknown == "unknown_handle")

		local notice = api.notify({ source = "MyAddon", text = "A notice" })
		check("a notice and a section never share a handle", notice ~= handle and notice ~= accepted and notice ~= builtin)
	end

	do
		local addon, env = world()
		local api = env.Everlook.island
		for index = 1, 12 do api.section(spec({ key = "k" .. index })) end
		local over, reason = api.section(spec({ key = "k13" }))
		check("a thirteenth section is refused", over == nil and reason == "limit")
		check("a section that already exists can still be updated at the limit", api.section(spec({ key = "k1", title = "Again" })) ~= nil)

		local other_world, other_env = world()
		local other = other_env.Everlook.island
		local filler = string.rep("x", 300)
		local blocks = {}
		for index = 1, 26 do blocks[index] = { kind = "text", text = filler } end
		check("a source may carry up to 8 KB of text", other.section(spec({ key = "a", blocks = blocks })) ~= nil)
		local more, why = other.section(spec({ key = "b", blocks = blocks }))
		check("text past 8 KB for one source is refused, and another source is not held to it",
			more == nil and why == "limit" and other.section(spec({ source = "Else", key = "b", blocks = blocks })) ~= nil)
		check("limits are counted per world", added(other_world, 2) == 2 and added(addon, 2) == 12)
	end

	do
		local addon, env = world()
		local api = env.Everlook.island
		local mine = api.section(spec({ source = "One" }))
		local yours = api.section(spec({ source = "Two" }))
		check("two sources using one key get their own sections", mine ~= yours and added(addon, 2) == 2)
		api.dismiss(mine)
		check("dismissing one leaves the other", added(addon, 2) == 1 and api.update(yours, { title = "Still" }) == yours)

		addon.module.set("smart_island", "enabled", false)
		local blocked, reason = api.section(spec({ key = "off" }))
		check("a disabled island refuses sections", blocked == nil and reason == "disabled")
		addon.module.set("smart_island", "enabled", true)
		check("turning the island off cleared the sections that were there", added(addon, 2) == 0)
	end

	-- A section expires only when its source asked for it.
	do
		local addon = world()
		local store = addon.island_section.new_store((function() local n = 0 return function() n = n + 1 return n end end)())
		local kept = addon.island_section.read(spec({ key = "plain" }))
		local timed = addon.island_section.read(spec({ key = "timed", expires = 30 }))
		store.put(kept, 100)
		store.put(timed, 100)
		check("a section with no expiry stays, and one with expiry stays until its time", store.prune(129) == false and store.count() == 2)
		check("an expired section is pruned and the other is not", store.prune(130) == true and store.count() == 1 and store.get(kept.handle) ~= nil)
		store.put(addon.island_section.read(spec({ key = "timed", expires = 30 })), 125)
		check("an update refreshes the expiry", store.prune(150) == false and store.count() == 2)
	end

	-- What the panes draw.
	do
		local addon, env, _, _, _, _, frames = world()
		local api = env.Everlook.island
		api.notify({ source = "MyAddon", text = "First notice" })
		local fired
		api.section(spec({ blocks = {
			{ kind = "text", text = "Phase two starts at 40 percent." },
			{ kind = "row", row = { icon = "quest", title = "Ragnaros", labels = { "3/8" }, badge = "60%" },
				action = { id = "pin", label = "Pin", on_click = function(handle, action_id) fired = { handle, action_id } end },
				tooltip = { title = "Ragnaros", lines = { "Fire Lord" } } },
		} }))
		open(addon, frames)
		local function dump(name, frames_list, env_list)
			local dir = os.getenv("ISLAND_LAYOUT_DIR")
			if not dir then return end
			local top
			for _, frame in ipairs(frames_list) do if frame.name == "EverlookSmartIsland" then top = frame end end
			local handle = assert(io.open(dir .. "/" .. name .. ".json", "w"))
			handle:write(layout.export(frames_list, top, env_list.GetTime()))
			handle:close()
		end
		dump("sections_b", frames, env)
		check("a section in pane B shows its title, text and row", find_text(frames, "BOSSES") and find_text(frames, "Phase two starts at 40 percent.")
			and find_text(frames, "Ragnaros") and find_text(frames, "3/8"))

		local measure = layout.new()
		local heading, notice = measure.rectangle(find_text(frames, "BOSSES")), measure.rectangle(find_text(frames, "First notice"))
		check("the section is drawn above the history, not over it", heading.top < notice.top and measure.rectangle(find_text(frames, "Ragnaros")).bottom <= notice.top)
		local problems = layout.lint(frames, { skip = function(frame) return frame.name == "EverlookIslandResting" end })
		check("with a section showing, nothing sits outside its frame and no two lines of text overlap", #problems == 0)
		if #problems > 0 then print(table.concat(problems, "\n")) end

		local function button_with(text)
			for _, frame in ipairs(frames) do
				if frame.scripts and frame.scripts.OnClick then
					for _, child in ipairs(frames) do
						if child.parent == frame then
							for _, region in ipairs(child.regions or {}) do if region.text == text then return frame end end
						end
					end
				end
			end
		end
		local button = button_with("Pin")
		check("the row's action is a button", button ~= nil)
		if button then
			button.scripts.OnClick(button)
			check("clicking an action calls the producer with the section's handle and the action id", fired and type(fired[1]) == "number" and fired[2] == "pin")
		end
		check("a section never takes the hover preview with it: its row is a hover target", (function()
			for _, frame in ipairs(frames) do
				if frame.scripts and frame.scripts.OnEnter and frame.parent and frame.width and frame.height == 28 then return true end
			end
		end)())
		local errors = {}
		env.geterrorhandler = function() return function(message) errors[#errors + 1] = message end end
		api.section(spec({ key = "fails", blocks = { { kind = "row", row = { title = "Boom" },
			action = { id = "boom", label = "Boom", on_click = function() error("callback failed") end } } } }))
		layout.settle(frames)
		local failing = button_with("Boom")
		if failing then failing.scripts.OnClick(failing) end
		check("an error in a producer's callback goes to the error handler and does not stop the island",
			failing ~= nil and #errors == 1 and errors[1]:find("callback failed", 1, true) ~= nil and addon.smart_island.view().mode == "open")
	end

	-- Pane A with no quest.
	do
		local addon, env, _, _, _, _, frames = world()
		local api = env.Everlook.island
		api.section(spec({ region = "pane_a", key = "list", title = "Raid" }))
		open(addon, frames)
		local measure = layout.new()
		local island
		for _, frame in ipairs(frames) do if frame.name == "EverlookSmartIsland" then island = measure.rectangle(frame) end end
		check("a section in pane A opens two panes with no quest", island.width == 720)
		check("with no quest, the first section's title is the pane's heading", find_text(frames, "RAID") ~= nil and find_text(frames, "QUESTS") == nil)
	end

	-- Both panes, with a quest and sections in each.
	do
		local addon, env, _, _, _, _, frames = quest_world()
		addon.module.set("smart_island", "quest_context", true)
		local api = env.Everlook.island
		api.notify({ source = "MyAddon", text = "Loot: Thunderfury", detail = "From Baron Geddon" })
		api.section(spec({ region = "pane_a", key = "raid", title = "Raid", blocks = {
			{ kind = "row", row = { icon = "quest", title = "Lucifron", ring = { fraction = 1, tone = "success" }, labels = { "Dead" } } },
			{ kind = "row", row = { icon = "quest", title = "Magmadar", ring = { fraction = 0.4, tone = "warning" }, labels = { "40%" } },
				action = { id = "pull", label = "Mark", on_click = function() end } },
			{ kind = "gap", size = "near" },
			{ kind = "text", text = "Phase two starts at 40 percent." },
			{ kind = "meter", label = "Raid cleared", value = "3/8", fraction = 0.375, tone = "warning" },
			{ kind = "cells", cells = { { icon = "money", label = "Gold", value = "12g 4s" }, { icon = "repair", label = "Armor", value = "40%", ring = { fraction = 0.4, tone = "error" } },
				{ icon = "bags", label = "Slots", value = "8 free" } } } } }))
		api.section(spec({ key = "bosses", title = "Bosses", blocks = {
			{ kind = "row", row = { title = "Ragnaros", labels = { "3/8" }, badge = "60%" } },
			{ kind = "row", row = { title = "Sulfuron Harbinger, Lord of the Molten Core", labels = { "Dead" } } } } }))
		open(addon, frames)
		local measure_a = layout.new()
		local function cell_at(text)
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions or {}) do
					if region.text == text and region.shown ~= false then return measure_a.rectangle(region.parent), measure_a.rectangle(region) end
				end
			end
		end
		local gold_cell, gold_label = cell_at("Gold")
		local gear_cell = cell_at("Armor")
		local bags_cell = cell_at("Slots")
		check("two cells share a row 24 apart and a third starts the next row 8 below, in the pane's 12 inset",
			gold_cell and gear_cell and bags_cell and gear_cell.left - gold_cell.right == 24 and gear_cell.top == gold_cell.top
			and bags_cell.top - gold_cell.bottom == 8 and bags_cell.left == gold_cell.left)
		check("a cell's text starts 36 in, past its gauge", gold_label.left - gold_cell.left == 36)
		check("a meter shows its label and its value", find_text(frames, "Raid cleared") ~= nil and find_text(frames, "3/8") ~= nil)
		local dir = os.getenv("ISLAND_LAYOUT_DIR")
		if dir then
			local top
			for _, frame in ipairs(frames) do if frame.name == "EverlookSmartIsland" then top = frame end end
			local handle = assert(io.open(dir .. "/sections_both.json", "w"))
			handle:write(layout.export(frames, top, env.GetTime()))
			handle:close()
		end
		-- A link has room each side of its words; the words, not the room, sit on the inset.
		local measure = layout.new()
		local island_rect
		for _, frame in ipairs(frames) do if frame.name == "EverlookSmartIsland" then island_rect = measure.rectangle(frame) end end
		local pin_words, clear_words = find_text(frames, "Pin quest"), find_text(frames, "Clear history")
		check("the words of a heading link end on the pane's 12 inset, as the figures below them do",
			pin_words and measure.rectangle(pin_words).right == island_rect.left + 300 - 12
			and measure.rectangle(clear_words).right == island_rect.right - 12)
		local problems = layout.lint(frames, { skip = function(frame) return frame.name == "EverlookIslandResting" end })
		check("with a quest and a section in each pane, nothing sits outside its frame and no two lines of text overlap", #problems == 0)
		if #problems > 0 then print(table.concat(problems, "\n")) end
	end

	-- A table: a heading line, columns of figures and a footer, with the heading folding it.
	do
		local addon, env, _, _, _, _, frames = world()
		local api = env.Everlook.island
		local folded
		api.section(spec({ key = "experience", title = nil, blocks = { { kind = "table", title = "Experience", columns = { "Hour", "Day" },
			rows = { { "Total", "1,200", "20,000" }, { "Quests", "800", "9,000" } }, footer = "Rested 20%", open = true,
			action = { id = "fold", label = "Show only the total", on_click = function(_, id) folded = id end } } } }))
		open(addon, frames)
		local measure = layout.new()
		local title, hour, day = find_text(frames, "v EXPERIENCE"), find_text(frames, "HOUR"), find_text(frames, "DAY")
		check("a table shows its heading with its fold marker, its columns, its rows and its footer",
			title and hour and day and find_text(frames, "Quests") and find_text(frames, "800") and find_text(frames, "Rested 20%"))
		local total, total_hour, total_day = measure.rectangle(find_text(frames, "Total")), measure.rectangle(find_text(frames, "1,200")), measure.rectangle(find_text(frames, "20,000"))
		local hour_head, day_head = measure.rectangle(hour), measure.rectangle(day)
		check("figures sit under their column heads, 84 wide with 8 between", total_hour.left == hour_head.left and total_day.left == day_head.left
			and day_head.left - hour_head.left == 84 + 8 and total_hour.top > hour_head.top and total.left < total_hour.left)
		local right_edge = measure.rectangle(find_text(frames, "20,000")).right
		local problems = layout.lint(frames, { skip = function(frame) return frame.name == "EverlookIslandResting" end })
		local island
		for _, frame in ipairs(frames) do if frame.name == "EverlookSmartIsland" then island = measure.rectangle(frame) end end
		check("a table sits inside its pane, its last column ending on the 12 inset, and overlaps nothing", #problems == 0 and right_edge == island.right - 12)
		if #problems > 0 then print(table.concat(problems, "\n")) end
		local toggle
		for _, frame in ipairs(frames) do if frame.scripts and frame.scripts.OnClick and frame.shown ~= false and frame.height == 14 + 8 then toggle = frame end end
		check("the heading line is a button that calls the action", toggle ~= nil)
		if toggle then
			toggle.scripts.OnClick(toggle)
			check("clicking the heading calls the producer with the action id", folded == "fold")
		end
	end
end
