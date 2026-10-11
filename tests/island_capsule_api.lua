-- The capsule spec a producer gives a status: what it accepts, what it draws, and how it stays right
-- as it changes. Every call goes through Everlook.island, as an outside addon would make it.
return function(root, check, island_world)
	local layout = dofile(root .. "/tests/layout.lua")

	local function world()
		local addon, env, event, state, afters, tickers, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		addon.module.set("smart_island", "reduced_motion", true)
		return addon, env, state, frames, afters
	end

	local function status(overrides)
		local spec = { source = "MyAddon", key = "trip", text = "Flying to Ratchet", presentation = "status",
			capsule = { text = "Ratchet", icon = "flight" } }
		for name, value in pairs(overrides or {}) do spec[name] = value end
		return spec
	end

	do
		local addon, env = world()
		local api = env.Everlook.island
		check("the capsule api is part of version 3", api.api == 3)

		local function rejected(label, capsule, reason)
			local handle, why = api.notify(status({ capsule = capsule }))
			check("a capsule is rejected: " .. label, handle == nil and why == (reason or "invalid_capsule"))
		end
		rejected("with nothing in it", {})
		rejected("with four labels", { text = "x", labels = { "a", "b", "c", "d" } })
		rejected("with three labels and a trailing one", { text = "x", labels = { "a", "b", "c" }, trailing = "d" })
		rejected("with a ring past one", { text = "x", ring = { fraction = 2 } })
		rejected("with a ring in a color that does not exist", { text = "x", ring = { fraction = 0.5, tone = "pink" } })
		rejected("with an arrow that is a string", { text = "x", arrow = "up" })
		rejected("with a label that has markup", { text = "x", labels = { "|cffff0000red|r" } })
		rejected("with a badge too long", { text = "x", badge = string.rep("9", 17) })
		rejected("with a title past 64 bytes", { text = string.rep("x", 65) })
		rejected("with a held width that is too narrow", { text = "x", min_width = 50 })
		rejected("with a held width that is too wide", { text = "x", min_width = 400 })
		rejected("with a held width that is not whole", { text = "x", min_width = 100.5 })

		local handle = api.notify(status({ capsule = { text = string.rep("x", 40), icon = "flight", arrow = function() return 0 end,
			ring = { fraction = 0.5, tone = "success" }, labels = { "~5 yd", { text = "20", tone = "primary" } }, badge = "45%", min_width = 300 } }))
		check("a capsule with a long title, an arrow, a ring, labels in tones, a badge and a held width is accepted", type(handle) == "number")
		local only_parts = api.notify(status({ key = "parts", capsule = { arrow = 1, labels = { "~5 yd" } } }))
		check("a capsule needs no title when it has other parts", type(only_parts) == "number")
	end

	do
		local addon, env, state, frames = world()
		local api = env.Everlook.island
		local angle, calls = 0.5, 0
		local errors = {}
		env.geterrorhandler = function() return function(message) errors[#errors + 1] = message end end
		local handle = api.notify(status({ capsule = { text = "Ratchet", icon = "flight", arrow = function() calls = calls + 1; return angle end,
			ring = { fraction = 0.4, tone = "warning" }, labels = { "~5 yd" }, badge = "45%" } }))
		layout.settle(frames)
		local function region(text)
			for _, frame in ipairs(frames) do
				for _, found in ipairs(frame.regions or {}) do
					if found.text == text and found.shown ~= false then return found end
				end
			end
		end
		local function arrow_texture()
			for _, frame in ipairs(frames) do
				local walker, in_slot = frame, false
				while walker do
					if walker.name == "EverlookIslandFace" then in_slot = true end
					walker = walker.parent
				end
				if in_slot then
					for _, found in ipairs(frame.regions or {}) do
						if type(found.path) == "string" and found.path:find("island_arrow", 1, true) and found.shown == true then return found end
					end
				end
			end
		end
		check("a status capsule draws its title, label and badge", region("Ratchet") and region("~5 yd") and region("45%"))
		check("its arrow points at the angle the function gave", arrow_texture() and arrow_texture().rotation == 0.5 and calls >= 1)
		local driver
		for _, frame in ipairs(frames) do
			if frame.name == nil and frame.scripts and frame.scripts.OnUpdate and frame.parent and frame.parent.name == "EverlookIslandFace" then driver = frame end
		end
		angle = 1.25
		driver.scripts.OnUpdate(driver, 0.05)
		local asked = calls
		driver.scripts.OnUpdate(driver, 0.06)
		check("it is asked at most every tenth of a second, and then the arrow turns", calls == asked + 1 and arrow_texture().rotation == 1.25)
		angle = nil
		driver.scripts.OnUpdate(driver, 0.1)
		check("a function that gives no angle hides the arrow", arrow_texture() == nil)

		-- A change of words is set in place: no crossfade, and the width holds.
		local before = addon.smart_island.view().shell
		api.update(handle, { capsule = { text = "Ratchet", icon = "flight", arrow = function() return 0 end,
			ring = { fraction = 0.6, tone = "warning" }, labels = { "~4 yd" }, badge = "46%" } })
		local after = addon.smart_island.view().shell
		check("new words and a new fraction replace in place, with no fade", region("~4 yd") ~= nil and region("~5 yd") == nil and after.fading ~= true)
		-- An update of the notice's own fields keeps the capsule whole.
		api.update(handle, { detail = "30 seconds elapsed" })
		local kept = addon.smart_island.view().status.capsule
		check("an update that does not name the capsule keeps all of it: arrow, ring, labels and badge",
			type(kept.arrow) == "function" and kept.ring and kept.ring.tone == "warning" and kept.labels[1] == "~4 yd" and kept.badge == "46%")
	end

	do
		local addon, env = world()
		local api = env.Everlook.island
		api.notify(status({ capsule = { text = "x", min_width = 320 } }))
		check("a capsule that asks to hold a width is that wide", addon.smart_island.view().width == 320)
		api.notify(status({ key = "narrow", capsule = { text = "x" } }))
		check("one that does not is as wide as its words need", addon.smart_island.view().width < 100)
	end

	-- A background status holds the capsule and nothing else.
	do
		local addon, env, state, frames, afters = world()
		local api = env.Everlook.island
		local function background(overrides)
			local spec = { source = "MyAddon", key = "quest", text = "Excavation", detail = "~885 yd", presentation = "status", rank = "background",
				capsule = { icon = "quest", text = "Excavation", labels = { "~885 yd" } } }
			for name, value in pairs(overrides or {}) do
				if value == false then spec[name] = nil else spec[name] = value end
			end
			return spec
		end
		local function rejected(label, spec)
			local handle, why = api.notify(spec)
			check("a background status is rejected: " .. label .. " (" .. tostring(why) .. ")", handle == nil and why == "invalid_rank")
		end
		rejected("with a rank that does not exist", background({ rank = "loud" }))
		rejected("on a toast", background({ presentation = "toast", capsule = false }))
		rejected("without a capsule to show", background({ capsule = false }))

		local handle = api.notify(background())
		local function region(text)
			for _, frame in ipairs(frames) do
				local visible, walker = true, frame
				while walker do
					if walker.shown == false or (walker.alpha or 1) == 0 then visible = false end
					walker = walker.parent
				end
				for _, found in ipairs(frame.regions or {}) do
					if visible and found.text == text and found.shown ~= false then return found end
				end
			end
		end
		layout.settle(frames)
		local view = addon.smart_island.view()
		check("a background status shows on the capsule", type(handle) == "number" and region("Excavation") ~= nil and view.background and view.background.count == 1)
		check("it is no status, no history row, no toast and not unread",
			view.status == nil and #view.notices == 0 and #view.toasts == 0 and view.unread_count == 0)

		-- The control: a normal status under the same clock does go, so a pass here means the clock ran.
		local mortal = api.notify({ source = "MyAddon", key = "mortal", text = "Mortal", presentation = "status", capsule = { text = "Mortal" } })
		state.time = state.time + 600
		for _, after in ipairs(afters) do
			if after.delay == 30 and not after.done then after.done = true; after.callback() end
		end
		layout.settle(frames)
		check("a normal status leaves when its thirty seconds pass", type(mortal) == "number" and addon.smart_island.view().status == nil)
		check("a background status stays through the same clock", addon.smart_island.view().background ~= nil and region("Excavation") ~= nil)

		local status_handle = api.notify({ source = "MyAddon", key = "flight", text = "Flying", presentation = "status", capsule = { text = "Ratchet", icon = "flight" } })
		layout.settle(frames)
		check("a real status takes the capsule while it lasts", region("Ratchet") ~= nil and region("Excavation") == nil and addon.smart_island.view().background ~= nil)
		api.dismiss(status_handle)
		layout.settle(frames)
		check("and when it is dismissed the background status is back", region("Excavation") ~= nil and region("Ratchet") == nil)

		for index = 1, 12 do api.notify({ source = "MyAddon", key = "s" .. index, text = "Status " .. index, presentation = "status", capsule = { text = "S" .. index } }) end
		for index = 1, 12 do api.dismiss(addon.smart_island.view().status and addon.smart_island.view().status.id or 0) end
		check("a pile of statuses does not push it out", addon.smart_island.view().background ~= nil)

		local again = api.update(handle, { detail = "~700 yd" })
		check("an update keeps its handle and its rank", again == handle and addon.smart_island.view().background.count == 1 and #addon.smart_island.view().notices == 0)
		check("dismissing it clears the capsule", api.dismiss(handle) == true and addon.smart_island.view().background == nil)

		api.notify(background())
		addon.module.set("smart_island", "enabled", false)
		addon.module.set("smart_island", "enabled", true)
		check("turning the island off clears it", addon.smart_island.view().background == nil)
	end
end
