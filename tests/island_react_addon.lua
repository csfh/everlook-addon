-- Everlook_IslandReactions: what it decides is worth a flash, and what it leaves alone.
return function(root, check, island_world)
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

	-- The addon that decides what deserves a flash.
	do
		local addon, env, event, state, _, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		env.COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience."
		env.LOOT_ITEM_SELF = "You receive loot: %s."
		env.LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
		local function flashes(fire, at)
			state.time = at
			fire()
			state.time = at + 0.06
			for _, frame in ipairs(frames) do if frame.scripts and frame.scripts.OnUpdate and frame.parent and frame.parent.name == "EverlookSmartIsland" then frame.scripts.OnUpdate(frame, 0.06) end end
			local seen = lit(frames, 173 / 255) > 0 or lit(frames, 128 / 255, 230 / 255) > 0 or lit(frames, 1, 210 / 255) > 0
			state.time = at + 5
			for _, frame in ipairs(frames) do if frame.scripts and frame.scripts.OnUpdate and frame.parent and frame.parent.name == "EverlookSmartIsland" then frame.scripts.OnUpdate(frame, 5) end end
			return seen
		end
		check("a level up flashes by default", flashes(function() event("PLAYER_LEVEL_UP", 12) end, 500))
		addon.module.set("smart_island", "react_level", false)
		check("and not once that is turned off", not flashes(function() event("PLAYER_LEVEL_UP", 12) end, 510))
		check("a kill that gives experience does not flash until it is turned on", not flashes(function() event("CHAT_MSG_COMBAT_XP_GAIN", "Boar dies, you gain 50 experience.") end, 520))
		addon.module.set("smart_island", "react_kill", true)
		check("it flashes once it is on", flashes(function() event("CHAT_MSG_COMBAT_XP_GAIN", "Boar dies, you gain 50 experience.") end, 530))
		check("experience that is not a kill does not flash", not flashes(function() event("CHAT_MSG_COMBAT_XP_GAIN", "You gain 50 experience.") end, 540))
		check("a message the client hides does not flash", not flashes(function() event("CHAT_MSG_COMBAT_XP_GAIN", nil) end, 550))
		addon.module.set("smart_island", "react_loot", true)
		check("your own loot flashes", flashes(function() event("CHAT_MSG_LOOT", "You receive loot: [Linen Cloth].") end, 560))
		check("another player's loot does not", not flashes(function() event("CHAT_MSG_LOOT", "Thrall receives loot: [Linen Cloth].") end, 570))
	end
end
