-- ensure and release for the game's own settings, on a stand-in for the toggle calls.
-- What the game does with a changed setting is not tested here.
return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)

	local function world(options)
		options = options or {}
		local env = setmetatable({}, { __index = _G })
		env._G = env
		env.EverlookDB = options.db or {}
		env.UnitGUID = function() return options.guid or "Player-1" end
		local frames = {}
		env.CreateFrame = function()
			local frame = { events = {}, scripts = {} }
			function frame:RegisterEvent(event) self.events[event] = true end
			function frame:UnregisterEvent(event) self.events[event] = nil end
			function frame:SetScript(name, callback) self.scripts[name] = callback end
			frames[#frames + 1] = frame
			return frame
		end
		local state = { time = 100, bars = options.bars or { false, false, true, false, false, false, false }, calls = {}, timers = {}, combat = false }
		env.GetTime = function() return state.time end
		env.InCombatLockdown = function() return state.combat end
		env.C_Timer = { After = function(delay, callback) state.timers[#state.timers + 1] = { delay = delay, callback = callback } end }
		env.GetActionBarToggles = function() return unpack(state.bars, 1, 7) end
		env.SetActionBarToggles = function(...)
			state.calls[#state.calls + 1] = { ... }
			state.bars = { ... }
		end
		for key, value in pairs(options.extra or {}) do env[key] = value end
		local addon = {}
		env.Everlook = addon
		local chunk = assert(loadfile(source("blizzard_settings")))
		setfenv(chunk, env)
		chunk("Everlook", addon)
		-- The module file loads at time 100. The test then lets time pass.
		function state.enter_world()
			for _, frame in ipairs(frames) do
				if frame.events.PLAYER_ENTERING_WORLD then frame.scripts.OnEvent(frame, "PLAYER_ENTERING_WORLD") end
			end
		end
		if options.entered ~= false then state.enter_world() end
		state.time = options.time or 100
		return addon.blizzard_settings, state, env
	end

	do
		local settings, state = world({ time = 110 })
		check("a setting it does not know is refused", settings.ensure("action_bar_9", true) == false and select(2, settings.ensure("nonsense", true)) == "unknown")
		check("a bar that is off is turned on", settings.ensure("action_bar_2", true) == true and state.bars[1] == true)
		check("the other bars go back as they were read", #state.calls == 1 and state.bars[3] == true and state.bars[2] == false and state.bars[7] == false)
		check("one call carries all seven", select("#", unpack(state.calls[1], 1, 7)) == 7)
		check("a bar already right makes no call", settings.ensure("action_bar_5", false) == true and #state.calls == 1)
		check("release puts back the bar it changed", settings.release("action_bar_2") == true and state.bars[1] == false and #state.calls == 2)
		check("releasing a second time does nothing", settings.release("action_bar_2") == true and #state.calls == 2)
		check("a bar it never changed is not released", settings.release("action_bar_4") == true and #state.calls == 2 and state.bars[3] == true)
	end

	do
		-- A bar that was on already is never turned off by release.
		local settings, state = world({ time = 110, bars = { true, true, false, false, false, false, false } })
		settings.ensure("action_bar_2", true)
		check("a bar that was already right makes no call", #state.calls == 0)
		check("and release leaves it on", settings.release("action_bar_2") == true and state.bars[1] == true and #state.calls == 0)
	end

	do
		-- The player changed it again meanwhile: release leaves their choice alone.
		local settings, state, env = world({ time = 110 })
		settings.ensure("action_bar_2", true)
		local count = #state.calls
		state.bars[1] = false
		check("release leaves a setting the player has changed since", settings.release("action_bar_2") == true and state.bars[1] == false and #state.calls == count)
		check("and forgets it", env.EverlookDB.qol.blizzard_settings.changed["Player-1"].action_bar_2 == nil)
	end

	do
		local db = {}
		local settings, state = world({ db = db, time = 110, guid = "Player-A" })
		settings.ensure("action_bar_2", true)
		check("what it changed is remembered for that character only", db.qol.blizzard_settings.changed["Player-A"].action_bar_2 ~= nil and db.qol.blizzard_settings.changed["Player-B"] == nil)
		local other = world({ db = db, time = 110, guid = "Player-B", bars = { true, false, true, false, false, false, false } })
		check("another character has no change to put back", other.release("action_bar_2") == true)
		check("and the first character's record is still there", db.qol.blizzard_settings.changed["Player-A"].action_bar_2 ~= nil)
		check("the first character's setting is untouched by the other", state.bars[1] == true)
	end

	do
		-- A long loading screen does not count: the clock starts when the character enters the world.
		local settings, state = world({ time = 130, entered = false })
		local ok, reason = settings.ensure("action_bar_2", true)
		check("a long loading screen does not make the values trustworthy", ok == false and reason == "waiting" and #state.calls == 0)
		local ran = 0
		settings.when_settled(function() ran = ran + 1 end)
		check("a wait before the world is entered has no timer yet", #state.timers == 0)
		state.enter_world()
		check("entering the world starts one", #state.timers == 1 and ran == 0)
		state.time = 133
		state.timers[1].callback()
		check("a timer that fires too early looks again", ran == 0 and #state.timers == 2)
		state.time = 136
		state.timers[2].callback()
		check("and the wait runs once five seconds have passed", ran == 1 and settings.ensure("action_bar_2", true) == true)
		state.time = 500
		state.enter_world()
		check("a later loading screen does not start the wait again", settings.release("action_bar_2") == true and state.bars[1] == false)
	end

	do
		local settings, state = world({ time = 101 })
		local ok, reason = settings.ensure("action_bar_2", true)
		check("just after login the game's values are not trusted", ok == false and reason == "waiting" and #state.calls == 0)
		local ran = 0
		settings.when_settled(function() ran = ran + 1 end)
		settings.when_settled(function() ran = ran + 1 end)
		check("one timer serves every wait", #state.timers == 1 and state.timers[1].delay == 5)
		state.time = 106
		state.timers[1].callback()
		check("every wait runs once the game has settled", ran == 2)
		check("and then the setting can be changed", settings.ensure("action_bar_2", true) == true)
		settings.when_settled(function() ran = ran + 1 end)
		check("a wait after that runs at once", ran == 3 and #state.timers == 1)
	end

	do
		local settings, state = world({ time = 110 })
		state.combat = true
		local ok, reason = settings.ensure("action_bar_2", true)
		check("nothing is changed in combat", ok == false and reason == "combat" and #state.calls == 0)
		check("nor put back", settings.release("action_bar_2") == true and #state.calls == 0)

		local unreadable = world({ time = 110, bars = { "secret", false, false, false, false, false, false } })
		local failed, why = unreadable.ensure("action_bar_2", true)
		check("a value that is not plain on or off is refused", failed == false and why == "unreadable")

		local missing, missing_state = world({ time = 110, extra = { SetActionBarToggles = false } })
		local gone, gone_why = missing.ensure("action_bar_2", true)
		check("a client without the calls is refused", gone == false and gone_why == "unavailable" and missing_state.bars[1] == false)

		local nameless = world({ time = 110, extra = { UnitGUID = function() return nil end } })
		local lost, lost_why = nameless.ensure("action_bar_2", true)
		check("a character it cannot name is refused", lost == false and lost_why == "unknown character")
		check("a wanted value that is not on or off is refused", select(2, world({ time = 110 }).ensure("action_bar_2", "yes")) == "invalid")
	end
end
