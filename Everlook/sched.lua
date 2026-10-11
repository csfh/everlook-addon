local _, Everlook = ...

-- One budget per frame for every piece of work that does not have to happen
-- now.
--
-- A task is a function that does a little work and says whether more is left.
-- All tasks share one frame and one time limit, so a bag scan, a page save and
-- a search cannot each take their millisecond in the same frame and add up.
-- The limit is halved under 30 frames a second. The tasks take turns, and the
-- one that goes first changes every frame, so none is starved.
--
-- A task's step is given the time it may use, in milliseconds, and must do at
-- least one piece of work whatever the number, so a client with no clock still
-- moves. It returns true while work remains, false when done (`wake` starts it
-- again), or a number of seconds to sleep before it is asked again.
--
-- A step that raises an error is reported once and asked again. After three in
-- a row the task rests for a few seconds, so a broken step never costs a frame
-- each frame.

Everlook.sched = {}
local M = Everlook.sched

local floor = math.floor

local BUDGET_MS = 1.5
local SLOW_BUDGET_MS = 0.75
local SLOW_FPS = 30
local MAX_ERRORS = 3
local ERROR_REST = 5
local MAX_JOBS = 2000
local FLUSH_TURNS = 1000

local tasks = {}
local by_name = {}
local runnable = {}
local turn = 0
local frame

local function clock()
	if type(debugprofilestop) == "function" then
		return debugprofilestop()
	end
end

local function now()
	if type(GetTime) == "function" then
		return GetTime()
	end
end

local function in_combat()
	return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

local function report(name, err)
	if type(geterrorhandler) == "function" then
		geterrorhandler()("Everlook " .. name .. ": " .. tostring(err))
	end
end

-- The time one frame may spend on all tasks together, in milliseconds.
function M.budget()
	local fps = type(GetFramerate) == "function" and GetFramerate() or 60
	return (fps or 60) < SLOW_FPS and SLOW_BUDGET_MS or BUDGET_MS
end

local function show()
	if frame == nil then
		if type(CreateFrame) ~= "function" then
			frame = false
		else
			frame = CreateFrame("Frame")
			frame:SetScript("OnUpdate", function()
				M.tick()
			end)
		end
	end
	if frame then
		frame:Show()
	end
end

local function any_active()
	for index = 1, #tasks do
		if tasks[index].active then
			return true
		end
	end
	return false
end

local function wake(task)
	task.active = true
	task.woken = true
	task.asleep_until = 0
	show()
end

local function run_step(task, limit_ms)
	local began = clock()
	task.woken = false
	local ok, more = pcall(task.step, limit_ms)
	local spent = began and clock() - began or 0
	local stats = task.stats
	stats.runs = stats.runs + 1
	stats.ms = stats.ms + spent
	if spent > stats.worst then
		stats.worst = spent
	end
	if not ok then
		stats.errors = stats.errors + 1
		task.failed = task.failed + 1
		if not task.reported then
			task.reported = true
			report(task.name, more)
		end
		if task.failed >= MAX_ERRORS then
			task.failed = 0
			local t = now()
			if t then
				task.asleep_until = t + ERROR_REST
			else
				task.active = false
			end
		end
		return
	end
	task.failed = 0
	if more == true then
		return
	end
	if type(more) == "number" and now() then
		if not task.woken then
			task.asleep_until = now() + more
		end
		return
	end
	if not task.woken then
		task.active = false
	end
end

