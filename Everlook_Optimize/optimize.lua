local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "optimize"

-- While the game loads, Lua allocates thousands of tables and strings that
-- nothing frees until later, and the collector spends part of the loading
-- screen walking them. With this on, the collector is stopped as this file
-- loads and started again when the loading screen ends. It is always started
-- again, by whichever of these comes first: the end of the loading screen, a
-- heap past the ceiling, a timer, logging out, or turning this off. It never
-- runs a full collection.
local CEILING_KB = 400 * 1024
local FALLBACK_SECONDS = 8

local held = false
local frame

local function release(reason)
	if not held then return end
	held = false
	collectgarbage("restart")
	local trace = Everlook.trace
	if trace then
		trace.stamp("gc_release")
		trace.note("gc", reason)
	end
end

local function on_event(_, event)
	if not held then return end
	if event == "LOADING_SCREEN_DISABLED" then
		release("loading_done")
	elseif event == "PLAYER_LOGOUT" then
		release("logout")
	elseif collectgarbage("count") > CEILING_KB then
		release("ceiling")
	end
end

local function hold()
	if held or type(collectgarbage) ~= "function" then return end
	held = true
	collectgarbage("stop")
	-- Only a load that holds the collector needs to listen.
	if not frame and CreateFrame then
		frame = CreateFrame("Frame")
		for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "LOADING_SCREEN_DISABLED", "PLAYER_LOGOUT" }) do
			frame:RegisterEvent(event)
		end
		frame:SetScript("OnEvent", on_event)
	end
	local trace = Everlook.trace
	if trace then trace.stamp("gc_hold") end
	if C_Timer and C_Timer.After then
		C_Timer.After(FALLBACK_SECONDS, function() release("timer") end)
	end
end

Everlook.optimize = { held = function() return held end, release = release }

module.register({
	addon = addon_name, page = "loading", order = 90,
	id = id, name = "Load faster",
	description = "Holds Lua's garbage collector while the game loads and starts it again when the loading screen ends, so a login or a reload spends less of its loading screen collecting. It takes effect from the next load, and it is only a gain if the Performance page shows a shorter load with it on than off. The collector starts again at the end of the loading screen, when the heap passes 400 MB, after eight seconds, on logout, and when this is turned off. Everlook never runs a full collection.",
	options = { gc_window = { name = "Hold the garbage collector while loading", default = true, description = "Stops Lua's garbage collector from the moment this loads until the loading screen ends. Turn it off to keep the module and leave the collector alone." } },
	apply = function(enabled)
		if not enabled or not module.get(id, "gc_window") then release("off") end
	end,
})

-- The saved settings are in place once this file runs, so the first load can
-- start holding at once. Only a load that has not logged in yet is held, since
-- no loading screen may end after that.
if module.enabled(id) and module.get(id, "gc_window") and not (IsLoggedIn and IsLoggedIn()) then
	hold()
end
