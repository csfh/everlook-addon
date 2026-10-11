-- The closed capsule in the states people see it: its resolved rectangles are written out so a change
-- to how it is drawn can be compared with how it was, and its measurements are held here.
return function(root, check, island_world, quest_world)
	local layout = dofile(root .. "/tests/layout.lua")

	local function ready(world)
		local addon, env, event, state, afters, tickers, frames = world()
		addon.module.set("smart_island", "enabled", true)
		addon.module.set("smart_island", "reduced_motion", true)
		local top
		for _, frame in ipairs(frames) do if frame.name == "EverlookSmartIsland" then top = frame end end
		return addon, env, event, state, tickers, frames, top
	end

	local function dump(name, frames, top)
		local dir = os.getenv("ISLAND_LAYOUT_DIR")
		if not dir then return end
		layout.settle(frames)
		local handle = assert(io.open(dir .. "/cap_" .. name .. ".txt", "w"))
		handle:write(layout.describe(frames, top))
		handle:close()
	end

	local states = {}

	-- The wide quest capsule.
	do
		local addon, _, _, _, _, frames, top = ready(quest_world)
		addon.module.set("smart_island", "quest_context", true)
		layout.settle(frames)
		dump("wide", frames, top)
		states.wide = { addon = addon, frames = frames, top = top }
	end

	-- The compact quest capsule: no title, no ring.
	do
		local addon, _, _, _, _, frames, top = ready(quest_world)
		addon.module.set("smart_island", "quest_context", true)
		addon.module.set("smart_island", "quest_title", false)
		layout.settle(frames)
		dump("compact", frames, top)
	end

	-- With an unread count.
	do
		local addon, env, _, _, _, frames, top = ready(quest_world)
		addon.module.set("smart_island", "quest_context", true)
		env.Everlook.island.notify({ source = "Test", key = "unread", text = "Something new", presentation = "inbox" })
		layout.settle(frames)
		dump("unread", frames, top)
	end

	-- A status with a mark, trailing text and progress.
	do
		local addon, env, _, _, _, frames, top = ready(island_world)
		env.Everlook.island.notify({ source = "Test", key = "flight", text = "Flying to Ratchet", presentation = "status",
			capsule = { text = "Ratchet", icon = "flight", trailing = "0:30", progress = 0.5 } })
		layout.settle(frames)
		dump("status", frames, top)
	end

	-- The level chip.
	do
		local addon, _, _, _, _, frames, top = ready(island_world)
		layout.settle(frames)
		dump("chip", frames, top)
	end
end
