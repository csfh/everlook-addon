-- The load trace: when each part of a load happened, and what it cost.
return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)

	local function load(setup)
		local Everlook = {}
		local env = setmetatable({}, { __index = _G })
		env._G = env
		local game = { now = 0, frames = {}, loaded = {} }
		env.debugprofilestop = function()
			return game.now
		end
		env.time = function()
			return 1700000000
		end
		env.EventUtil = {
			ContinueOnAddOnLoaded = function(name, callback)
				game.loaded[name] = callback
			end,
		}
		env.CreateFrame = function()
			local frame = { events = {} }
			function frame:RegisterEvent(event)
				self.events[event] = true
			end
			function frame:UnregisterEvent(event)
				self.events[event] = nil
			end
			function frame:SetScript(name, handler)
				self[name] = handler
			end
			game.frames[#game.frames + 1] = frame
			return frame
		end
		if setup then
			setup(env, game)
		end
		local chunk = assert(loadfile(source("trace.lua")))
		setfenv(chunk, env)
		chunk("Everlook", Everlook)
		game.fire = function(event, ...)
			game.frames[1].OnEvent(game.frames[1], event, ...)
		end
		return Everlook.trace, game, env
	end

	do
		local trace, game, env = load()
		local frame = game.frames[1]
		check("it listens for the steps of a load",
			frame.events.ADDON_LOADED and frame.events.PLAYER_LOGIN and frame.events.PLAYER_ENTERING_WORLD and frame.events.LOADING_SCREEN_DISABLED)
		game.now = 5
		trace.stamp("core_files")
		game.now = 9.04
		game.fire("ADDON_LOADED", "Everlook")
		check("a stamp is the time since the file loaded, in tenths of a millisecond",
			trace.ledger.marks[1][1] == "core_files" and trace.ledger.marks[1][2] == 5 and trace.ledger.marks[2][1] == "addon:Everlook" and trace.ledger.marks[2][2] == 9)
		game.now = 20
		trace.stamp("core_files")
		check("a label keeps its first time", #trace.ledger.marks == 2 and trace.ledger.marks[1][2] == 5)
		game.loaded.Everlook()
		check("the saved variables hold this load's ledger", env.EverlookDB.loadTrace == trace.ledger)

		local function work(a, b)
			game.now = game.now + 2.5
			return a + b, "second"
		end
		local sum, word = trace.span("module:x", work, 1, 2)
		trace.span("module:x", work, 1, 2)
		trace.span("settings", work, 1, 2)
		check("a span passes the results through and adds up the time", sum == 3 and word == "second"
			and trace.ledger.spans["module:x"].ms == 5 and trace.ledger.spans["module:x"].runs == 2)
		trace.count("fonts_frames", 40)
		trace.count("fonts_frames", 2)
		trace.count("fonts_passes")
		check("a count adds up", trace.ledger.counts.fonts_frames == 42 and trace.ledger.counts.fonts_passes == 1)

		check("a mark carries what the Lua heap held", type(trace.ledger.memory.core_files) == "number" and trace.ledger.memory.core_files > 0)
		trace.note("gc", "loading_done")
		game.now = 30
		game.fire("PLAYER_LOGIN")
		game.now = 40
		game.fire("PLAYER_ENTERING_WORLD", false, true)
		game.now = 50
		game.fire("LOADING_SCREEN_DISABLED")
		local history = env.EverlookDB.loadTraceHistory
		check("the end of the loading screen adds one line to the history", #history == 1)
		local line = history[1]
		check("it says how long each step took", line.reload == true and line.saved == 4 and line.login > 0 and line.enter > line.login and line.done > line.enter)
		check("it adds up what the modules spent starting, and the settings", line.modules == 5 and line.settings == 2.5)
		check("it says when a module held the collector", line.gc == "loading_done")
		game.fire("LOADING_SCREEN_DISABLED")
		game.fire("PLAYER_ENTERING_WORLD", false, false)
		check("a later zone change is not another load", #env.EverlookDB.loadTraceHistory == 1 and line.reload == true)
	end

	do
		local trace, game, env = load()
		env.EverlookDB = { loadTraceHistory = {} }
		for index = 1, 12 do
			env.EverlookDB.loadTraceHistory[index] = { at = index }
		end
		game.now = 1
		game.fire("PLAYER_LOGIN")
		game.fire("LOADING_SCREEN_DISABLED")
		local history = env.EverlookDB.loadTraceHistory
		check("the history keeps the last eight loads", #history == 8 and history[1].at == 6)
	end

	do
		local trace, game, env = load(function(env)
			env.debugprofilestop = nil
		end)
		local result = trace.span("module:none", function(value)
			return value * 2
		end, 21)
		trace.stamp("anything")
		game.fire("LOADING_SCREEN_DISABLED")
		check("with no clock nothing is recorded and the work still happens", result == 42 and trace.ledger.marks[1] == nil and next(trace.ledger.spans) == nil and rawget(env, "EverlookDB") == nil)
	end
end
