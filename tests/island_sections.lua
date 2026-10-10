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
			type(api.section) == "function" and api.api == 1 and api.view == nil)

		local handle = api.section(spec())
		check("a section returns a number handle", type(handle) == "number")
		check("the same source and key updates the section and keeps its handle", api.section(spec({ title = "Raid" })) == handle
			and addon.smart_island.view().sections == 1)

		local function rejected(label, bad, reason)
			local result, why = api.section(bad)
			check("a section is rejected: " .. label, result == nil and why == reason)
		end
		rejected("no source", spec({ source = false }), "invalid_source")
		rejected("no key", spec({ key = "" }), "invalid_key")
		rejected("a region that does not draw yet", spec({ region = "header" }), "invalid_region")
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

		local builtin = api.section(spec({ source = "everlook_quests", key = "first", order = 10 }))
		check("one of our own sources may take a slot below 100", type(builtin) == "number")

		-- Updating and dismissing use the same two functions as a notice.
		check("update replaces a section's blocks and keeps its handle",
			api.update(handle, { blocks = { { kind = "text", text = "Phase two" } } }) == handle)
		check("update keeps what it was not given", addon.island_section ~= nil and addon.smart_island.view().sections == 3)
		local _, no_region = api.update(handle, { region = "pane_a" })
		local _, no_source = api.update(handle, { source = "Else" })
		local _, bad_field = api.update(handle, { blocks = { { kind = "chart" } } })
		check("update refuses to move a section or rename its source, and checks the blocks",
			no_region == "invalid_update" and no_source == "invalid_update" and bad_field == "invalid_block")
		check("dismiss removes a section once", api.dismiss(handle) == true and api.dismiss(handle) == false and addon.smart_island.view().sections == 2)
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
		check("limits are counted per world", other_world.smart_island.view().sections == 2 and addon.smart_island.view().sections == 12)
	end

	do
		local addon, env = world()
		local api = env.Everlook.island
		local mine = api.section(spec({ source = "One" }))
		local yours = api.section(spec({ source = "Two" }))
		check("two sources using one key get their own sections", mine ~= yours and addon.smart_island.view().sections == 2)
		api.dismiss(mine)
		check("dismissing one leaves the other", addon.smart_island.view().sections == 1 and api.update(yours, { title = "Still" }) == yours)

		addon.module.set("smart_island", "enabled", false)
		local blocked, reason = api.section(spec({ key = "off" }))
		check("a disabled island refuses sections", blocked == nil and reason == "disabled")
		addon.module.set("smart_island", "enabled", true)
		check("turning the island off cleared the sections that were there", addon.smart_island.view().sections == 0)
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
			{ kind = "text", text = "Phase two starts at 40 percent." } } }))
		api.section(spec({ key = "bosses", title = "Bosses", blocks = {
			{ kind = "row", row = { title = "Ragnaros", labels = { "3/8" }, badge = "60%" } },
			{ kind = "row", row = { title = "Sulfuron Harbinger, Lord of the Molten Core", labels = { "Dead" } } } } }))
		open(addon, frames)
		local dir = os.getenv("ISLAND_LAYOUT_DIR")
		if dir then
			local top
			for _, frame in ipairs(frames) do if frame.name == "EverlookSmartIsland" then top = frame end end
			local handle = assert(io.open(dir .. "/sections_both.json", "w"))
			handle:write(layout.export(frames, top, env.GetTime()))
			handle:close()
		end
		local problems = layout.lint(frames, { skip = function(frame) return frame.name == "EverlookIslandResting" end })
		check("with a quest and a section in each pane, nothing sits outside its frame and no two lines of text overlap", #problems == 0)
		if #problems > 0 then print(table.concat(problems, "\n")) end
	end
end
