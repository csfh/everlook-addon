-- What the game does that the fake frames do not. The fakes keep their state in plain fields (.mouse,
-- .point, .scripts and the like) that a real frame does not have, so production code that reads one of
-- them works in the tests and silently does nothing in the game.
return function(root, check, island_world)
	local layout = dofile(root .. "/tests/layout.lua")

	do
		local listing = io.popen("cd " .. root .. " && ls Everlook*/*.lua")
		local fields = { "mouse", "point", "points", "clicks", "scripts", "regions", "animation_groups", "pass_through", "attributes", "scroll_child", "scroll_offset" }
		local offences = {}
		for path in listing:lines() do
			local handle = assert(io.open(root .. "/" .. path, "r"))
			local number = 0
			for line in handle:lines() do
				number = number + 1
				local code = line:gsub("%-%-.*$", ""):gsub('"[^"]*"', '""')
				for _, field in ipairs(fields) do
					if code:find("[%w_%)%]]%." .. field .. "%f[^%w_]") then offences[#offences + 1] = path .. ":" .. number .. " ." .. field end
				end
			end
			handle:close()
		end
		listing:close()
		check("no addon code reads a field only the test frames have" .. (#offences > 0 and (": " .. table.concat(offences, ", ")) or ""), #offences == 0)
	end

	do
		local addon, _, _, _, _, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		local resting
		for _, frame in ipairs(frames) do if frame.name == "EverlookIslandResting" then resting = frame end end
		local kinds = {}
		for _, group in ipairs(resting and resting.animation_groups or {}) do
			for _, animation in ipairs(group.animations) do kinds[#kinds + 1] = animation.kind end
		end
		local alpha = false
		for _, kind in ipairs(kinds) do alpha = alpha or kind == "Alpha" end
		check("the pill's body has a clock for its motion and no alpha animation that would fade it", #kinds > 0 and not alpha)
	end

	do
		local addon, env, _, _, _, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		env.Everlook.island.notify({ source = "Test", key = "right", text = "Right click me", duration = 4,
			actions = { { id = "go", label = "Go", type = "callback", on_click = function() end } } })
		layout.settle(frames)
		local card
		for _, frame in ipairs(frames) do if frame.bound_entry and frame.scripts.OnMouseUp then card = frame end end
		check("a toast takes a right click to dismiss itself", card ~= nil and card.clicks ~= nil)
		local dismissed
		if card then
			card.scripts.OnMouseUp(card, "RightButton")
			dismissed = #addon.smart_island.view().toasts == 0 or addon.smart_island.view().toasts[1].phase == "exiting"
		end
		check("and the right click dismisses it", dismissed == true)
	end

	do
		-- A frame has no `shown` field. The pill's arrows turn only while their capsule is on screen.
		local addon, env, _, _, _, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		addon.module.set("smart_island", "reduced_motion", true)
		local calls = 0
		env.Everlook.island.notify({ source = "A", key = "a", presentation = "status", text = "x", capsule = { arrow = function() calls = calls + 1; return 0 end } })
		layout.settle(frames)
		env.Everlook.island.notify({ source = "B", key = "b", presentation = "status", text = "y", capsule = { text = "y" } })
		layout.settle(frames)
		local driver
		for _, frame in ipairs(frames) do
			if frame.scripts and frame.scripts.OnUpdate and frame.parent and frame.parent.name == "EverlookIslandFace" then driver = frame end
		end
		calls = 0
		driver.scripts.OnUpdate(driver, 0.2)
		check("a capsule that has left the pill is not asked for its arrow", driver ~= nil and calls == 0)
	end
end
