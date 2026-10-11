-- The resting display: the level chip is a capsule the island's own source pushes as a resting status,
-- the lowest rung under a status and a background status.
return function(root, check, island_world)
	local layout = dofile(root .. "/tests/layout.lua")

	local function world()
		local addon, env, event, state, afters, tickers, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		addon.module.set("smart_island", "reduced_motion", true)
		return addon, env, state, frames
	end

	-- The text of a visible region, as the closed pill shows it now.
	local function finder(frames)
		return function(text)
			layout.settle(frames)
			for _, frame in ipairs(frames) do
				local visible, walker = true, frame
				while walker do
					if walker.shown == false or (walker.alpha or 1) == 0 then visible = false end
					walker = walker.parent
				end
				for _, region in ipairs(frame.regions or {}) do
					if visible and region.text == text and region.shown ~= false then return region end
				end
			end
		end
	end

	local function capsule_spec() return { text = "Chip", labels = { "x" } } end

	do
		local addon, env, _, frames = world()
		local api = env.Everlook.island
		local function rejected(label, payload)
			local handle, why = api.notify(payload)
			check("a resting status is rejected: " .. label, handle == nil and why == "invalid_rank")
		end
		rejected("on a toast", { source = "A", key = "k", text = "t", rank = "resting" })
		rejected("without a capsule", { source = "A", key = "k", text = "t", presentation = "status", rank = "resting" })
		local handle = api.notify({ source = "A", key = "k", text = "t", presentation = "status", rank = "resting", capsule = capsule_spec() })
		check("with a capsule it is held", type(handle) == "number" and addon.smart_island.view().resting.source == "A")
	end

	do
		local addon, env, _, frames = world()
		local api = env.Everlook.island
		local shown = finder(frames)
		local view = addon.smart_island.view()
		check("the level chip is the island's own resting status", view.resting and view.resting.source == "everlook_resting" and shown("12") ~= nil)
		check("it is no status, history row, toast or unread notice", view.status == nil and #view.notices == 0 and #view.toasts == 0 and view.unread_count == 0)

		local background = api.notify({ source = "A", key = "bg", text = "Quest", presentation = "status", rank = "background",
			capsule = { text = "Quest", labels = { "~5 yd" } } })
		check("a background status takes the capsule from the chip", shown("Quest") ~= nil and shown("12") == nil and addon.smart_island.view().resting ~= nil)
		local status = api.notify({ source = "A", key = "s", text = "Trip", presentation = "status", capsule = { text = "Trip" } })
		check("a status takes it from both", shown("Trip") ~= nil and shown("Quest") == nil)
		api.dismiss(status)
		check("and the background status is back when it goes", shown("Quest") ~= nil)
		api.dismiss(background)
		check("and the chip when that goes", shown("12") ~= nil)

		addon.module.set("smart_island", "enabled", false)
		check("turning the island off clears the chip", addon.smart_island.view().resting == nil)
		addon.module.set("smart_island", "enabled", true)
		check("and turning it on brings it back", addon.smart_island.view().resting ~= nil and addon.smart_island.view().resting.count == 1)
	end

	do
		local addon, env, state, frames = world()
		local shown = finder(frames)
		addon.module.set("smart_island", "closed_xp", true)
		check("the experience percent is a label on the chip", shown("45%") ~= nil)
		check("with one resting status, however many times it changes", addon.smart_island.view().resting.count == 1)
		addon.module.set("smart_island", "closed_clock", true)
		state.bags = { [0] = 0, [1] = 0 }
		addon.smart_island.pull()
		addon.module.set("smart_island", "low_slots", 5)
		check("gear and bags share one label, so the chip keeps within three", shown("Bags 0") ~= nil and addon.smart_island.view().resting.count == 1)
		check("an empty bag is in the error color", math.abs(shown("Bags 0").color[2] - 128 / 255) < 0.01 and shown("Bags 0").color[1] > 0.99)
	end

	do
		local addon, env, _, frames = world()
		addon.module.set("smart_island", "reduced_motion", false)
		layout.settle(frames)
		-- Every region that says the level, with whether it is lent out and where it hangs.
		local function level_regions()
			local found = {}
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions or {}) do
					if region.text == "12" and region.shown ~= false then
						found[#found + 1] = { region = region, frame = frame }
					end
				end
			end
			return found
		end
		local resting_count = #level_regions()
		local pill
		for _, frame in ipairs(frames) do if frame.name == "EverlookSmartIsland" then pill = frame end end
		pill.scripts.OnEnter(pill)
		local travelling, lent = 0, 0
		for _, entry in ipairs(level_regions()) do
			if entry.frame.name == "EverlookIslandFace" then travelling = travelling + 1 end
			if entry.region.alpha == 0 then lent = lent + 1 end
			-- It starts where the row's title is: the middle of a 64 wide pill, half the 36 height down.
			if entry.frame.name == "EverlookIslandFace" then
				local point = entry.region.point
				check("it starts on the title it replaces", point and point[1] == "CENTER" and point[4] == 32 and point[5] == -18)
			end
		end
		check("opening, a copy of the level slides and the row's own title stands aside", resting_count >= 1 and travelling == 1 and lent >= 1)
		pill.scripts.OnLeave(pill)
		layout.settle(frames)
		local still = 0
		for _, entry in ipairs(level_regions()) do
			if entry.region.alpha == 0 then still = still + 1 end
		end
		check("closed again, the row has its title back", still == 0)
	end

	-- With the experience percent on, which is how the client starts, the title sits at the left and the
	-- other parts follow it. The copy starts on that title, and a resting status of someone else's does not slide.
	do
		local addon, env, _, frames = world()
		addon.module.set("smart_island", "reduced_motion", false)
		addon.module.set("smart_island", "closed_xp", true)
		layout.settle(frames)
		local pill
		for _, frame in ipairs(frames) do if frame.name == "EverlookSmartIsland" then pill = frame end end
		pill.scripts.OnEnter(pill)
		local copy
		for _, frame in ipairs(frames) do
			if frame.name == "EverlookIslandFace" then
				for _, region in ipairs(frame.regions or {}) do
					if region.text == "12" and region.shown ~= false then copy = region end
				end
			end
		end
		-- The face is 72 wide here: 12 in, the title, a 12 gap and the percent. The title is "12", two glyphs of 7.
		check("with the percent on it starts on the title at the left, 12 in and half its width over", copy and copy.point and copy.point[4] == 12 + 14 / 2 and copy.point[5] == -18)
		pill.scripts.OnLeave(pill)
		layout.settle(frames)
	end

	do
		local addon, env, _, frames = world()
		addon.module.set("smart_island", "reduced_motion", false)
		local api = env.Everlook.island
		api.notify({ source = "Other", key = "idle", text = "Standing by", presentation = "status", rank = "resting", capsule = { text = "Standing by" } })
		layout.settle(frames)
		local pill
		for _, frame in ipairs(frames) do if frame.name == "EverlookSmartIsland" then pill = frame end end
		pill.scripts.OnEnter(pill)
		local copies, title = 0, nil
		for _, frame in ipairs(frames) do
			for _, region in ipairs(frame.regions or {}) do
				if region.text == "12" and frame.name == "EverlookIslandFace" and region.shown ~= false then copies = copies + 1 end
				if region.text == "Standing by" and region.shown ~= false then title = region end
			end
		end
		check("a resting status of someone else's does not hand its title to the level", copies == 0 and title and title.alpha ~= 0)
	end

	-- Only a capsule centers a lone title. A title on its own in a section's row stays at the left.
	do
		local addon, env, _, frames = world()
		env.Everlook.island.section({ source = "Other", key = "lone", region = "pane_b", order = 100,
			blocks = { { kind = "row", row = { title = "Alone in a row" } } } })
		local pill
		for _, frame in ipairs(frames) do if frame.name == "EverlookSmartIsland" then pill = frame end end
		pill.scripts.OnEnter(pill)
		layout.settle(frames)
		local title
		for _, frame in ipairs(frames) do
			for _, region in ipairs(frame.regions or {}) do
				if region.text == "Alone in a row" then title = region end
			end
		end
		check("a section row's lone title is left aligned", title and title.justify == "LEFT")
	end
end
