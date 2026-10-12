-- Holding the garbage collector while the game loads, and starting it again.
return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)

	-- A load: `opts` says what the saved settings are and whether the player is in.
	local function load(opts)
		opts = opts or {}
		local Everlook = { trace = { stamp = function() end, note = function() end } }
		local env = setmetatable({}, { __index = _G })
		env._G = env
		local game = { calls = {}, frames = {}, timers = {}, heap = 100 * 1024, notes = {}, registered = nil }
		env.Everlook = Everlook
		env.collectgarbage = function(what)
			game.calls[#game.calls + 1] = what
			if what == "count" then return game.heap end
		end
		env.CreateFrame = function()
			local frame = { events = {} }
			function frame:RegisterEvent(event) self.events[event] = true end
			function frame:SetScript(name, handler) self[name] = handler end
			game.frames[#game.frames + 1] = frame
			return frame
		end
		env.C_Timer = { After = function(_, fn) game.timers[#game.timers + 1] = fn end }
		env.IsLoggedIn = function() return opts.logged_in == true end
		Everlook.trace.note = function(key, value) game.notes[key] = value end
		Everlook.module = {
			enabled = function() return opts.enabled ~= false end,
			get = function() return opts.gc_window ~= false end,
			register = function(module) game.registered = module; return module end,
		}
		local chunk = assert(loadfile(source("optimize.lua")))
		setfenv(chunk, env)
		chunk("Everlook_Optimize")
		function game.count(what)
			local total = 0
			for _, call in ipairs(game.calls) do
				if call == what then total = total + 1 end
			end
			return total
		end
		function game.fire(event)
			local frame = game.frames[1]
			if frame then frame.OnEvent(frame, event) end
		end
		return Everlook.optimize, game
	end

	do
		local optimize, game = load()
		check("a load that has not logged in is held", game.count("stop") == 1 and optimize.held())
		check("and it listens for the ways a hold ends", game.frames[1].events.LOADING_SCREEN_DISABLED and game.frames[1].events.PLAYER_LOGOUT and #game.timers == 1)
		game.fire("ADDON_LOADED")
		check("a heap under the ceiling keeps the hold", optimize.held() and game.count("restart") == 0)
		game.fire("LOADING_SCREEN_DISABLED")
		check("the end of the loading screen starts the collector again, once", not optimize.held() and game.count("restart") == 1 and game.notes.gc == "loading_done")
		game.fire("LOADING_SCREEN_DISABLED")
		game.fire("PLAYER_LOGOUT")
		game.timers[1]()
		optimize.release("off")
		check("nothing starts it twice", game.count("restart") == 1)
		check("and it never runs a full collection", game.count("collect") == 0)
	end

	do
		local optimize, game = load()
		game.heap = 500 * 1024
		game.fire("PLAYER_ENTERING_WORLD")
		check("a heap past 400 MB starts the collector again", not optimize.held() and game.count("restart") == 1 and game.notes.gc == "ceiling")
	end

	do
		local optimize, game = load()
		game.fire("PLAYER_LOGOUT")
		check("logging out starts the collector again", not optimize.held() and game.count("restart") == 1 and game.notes.gc == "logout")
	end

	do
		local optimize, game = load()
		game.timers[1]()
		check("the timer starts the collector again if the loading screen never ends", not optimize.held() and game.count("restart") == 1 and game.notes.gc == "timer")
	end

	do
		local optimize, game = load()
		game.registered.apply(false)
		check("turning the module off starts the collector again", not optimize.held() and game.count("restart") == 1 and game.notes.gc == "off")
	end

	do
		local _, logged_in = load({ logged_in = true })
		check("a player who is already in is not held, since no loading screen is coming", logged_in.count("stop") == 0)
		local _, off = load({ enabled = false })
		check("a module that is off holds nothing", off.count("stop") == 0)
		local _, option_off = load({ gc_window = false })
		check("an option that is off holds nothing", option_off.count("stop") == 0)
	end

	-- What ships never asks for a full collection, which is a stall of its own.
	do
		local offenders = {}
		local listing = assert(io.popen('ls "' .. root .. '"'))
		for folder in listing:lines() do
			if folder:match("^Everlook[%w_]*$") then
				for line in io.lines(root .. "/" .. folder .. "/" .. folder .. ".toc") do
					local file = line:match("^([%w_]+)%.lua%s*$")
					if file then
						local handle = assert(io.open(root .. "/" .. folder .. "/" .. file .. ".lua", "r"))
						local text = handle:read("*a")
						handle:close()
						if text:find('collectgarbage%("collect"%)') or text:find("collectgarbage%('collect'%)") or text:find("collectgarbage%(%)") then
							offenders[#offenders + 1] = folder .. "/" .. file
						end
					end
				end
			end
		end
		listing:close()
		check("no shipped file runs a full garbage collection" .. (#offenders > 0 and (": " .. table.concat(offenders, ", ")) or ""), #offenders == 0)
	end
end
