-- The scheduler: one time limit a frame for every task that can wait.
return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)

	-- `cost` is what each piece of work takes, in milliseconds of the fake clock.
	local function load(setup)
		local Everlook = {}
		local env = setmetatable({}, { __index = _G })
		env._G = env
		local now = 0
		local game = { fps = 60, combat = false, errors = {}, frames = {} }
		env.debugprofilestop = function()
			return now
		end
		env.GetFramerate = function()
			return game.fps
		end
		env.InCombatLockdown = function()
			return game.combat
		end
		env.GetTime = function()
			return game.time or 0
		end
		env.geterrorhandler = function()
			return function(err)
				game.errors[#game.errors + 1] = err
			end
		end
		env.CreateFrame = function()
			local frame = { shown = false }
			function frame:SetScript(name, handler)
				self[name] = handler
			end
			function frame:Show()
				self.shown = true
			end
			function frame:Hide()
				self.shown = false
			end
			game.frames[#game.frames + 1] = frame
			return frame
		end
		if setup then
			setup(env, game)
		end
		local chunk = assert(loadfile(source("sched.lua")))
		setfenv(chunk, env)
		chunk("Everlook", Everlook)
		game.spend = function(ms)
			now = now + ms
		end
		return Everlook.sched, game
	end

	-- A task with `pieces` pieces of work that each cost `cost`. It stops at its limit.
	local function worker(sched, game, name, pieces, cost, opts)
		local state = { name = name, left = pieces, done = 0, limits = {} }
		opts = opts or {}
		opts.step = function(limit)
			state.limits[#state.limits + 1] = limit
			local used = 0
			repeat
				state.left = state.left - 1
				state.done = state.done + 1
				game.spend(cost)
				used = used + cost
			until state.left <= 0 or used >= limit
			return state.left > 0
		end
		state.handle = sched.task(name, opts)
		state.handle.wake()
		return state
	end

	-- Tasks share a frame: two that could each take it all take half each.
	do
		local sched, game = load()
		local a = worker(sched, game, "a", 100, 0.25)
		local b = worker(sched, game, "b", 100, 0.25)
		sched.tick()
		check("a frame's budget is shared between the tasks", a.done + b.done <= 8 and a.done >= 3 and b.done >= 3)
		check("the first task is given its share, not the whole frame", a.limits[1] == 0.75 and b.limits[1] > 0 and b.limits[1] <= 0.75 + 0.01)
		sched.tick()
		check("the task that goes first changes each frame", b.limits[2] ~= nil and a.limits[2] ~= nil)
		check("the frame shows while work waits", game.frames[1].shown == true)
	end

	-- A task that finishes early leaves the rest of the frame to the others.
	do
		local sched, game = load()
		local short = worker(sched, game, "short", 1, 0.1)
		local long = worker(sched, game, "long", 100, 0.1)
		sched.tick()
		check("time a task does not use goes to the next", short.done == 1 and long.done >= 10)
	end

	-- One task cannot take every frame from another.
	do
		local sched, game = load()
		local greedy = worker(sched, game, "greedy", 1000, 2)
		local small = worker(sched, game, "small", 5, 0.1)
		for _ = 1, 4 do
			sched.tick()
		end
		check("a task that overruns still lets the others have a turn", small.done > 0)
	end

	-- Slow frames get half.
	do
		local sched, game = load()
		check("the budget is 1.5 ms at a good frame rate", sched.budget() == 1.5)
		game.fps = 20
		check("the budget is halved below 30 frames a second", sched.budget() == 0.75)
	end

	-- Done work hides the frame; waking starts it again.
	do
		local sched, game = load()
		local one = worker(sched, game, "one", 1, 0.1)
		sched.tick()
		check("a finished task is not asked again", one.done == 1)
		check("the frame hides when no task has work", game.frames[1].shown == false)
		one.left = 1
		one.handle.wake()
		check("waking shows the frame", game.frames[1].shown == true)
		sched.tick()
		check("a woken task runs again", one.done == 2)
	end

	-- A wake inside the step is not lost when the step says it is done.
	do
		local sched, game = load()
		local runs = 0
		local handle
		handle = sched.task("again", {
			step = function()
				runs = runs + 1
				if runs == 1 then
					handle.wake()
				end
				return false
			end,
		})
		handle.wake()
		sched.tick()
		sched.tick()
		sched.tick()
		check("a wake during the step keeps the task going", runs == 2)
	end

	-- A wake during a step that asks to sleep is not lost.
	do
		local sched, game = load()
		local runs = 0
		local handle
		handle = sched.task("napping_woken", {
			step = function()
				runs = runs + 1
				if runs == 1 then
					handle.wake()
				end
				return 10
			end,
		})
		handle.wake()
		game.time = 100
		sched.tick()
		sched.tick()
		check("a wake during a step that asks to sleep wins", runs == 2)
	end

	-- Combat.
	do
		local sched, game = load()
		local paused = worker(sched, game, "paused", 3, 0.1)
		local running = worker(sched, game, "running", 3, 0.1, { combat = "run" })
		game.combat = true
		sched.tick()
		check("a task that pauses in combat does no work", paused.done == 0)
		check("a task that runs in combat does", running.done == 3)
		check("the frame stays while a task waits for combat to end", game.frames[1].shown == true)
		game.combat = false
		sched.tick()
		check("work resumes after combat", paused.done == 3)
	end

	-- A step that returns a number sleeps that long.
	do
		local sched, game = load()
		local runs = 0
		local handle = sched.task("napping", {
			step = function()
				runs = runs + 1
				return 10
			end,
		})
		handle.wake()
		game.time = 100
		sched.tick()
		sched.tick()
		check("a task that asks for a pause is left alone for that long", runs == 1)
		game.time = 111
		sched.tick()
		check("then it is asked again", runs == 2)
	end

	-- Errors.
	do
		local sched, game = load()
		local order = {}
		local handle = sched.task("broken", {
			step = function()
				order[#order + 1] = "broken"
				error("boom")
			end,
		})
		local fine = worker(sched, game, "fine", 5, 0.1)
		handle.wake()
		sched.tick()
		check("a step that errors does not stop the others", fine.done > 0)
		check("the error is reported", #game.errors == 1 and game.errors[1]:find("boom", 1, true) ~= nil)
		sched.tick()
		sched.tick()
		check("the error is reported once", #game.errors == 1)
		local seen = #order
		game.time = 1
		sched.tick()
		sched.tick()
		check("a task that fails three times in a row rests", #order == seen and seen == 3)
		game.time = 7
		sched.tick()
		check("and is tried again after the rest", #order == 4)
		check("failures are counted", sched.stats().broken.errors == 4)
	end

	-- Stats.
	do
		local sched, game = load()
		local counted = worker(sched, game, "counted", 4, 0.5, { combat = "run" })
		sched.tick()
		sched.tick()
		local stats = sched.stats().counted
		check("time and runs are counted for each task", stats.runs == 2 and stats.ms == 2 and stats.worst == 1.5 and stats.errors == 0)
	end

	-- Flush.
	do
		local sched, game = load()
		local must = worker(sched, game, "must", 40, 0.5, { logout = "flush", combat = "run" })
		local drop = worker(sched, game, "drop", 40, 0.5)
		game.combat = true
		check("flush finishes the work that must be saved", sched.flush(1000) == true and must.left == 0)
		check("flush leaves the rest", drop.left == 40)
	end
	do
		local sched, game = load()
		local must = worker(sched, game, "must", 100, 1, { logout = "flush" })
		check("flush stops at its limit", sched.flush(10) == false and must.left > 0 and must.left < 100)
	end

	do
		local sched, game = load()
		local bad = sched.task("bad", {
			step = function()
				game.spend(1)
				error("flush boom")
			end,
			logout = "flush",
		})
		bad.wake()
		local good = worker(sched, game, "good", 20, 0.5, { logout = "flush" })
		check("flush finishes a good task next to a broken one", sched.flush(400) == true and good.left == 0)
		check("and does not spend the limit on the broken one", sched.stats().bad.runs <= 2 and #game.errors == 1)
	end

	-- Deferred jobs.
	do
		local sched, game = load()
		local ran = {}
		sched.defer(nil, function(...)
			ran[#ran + 1] = { ... }
		end, 1, 2)
		check("a deferred job waits for a frame", #ran == 0)
		sched.tick()
		check("it runs with the values it was given", #ran == 1 and ran[1][1] == 1 and ran[1][2] == 2)
		sched.tick()
		check("and once", #ran == 1)
		check("the frame hides after the jobs", game.frames[1].shown == false)
	end
	do
		local sched, game = load()
		local seen = {}
		local function note(value)
			seen[#seen + 1] = value
		end
		sched.defer("spell", note, "first")
		sched.defer("other", note, "kept")
		sched.defer("spell", note, "latest")
		sched.tick()
		check("a job under the same key is replaced by the latest", #seen == 2 and seen[1] == "latest" and seen[2] == "kept")
	end
	do
		local sched, game = load()
		local seen = {}
		sched.defer(nil, function()
			error("bad job")
		end)
		sched.defer(nil, function()
			seen[#seen + 1] = "next"
		end)
		sched.tick()
		check("a job that errors does not stop the next", seen[1] == "next" and #game.errors == 1)
	end
	do
		local sched, game = load()
		local count = 0
		for _ = 1, 2100 do
			sched.defer(nil, function()
				count = count + 1
			end)
		end
		local guard = 0
		while game.frames[1].shown and guard < 5000 do
			sched.tick()
			guard = guard + 1
		end
		check("a long line of jobs keeps the newest", count == 2000 and sched.stats().defer.dropped == 100)
	end
	do
		local sched, game = load()
		local seen = {}
		sched.defer(nil, function()
			seen[#seen + 1] = 1
		end)
		game.combat = true
		sched.tick()
		check("deferred jobs wait out combat", #seen == 0)
		check("and are run by a flush at logout", sched.flush(100) == true and #seen == 1)
	end

	-- No frame: the work is done on the spot.
	do
		local sched = load(function(env)
			env.CreateFrame = false
		end)
		local seen = {}
		sched.defer("key", function(value)
			seen[#seen + 1] = value
		end, "now")
		check("with no frame a job runs at once", seen[1] == "now")
	end

	-- No clock: every task moves one piece a frame.
	do
		local sched, game = load(function(env)
			env.debugprofilestop = false
		end)
		local a = worker(sched, game, "a", 3, 0, { logout = "flush" })
		local b = worker(sched, game, "b", 3, 0)
		sched.tick()
		check("with no clock each task does one piece a frame", a.done == 1 and b.done == 1)
		check("and flush still finishes", sched.flush(100) == true and a.left == 0)
	end
end
