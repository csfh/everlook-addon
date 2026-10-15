-- The where-am-I text: formatting on its own, then reading the game.
return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)
	local function load(extra)
		local Everlook = { module = { modules = {}, enabled = function() return false end } }
		local env = setmetatable({}, { __index = _G })
		env._G = env
		for key, value in pairs(extra or {}) do env[key] = value end
		local chunk = assert(loadfile(source("where")))
		setfenv(chunk, env)
		chunk("Everlook", Everlook)
		return Everlook, env
	end

	local addon = load()
	local lines = addon.where.lines({
		core = "0.28.0", build = "70374", locale = "enUS", toc = 16001, map_id = 1429, map_name = "Elwynn Forest", x = 0.4871, y = 0.6523,
		modules = { { id = "bags", enabled = true, version = "0.28.0" }, { id = "nameplates", enabled = false, version = "0.27.0" }, { id = "map_pins", enabled = true } },
	})
	check("the first line names the version, the build and the locale", lines[1] == "Everlook 0.28.0 on client build 70374 (enUS, interface 16001)")
	check("the map line names the zone, id and position", lines[2] == "Map Elwynn Forest (1429) at 48.7, 65.2")
	check("modules are listed by state and a differing version is shown", lines[3] == "Modules on (2): bags, map_pins" and lines[4] == "Modules off (1): nameplates 0.27.0")
	local bare = addon.where.lines({ modules = {} })
	check("missing facts print as unknown, never as an error", bare[1]:find("?", 1, true) and bare[2] == "Map unknown" and bare[3] == "Modules on (0): none")

	local read, env = load({
		GetBuildInfo = function() return "1.60.1", "70374", "Oct 10 2026", 16001 end,
		GetLocale = function() return "enUS" end,
		C_AddOns = { GetAddOnMetadata = function(name) return name == "Everlook" and "0.28.0" or nil end },
		C_Map = {
			GetBestMapForUnit = function() return 1429 end,
			GetMapInfo = function() return { name = "Elwynn Forest" } end,
			GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.25 end } end,
		},
	})
	read.module.modules = { { id = "bags", addon = "Everlook_Bags" } }
	read.module.enabled = function(id) return id == "bags" end
	local text = read.where.text()
	check("the game's answers go into the text", text:find("build 70374", 1, true) and text:find("Elwynn Forest (1429) at 50.0, 25.0", 1, true) and text:find("Modules on (1): bags", 1, true))
	env.issecretvalue = function() return true end
	check("hidden values are left out, not printed", read.where.text():find("Map unknown", 1, true) ~= nil)
end
