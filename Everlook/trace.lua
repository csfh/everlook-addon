local addonName, Everlook = ...

-- Where the time goes when the game loads or reloads. The core loads first
-- among the Everlook addons, so this file starts the clock, notes when each
-- addon finishes loading, how long each module spends starting, and when the
-- loading screen ends. Every load overwrites `EverlookDB.loadTrace`, and a short
-- summary of each load is kept in `EverlookDB.loadTraceHistory`, so a change
-- can be judged by comparing a few loads before and after it.
--
-- The clock is `debugprofilestop`, which keeps running through a loading
-- screen where `GetTime` stands still.

Everlook.trace = {}
local M = Everlook.trace

local MAX_MARKS = 150
local MAX_HISTORY = 8

local floor = math.floor

local function clock()
	if type(debugprofilestop) == "function" then
		return debugprofilestop()
	end
end

local began = clock()

local function tenths(ms)
	return floor(ms * 10 + 0.5) / 10
end

local ledger = {
	at = type(time) == "function" and time() or nil,
	marks = {},
	spans = {},
	counts = {},
}
M.ledger = ledger

local seen = {}

-- Milliseconds since this file loaded, or nil with no clock.
local function elapsed()
	local now = clock()
	return now and began and tenths(now - began) or nil
end

-- Notes that something happened now. A label already noted keeps its first time.
function M.stamp(label)
	local at = elapsed()
	if not at or seen[label] or #ledger.marks >= MAX_MARKS then
		return at
	end
	seen[label] = at
	ledger.marks[#ledger.marks + 1] = { label, at }
	return at
end

local function add(label, ms)
	local span = ledger.spans[label]
	if not span then
		span = { ms = 0, runs = 0 }
		ledger.spans[label] = span
	end
	span.ms = tenths(span.ms + ms)
	span.runs = span.runs + 1
end

local function finish_span(started, label, ...)
	if started then
		add(label, clock() - started)
	end
	return ...
end

-- Runs `fn(...)` and adds its time to `label`. Passes the results through, and
-- an error too, so wrapping a call changes nothing but the record.
function M.span(label, fn, ...)
	local started = clock()
	return finish_span(started, label, fn(...))
end

-- Counts something that is expensive in numbers, such as frames walked.
function M.count(label, amount)
	ledger.counts[label] = (ledger.counts[label] or 0) + (amount or 1)
end

-- What each load adds to the history.
local function summary(reload)
	local marks = {}
	for index = 1, #ledger.marks do
		marks[ledger.marks[index][1]] = ledger.marks[index][2]
	end
	local modules = 0
	for label, span in pairs(ledger.spans) do
		if label:sub(1, 7) == "module:" then
			modules = modules + span.ms
		end
	end
	local settings = ledger.spans.settings
	return {
		at = ledger.at,
		reload = reload,
		saved = marks["addon:" .. addonName] and marks.core_files and tenths(marks["addon:" .. addonName] - marks.core_files) or nil,
		login = marks.login,
		enter = marks.enter,
		done = marks.loading_done,
		modules = tenths(modules),
		settings = settings and settings.ms or nil,
	}
end

local reload
local logged

local function remember()
	if logged or not ledger.marks[1] then
		return
	end
	logged = true
	EverlookDB = EverlookDB or {}
	local history = EverlookDB.loadTraceHistory
	if type(history) ~= "table" then
		history = {}
		EverlookDB.loadTraceHistory = history
	end
	history[#history + 1] = summary(reload)
	while #history > MAX_HISTORY do
		table.remove(history, 1)
	end
end

if type(CreateFrame) == "function" then
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("ADDON_LOADED")
	frame:RegisterEvent("PLAYER_LOGIN")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:RegisterEvent("LOADING_SCREEN_DISABLED")
	frame:SetScript("OnEvent", function(_, event, first, second)
		if event == "ADDON_LOADED" then
			M.stamp("addon:" .. tostring(first))
		elseif event == "PLAYER_LOGIN" then
			M.stamp("login")
		elseif event == "PLAYER_ENTERING_WORLD" then
			if not seen.enter then
				reload = second == true
			end
			M.stamp("enter")
		elseif event == "LOADING_SCREEN_DISABLED" then
			-- Each zone change ends a loading screen. Only the first is the load.
			if not seen.loading_done then
				M.stamp("loading_done")
				remember()
			end
		end
	end)
end

-- The saved variables exist once this addon has loaded.
EventUtil.ContinueOnAddOnLoaded(addonName, function()
	EverlookDB = EverlookDB or {}
	EverlookDB.loadTrace = ledger
end)