-- Registers a task. `opts.step(limit_ms)` does the work. `opts.combat` is
-- "pause" (the default: no work in combat) or "run". `opts.logout` is "flush"
-- (it must finish before the variables are saved, see `flush`) or "drop" (the
-- default: whatever is left is not worth the wait). Asking for a name again
-- replaces the task. Returns a handle: `wake()` says there is work.
function M.task(name, opts)
	local task = by_name[name]
	if task then
		task.step, task.combat, task.logout = opts.step, opts.combat or "pause", opts.logout or "drop"
		task.active = false
	else
		task = {
			name = name,
			step = opts.step,
			combat = opts.combat or "pause",
			logout = opts.logout or "drop",
			active = false,
			woken = false,
			asleep_until = 0,
			failed = 0,
			stats = { runs = 0, ms = 0, worst = 0, errors = 0, dropped = 0 },
		}
		by_name[name] = task
		tasks[#tasks + 1] = task
	end
	return {
		name = name,
		wake = function()
			wake(task)
		end,
	}
end

-- One pass over the tasks. Called by the frame, and by tests.
function M.tick()
	local count = #tasks
	if count == 0 then
		if frame then
			frame:Hide()
		end
		return
	end
	local t = now() or 0
	local combat = in_combat()
	for index = #runnable, 1, -1 do
		runnable[index] = nil
	end
	for offset = 0, count - 1 do
		local task = tasks[(turn + offset) % count + 1]
		if task.active and task.asleep_until <= t and not (combat and task.combat == "pause") then
			runnable[#runnable + 1] = task
		end
	end
	turn = (turn + 1) % count
	local budget = M.budget()
	local began = clock()
	local total = #runnable
	for index = 1, total do
		local limit = 0
		if began then
			local left = budget - (clock() - began)
			if left <= 0 then
				break
			end
			limit = left / (total - index + 1)
		end
		run_step(runnable[index], limit)
	end
	if frame and not any_active() then
		frame:Hide()
	end
end

-- Runs every "flush" task to the end, or until `limit_ms` is up. For logout,
-- when what is queued would otherwise be lost. Combat and sleep are ignored,
-- and a task whose step fails is left alone for the rest of the call. True
-- when nothing is left.
function M.flush(limit_ms)
	local began = clock()
	local broken = {}
	for _ = 1, began and 1e9 or FLUSH_TURNS do
		local left = false
		for index = 1, #tasks do
			local task = tasks[index]
			if task.active and task.logout == "flush" and not broken[task] then
				local remaining = began and math.max(0.1, limit_ms - (clock() - began)) or 0
				local errors = task.stats.errors
				run_step(task, remaining)
				if task.stats.errors > errors then
					broken[task] = true
				end
				left = left or (task.active and not broken[task])
			end
		end
		if not left then
			return true
		end
		if began and clock() - began >= limit_ms then
			return false
		end
	end
	return false
end

-- (name -> { runs, ms, worst, errors, dropped }), for the saved variables.
function M.stats()
	local out = {}
	for index = 1, #tasks do
		local task = tasks[index]
		local s = task.stats
		out[task.name] = {
			runs = s.runs,
			ms = floor(s.ms * 100 + 0.5) / 100,
			worst = floor(s.worst * 100 + 0.5) / 100,
			errors = s.errors,
			dropped = s.dropped,
		}
	end
	return out
end

-- Jobs for things that happen once, such as an event that needs a lookup. A
-- job with a key replaces one waiting under the same key, so a burst of the
-- same event is worked out once, with the latest values. With no frame to run
-- it, the job runs on the spot.
local jobs = {}
local first, last = 1, 0
local waiting = {}
local deferred

local function next_job(limit_ms)
	local began = clock()
	while first <= last do
		local job = jobs[first]
		jobs[first] = nil
		first = first + 1
		if job.key ~= nil then
			waiting[job.key] = nil
		end
		local ok, err = pcall(job.fn, unpack(job.args, 1, job.n))
		if not ok then
			report("job", err)
		end
		if not began or clock() - began >= limit_ms then
			break
		end
	end
	if first > last then
		first, last = 1, 0
		return false
	end
	return true
end

function M.defer(key, fn, ...)
	if type(CreateFrame) ~= "function" then
		fn(...)
		return
	end
	if not deferred then
		deferred = M.task("defer", { step = next_job, combat = "pause", logout = "flush" })
	end
	local queued = key ~= nil and waiting[key]
	if queued then
		queued.fn, queued.args, queued.n = fn, { ... }, select("#", ...)
		return
	end
	if last - first + 1 >= MAX_JOBS then
		local dropped = jobs[first]
		jobs[first] = nil
		first = first + 1
		if dropped.key ~= nil then
			waiting[dropped.key] = nil
		end
		by_name.defer.stats.dropped = by_name.defer.stats.dropped + 1
	end
	local job = { key = key, fn = fn, args = { ... }, n = select("#", ...) }
	last = last + 1
	jobs[last] = job
	if key ~= nil then
		waiting[key] = job
	end
	deferred.wake()
end
