-- Where the mouse goes. The fake frames know their strata, level, rectangle and whether they take the
-- mouse, so a test can ask what is under a point the way the game does, and find a button that
-- something else covers or clips.
return function(root, check, island_world, quest_world)
	local layout = dofile(root .. "/tests/layout.lua")

	local function inside(frame, ancestor)
		while frame do
			if frame == ancestor then return true end
			frame = frame.parent
		end
		return false
	end

	local function shown(frame)
		while frame do
			if frame.shown == false then return false end
			frame = frame.parent
		end
		return true
	end

	-- Every button that is on screen and takes clicks.
	local function pressable(frames)
		local list = {}
		for _, frame in ipairs(frames) do
			if frame.kind == "Button" and frame.mouse == true and frame.scripts.OnClick and shown(frame) then
				local rect = layout.new().rectangle(frame)
				if rect.width > 0 and rect.height > 0 then list[#list + 1] = frame end
			end
		end
		return list
	end

	-- The buttons the mouse would not reach at their middle.
	local function unreachable(frames, buttons)
		local lost = {}
		for _, button in ipairs(buttons) do
			local x, y = layout.center(button)
			local top = layout.hit(frames, x, y)
			if top ~= button and not inside(top, button) then lost[#lost + 1] = button end
		end
		return lost
	end

	local function open_world(how)
		local addon, env, _, _, afters, _, frames = quest_world()
		addon.module.set("smart_island", "quest_context", true)
		addon.module.set("smart_island", "quest_plan", true)
		addon.module.set("smart_island", "reduced_motion", how.reduced)
		-- A notice changes the capsule, and its ease is still playing when the island opens.
		env.Everlook.island.notify({ source = "Test", key = "one", text = "A notice", detail = "with detail",
			actions = { { id = "go", label = "Go", type = "callback", on_click = function() end },
				{ id = "later", label = "Later", type = "callback", on_click = function() end } } })
		local island_frame
		for _, frame in ipairs(frames) do if frame.name == "EverlookSmartIsland" then island_frame = frame end end
		if how.click then
			island_frame.IsMouseOver = function() return true end
			island_frame.scripts.OnClick(island_frame, "LeftButton")
		elseif how.pointer then
			island_frame.IsMouseOver = function() return true end
			island_frame.scripts.OnEnter(island_frame)
		else
			env.everlook_smart_island_key("down")
		end
		layout.settle(frames)
		return addon, env, frames, afters
	end

	do
		-- A frame that takes the mouse and does nothing with it is a dead spot on the island.
		local _, _, frames = open_world({ reduced = true, click = true })
		local idle = {}
		for _, frame in ipairs(frames) do
			if frame.kind == "Button" and frame.mouse == true and shown(frame) and not frame.scripts.OnClick and not frame.scripts.OnMouseDown and not frame.scripts.OnMouseUp then
				local rect = layout.new().rectangle(frame)
				if rect.width > 0 and rect.height > 0 then idle[#idle + 1] = (frame.name or "button") .. " " .. rect.width .. "x" .. rect.height end
			end
		end
		check("every button that takes the mouse on the open island does something with a click" .. (#idle > 0 and (": " .. table.concat(idle, ", ")) or ""), #idle == 0)
	end

	for _, how in ipairs({ { name = "by key", reduced = true }, { name = "by key, with motion", reduced = false },
		{ name = "by clicking", reduced = true, click = true }, { name = "by clicking, with motion", reduced = false, click = true },
		{ name = "by hovering", reduced = true, pointer = true }, { name = "by hovering, with motion", reduced = false, pointer = true } }) do
		local addon, _, frames = open_world(how)
		local view = addon.smart_island.view()
		check("the island opened " .. how.name .. " is open and as large as its panes", view.mode == "open" and view.shell.width == view.width and view.shell.height == view.height)
		local buttons = pressable(frames)
		local lost = unreachable(frames, buttons)
		check("every button in the island opened " .. how.name .. " gets the mouse where it sits (" .. #buttons .. " checked, " .. #lost .. " lost)", #buttons > 5 and #lost == 0)
	end

	do
		local _, env, frames = open_world({ reduced = true })
		local buttons = pressable(frames)
		local island_frame
		for _, frame in ipairs(frames) do if frame.name == "EverlookSmartIsland" then island_frame = frame end end
		local cover = env.CreateFrame("Frame", nil, nil)
		cover:SetFrameStrata("HIGH")
		cover:SetFrameLevel(90)
		cover:SetAllPoints(island_frame)
		cover:EnableMouse(true)
		check("a mouse-enabled frame laid over the buttons takes the mouse from them", #unreachable(frames, buttons) == #buttons)
		cover:EnableMouse(false)
		check("and with its mouse off the buttons have it back", #unreachable(frames, buttons) == 0)
	end

	do
		local addon, env, frames, afters = open_world({ reduced = true, click = true })
		local lines = {}
		env.print = function(...)
			local parts = {}
			for index = 1, select("#", ...) do parts[#parts + 1] = tostring((select(index, ...))) end
			lines[#lines + 1] = table.concat(parts, " ")
		end
		local ran, err = pcall(env.SlashCmdList.EVERLOOKISLANDMOUSE, "")
		check("/islandmouse starts without an error and asks for the pointer" .. (ran and "" or ": " .. tostring(err)), ran and lines[1] and lines[1]:find("hover the control now", 1, true) ~= nil)
		-- Three seconds on, it reports what the game says, and keeps the report for the saved variables.
		for _, after in ipairs(afters) do
			if after.delay == 3 and not after.done then after.done = true; after.callback() end
		end
		local report = env.EverlookDB and env.EverlookDB.island_mouse
		check("then it writes its report where it can be read after a reload", report ~= nil and report.lines[1]:find("mode open", 1, true) ~= nil and #report.lines >= 3)
		ran, err = pcall(env.SlashCmdList.EVERLOOKISLANDMOUSE, "click")
		check("and /islandmouse click presses the link without an error" .. (ran and "" or ": " .. tostring(err)), ran)
	end
end
