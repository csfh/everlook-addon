-- Reactions: the arithmetic of a brief flash on the island's body, then how the island shows it.
return function(root, check, island_world, quest_world, secret_stat)
	local function near(actual, expected) return actual ~= nil and math.abs(actual - expected) < 1e-9 end

	do
		local addon = island_world()
		local reaction = addon.island_reaction
		local state = reaction.new()
		check("a kind that does not exist is refused", select(2, reaction.start(state, "fireworks", nil, 0)) == "invalid_reaction")
		check("a strength that is not a number is refused", select(2, reaction.start(state, "kill", "loud", 0)) == "invalid_reaction")

		check("a kill starts", reaction.start(state, "kill", nil, 10) == true)
		local rising = reaction.sample(state, 10.03)
		check("it rises over the first 60 ms to the kind's peak", near(rising.tint, 0.5 * 0.18 * 0.5) and rising.tone == "accent")
		local peak = reaction.sample(state, 10.06)
		check("the tint peaks at strength times the ceiling and the edge at its own", near(peak.tint, 0.09) and near(peak.edge, 0.45))
		local later = reaction.sample(state, 10.19)
		check("it decays after the peak, quickly at first", later.tint < peak.tint / 2 and later.tint > 0)
		check("it is gone when its time is up", reaction.sample(state, 10.32) == nil and reaction.sample(state, 10.33) == nil)

		local loud = reaction.new()
		reaction.start(loud, "level", 1, 0)
		check("the tint never goes past the ceiling", near(reaction.sample(loud, 0.06).tint, 0.18))
		local over = reaction.new()
		reaction.start(over, "level", 5, 0)
		check("a strength past one counts as one", near(reaction.sample(over, 0.06).tint, 0.18))

		local edge_only = reaction.new()
		reaction.start(edge_only, "error", nil, 0)
		local flash = reaction.sample(edge_only, 0.06)
		check("an error flashes the edge strongly and tints the body only lightly", near(flash.tint, 0.18 * 0.8 * 0.4) and flash.edge > 0.7 and flash.tone == "error")

		local twice = reaction.new()
		reaction.start(twice, "warning", nil, 0)
		local first_peak = reaction.sample(twice, 0.06).edge
		local between = reaction.sample(twice, 0.235).edge
		local second_peak = reaction.sample(twice, 0.30).edge
		check("a warning beats twice", first_peak > 0.4 and between < first_peak / 4 and second_peak > between * 3)
	end

	do
		local addon = island_world()
		local reaction = addon.island_reaction
		local state = reaction.new()
		reaction.start(state, "info", nil, 0)
		reaction.start(state, "kill", nil, 0.1)
		check("a reaction that starts soon after another joins it, with the louder kind and a fresh start",
			state.pulse.kind == "kill" and state.pulse.start == 0.1 and reaction.sample(state, 0.16).tone == "accent")
		reaction.start(state, "info", nil, 0.2)
		check("a quieter one joining does not turn the louder one down", state.pulse.kind == "kill")
		check("one that starts later than the window is its own", reaction.start(state, "loot", nil, 5) == true and state.pulse.kind == "loot" and state.pulse.start == 5)

		local busy = reaction.new()
		local results = {}
		for index = 1, 5 do results[index] = { reaction.start(busy, "loot", nil, index * 0.1) } end
		check("four start in a second and the fifth is limited", results[4][1] == true and results[5][1] == nil and results[5][2] == "limited")
		check("a second later it may start again", reaction.start(busy, "loot", nil, 1.5) == true)
	end

	do
		local addon = island_world()
		local reaction = addon.island_reaction
		local state = reaction.new()
		reaction.start(state, "kill", 1, 0, true)
		local first, mid = reaction.sample(state, 0), reaction.sample(state, 0.075)
		check("reduced motion is one short fade from a lower brightness, with no ramp",
			near(first.tint, 0.12) and near(mid.tint, 0.06) and near(first.edge, 0.6) and reaction.sample(state, 0.15) == nil)
	end

	-- How the island shows one.
	local function world()
		local addon, env, event, state, afters, tickers, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		return addon, env, state, frames
	end

	local function surface_pieces(frames)
		local list = {}
		for _, frame in ipairs(frames) do
			if frame.name == "EverlookIslandResting" then
				for _, region in ipairs(frame.regions) do list[#list + 1] = region end
			end
		end
		return list
	end

	-- The pieces that carry a reaction's colour: shown, with an alpha, and not the surface's own.
	local function lit(frames, red, green)
		local count = 0
		for _, region in ipairs(surface_pieces(frames)) do
			if region.shown ~= false and region.color and region.color[4] and region.color[4] > 0 and region.color[4] <= 1
				and math.abs(region.color[1] - red) < 0.01 and (green == nil or math.abs(region.color[2] - green) < 0.01) then count = count + 1 end
		end
		return count
	end

	do
		local addon, env, state, frames = world()
		local api = env.Everlook.island
		check("the island exposes react and a version that counts it", type(api.react) == "function" and api.api == 2)
		local resting
		for _, frame in ipairs(frames) do if frame.name == "EverlookIslandResting" then resting = frame end end
		local driver
		for _, frame in ipairs(frames) do if frame.parent and frame.parent.name == "EverlookSmartIsland" and frame.name == nil and frame.scripts then driver = driver or frame end end
		local accent = 173 / 255
		check("nothing is lit before a reaction", lit(frames, accent) == 0)
		state.time = 100
		check("a kill reaction returns true", api.react("kill") == true)
		state.time = 100.06
		for _, frame in ipairs(frames) do if frame.scripts and frame.scripts.OnUpdate and frame.parent and frame.parent.name == "EverlookSmartIsland" then frame.scripts.OnUpdate(frame, 0.06) end end
		check("it lights the body in the accent tone, and the edge strips with it", lit(frames, accent) >= 9)
		state.time = 101
		for _, frame in ipairs(frames) do if frame.scripts and frame.scripts.OnUpdate and frame.parent and frame.parent.name == "EverlookSmartIsland" then frame.scripts.OnUpdate(frame, 1) end end
		local still_running
		for _, frame in ipairs(frames) do if frame.scripts and frame.scripts.OnUpdate and frame.parent and frame.parent.name == "EverlookSmartIsland" then still_running = true end end
		check("when its time is up the light goes out and nothing keeps running", lit(frames, accent) == 0 and not still_running)

		local _, unknown = api.react("fireworks")
		local _, extra = api.react({ kind = "kill", colour = "red" })
		local _, source = api.react({ kind = "kill", source = 5 })
		check("a kind that does not exist, an unknown field and a source that is not text are refused",
			unknown == "invalid_reaction" and extra == "invalid_reaction" and source == "invalid_reaction")
		check("a reaction can name its source and a strength", api.react({ kind = "loot", strength = 0.5, source = "MyAddon" }) == true)

		state.time = 200
		local results = {}
		for index = 1, 5 do state.time = 200 + index * 0.05; results[index] = { api.react("info") } end
		check("the fifth reaction inside a second is limited", results[5][1] == nil and results[5][2] == "limited")
	end

	do
		local addon, env, state = world()
		local api = env.Everlook.island
		addon.module.set("smart_island", "do_not_disturb", true)
		check("do not disturb turns reactions off", select(2, api.react("kill")) == "do_not_disturb")
		addon.module.set("smart_island", "do_not_disturb", false)
		addon.module.set("smart_island", "reactions", false)
		check("the setting turns reactions off", select(2, api.react("kill")) == "disabled")
		addon.module.set("smart_island", "reactions", true)
		addon.module.set("smart_island", "enabled", false)
		check("a disabled island refuses a reaction", select(2, api.react("kill")) == "disabled")
	end

	do
		local addon, env, state, frames = world()
		local api = env.Everlook.island
		state.time = 300
		api.notify({ source = "MyAddon", text = "Durability low", severity = "error" })
		state.time = 300.06
		for _, frame in ipairs(frames) do if frame.scripts and frame.scripts.OnUpdate and frame.parent and frame.parent.name == "EverlookSmartIsland" then frame.scripts.OnUpdate(frame, 0.06) end end
		check("a new error flashes the edge in red without anyone asking", lit(frames, 1, 128 / 255) > 0)
		state.time = 301
		for _, frame in ipairs(frames) do if frame.scripts and frame.scripts.OnUpdate and frame.parent and frame.parent.name == "EverlookSmartIsland" then frame.scripts.OnUpdate(frame, 1) end end
		check("it fades on its own", lit(frames, 1, 128 / 255) == 0)
		state.time = 310
		api.notify({ source = "MyAddon", text = "Routine", severity = "info" })
		check("a routine notice does not flash", lit(frames, 1, 128 / 255) == 0 and lit(frames, 173 / 255) == 0)
	end

	-- A WoW event can ask for a reaction, alone or with a notice.
	do
		local addon, env, state, frames = world()
		local event
		do
			local fresh_addon, fresh_env, fresh_event, fresh_state, _, _, fresh_frames = island_world()
			fresh_addon.module.set("smart_island", "enabled", true)
			addon, env, state, frames, event = fresh_addon, fresh_env, fresh_state, fresh_frames, fresh_event
		end
		local api = env.Everlook.island
		api.register_event("CHAT_MSG_COMBAT_XP_GAIN", function() return { reaction = "kill" } end)
		api.register_event("PLAYER_LEVEL_UP", function() return { reaction = "level", source = "MyAddon", text = "Level up" } end)
		local errors = {}
		env.geterrorhandler = function() return function(message) errors[#errors + 1] = message end end
		api.register_event("UPDATE_EXHAUSTION", function() return { reaction = "fireworks" } end)
		state.time = 400
		event("CHAT_MSG_COMBAT_XP_GAIN")
		state.time = 400.06
		for _, frame in ipairs(frames) do if frame.scripts and frame.scripts.OnUpdate and frame.parent and frame.parent.name == "EverlookSmartIsland" then frame.scripts.OnUpdate(frame, 0.06) end end
		check("an event callback that returns only a reaction flashes the island and adds no notice",
			lit(frames, 173 / 255) > 0 and #addon.smart_island.view().notices == 0)
		state.time = 410
		event("PLAYER_LEVEL_UP")
		check("a callback may return a reaction and a notice together", #addon.smart_island.view().notices == 1 and addon.smart_island.view().notices[1].text == "Level up")
		event("UPDATE_EXHAUSTION")
		check("a reaction that does not exist is reported to the error handler", #errors == 1 and errors[1]:find("invalid_reaction", 1, true) ~= nil)
	end

	-- ISLAND_LAYOUT_DIR=<dir> writes a kill on the open panel and an error on the closed chip at their peak.
	do
		local dir = os.getenv("ISLAND_LAYOUT_DIR")
		if dir then
			local layout = dofile(root .. "/tests/layout.lua")
			local function dump(name, make_world, kind, open_it)
				local addon, env, event, state, _, _, frames = make_world()
				addon.module.set("smart_island", "enabled", true)
				addon.module.set("smart_island", "reduced_motion", false)
				local top
				for _, frame in ipairs(frames) do if frame.name == "EverlookSmartIsland" then top = frame end end
				if open_it then
					addon.module.set("smart_island", "reduced_motion", true)
					top.scripts.OnClick(top, "LeftButton")
					addon.module.set("smart_island", "reduced_motion", false)
				end
				layout.settle(frames)
				state.time = 800
				env.Everlook.island.react(kind)
				state.time = 800.06
				for _, frame in ipairs(frames) do if frame.scripts and frame.scripts.OnUpdate and frame.parent and frame.parent.name == "EverlookSmartIsland" then frame.scripts.OnUpdate(frame, 0.06) end end
				local handle = assert(io.open(dir .. "/" .. name .. ".json", "w"))
				handle:write(layout.export(frames, top, env.GetTime()))
				handle:close()
			end
			dump("react_open", quest_world, "level", true)
			dump("react_closed", island_world, "error", false)
			dump("react_closed_kill", island_world, "kill", false)
		end
	end
end
