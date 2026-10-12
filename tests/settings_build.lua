-- The settings page is built a few frames after login, or at once when it is opened first.
return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)

	local function load(with_sched, cvars)
		local Everlook = {
			module = { chapters = function() return {}, {}, {} end },
			scan = { now = function() end },
			collected = { page = function() return {} end },
		}
		local game = { built = 0, opened = nil, login = nil, deferred = {}, subpages = {}, headers = {}, proxies = {}, dropdowns = {} }
		if with_sched then
			Everlook.sched = {}
			Everlook.world = { defer = function(key, fn) game.deferred[key] = fn end }
		end
		local env = setmetatable({}, { __index = _G })
		env._G = env
		local category = { GetID = function() return 7 end }
		env.Settings = {
			RegisterProxySetting = function(_, variable, kind, name, default, get, set)
				game.proxies[variable] = { kind = kind, name = name, default = default, get = get, set = set }
				return { variable = variable }
			end,
			RegisterVerticalLayoutSubcategory = function(_, name)
				game.subpages[#game.subpages + 1] = name
				return { name = name }, { AddInitializer = function(_, row) game.headers[#game.headers + 1] = row end }
			end,
			CreateControlTextContainer = function()
				local data = {}
				return { Add = function(_, value, label) data[#data + 1] = { value = value, label = label } end, GetData = function() return data end }
			end,
			CreateDropdown = function(_, proxy, choices, tooltip) game.dropdowns[proxy.variable] = { choices = choices(), tooltip = tooltip } end,
			RegisterCanvasLayoutSubcategory = function() return {} end,
			RegisterVerticalLayoutCategory = function()
				game.built = game.built + 1
				return category, { AddInitializer = function() end }
			end,
			RegisterAddOnCategory = function() end,
			OpenToCategory = function(id) game.opened = id end,
		}
		env.CreateSettingsButtonInitializer = function() end
		env.CreateSettingsListSectionHeaderInitializer = function(name, tooltip) return { name = name, tooltip = tooltip } end
		if cvars then
			env.GetCVar = function(name) return cvars[name] end
			env.SetCVar = function(name, value) cvars[name] = tostring(value) end
		end
		env.EventUtil = { ContinueOnPlayerLogin = function(fn) game.login = fn end }
		env.SettingsPanel = nil
		local chunk = assert(loadfile(source("settings.lua")))
		setfenv(chunk, env)
		chunk("Everlook", Everlook)
		return Everlook, game
	end

	do
		local _, game = load(true)
		game.login()
		check("with a scheduler, login builds nothing and asks for a coming frame", game.built == 0 and game.deferred.settings ~= nil)
		game.deferred.settings()
		game.deferred.settings()
		check("the page is built once, in that frame", game.built == 1)
	end

	do
		local addon, game = load(true)
		game.login()
		addon.settings.toggle()
		check("opening the page first builds it on the spot and opens it", game.built == 1 and game.opened == 7)
		game.deferred.settings()
		check("and the frame that was waiting builds nothing more", game.built == 1)
	end

	do
		local _, game = load(false)
		game.login()
		check("with no scheduler, login builds the page", game.built == 1)
	end

	-- The Debug subpage: one control for the game's taint log.
	local function build_with(cvars)
		local addon, game = load(true, cvars)
		game.login()
		game.deferred.settings()
		return game
	end
	do
		local cvars = { taintLog = "2" }
		local game = build_with(cvars)
		check("the Debug subpage is the last one in the list", game.subpages[#game.subpages] == "Debug")
		local header = game.headers[#game.headers]
		check("it opens with a Taint log heading", header and header.name == "Taint log")
		local proxy = game.proxies.Everlook_Debug_taint_log
		check("the taint log has a control", proxy ~= nil)
		check("the control is a number and is off by default", proxy.kind == "number" and proxy.default == 0)
		check("it shows what the game has right now", proxy.get() == 2)
		cvars.taintLog = "1"
		check("a change made somewhere else shows when the page is read again", proxy.get() == 1)
		proxy.set(0)
		check("choosing Off turns the game's taint log off", cvars.taintLog == "0")
		proxy.set(2)
		check("choosing a level sets that level", cvars.taintLog == "2")
		cvars.taintLog = "nonsense"
		check("a value the game gives that is not a number reads as off", proxy.get() == 0)
		local dropdown = game.dropdowns.Everlook_Debug_taint_log
		local labels = {}
		for _, choice in ipairs(dropdown.choices) do labels[#labels + 1] = choice.value .. "=" .. choice.label end
		check("the dropdown offers off and two levels", table.concat(labels, ",") == "0=Off,1=Level 1,2=Level 2")
		check("the help says what leaving it on can cost", dropdown.tooltip:find("attempt to call a nil value", 1, true) ~= nil and dropdown.tooltip:find("Logs/taint.log", 1, true) ~= nil)
		check("the heading carries the same help", header.tooltip == dropdown.tooltip)
	end
	do
		local game = build_with(nil)
		check("a client without the console variable calls has no Debug subpage", #game.subpages == 0 and game.proxies.Everlook_Debug_taint_log == nil)
	end
	do
		local game = build_with({})
		check("a client that has no taintLog variable has no Debug subpage", #game.subpages == 0)
	end
	do
		local cvars = { taintLog = "0" }
		local game = build_with(cvars)
		local _, built_again = pcall(function() return game.proxies.Everlook_Debug_taint_log.get() end)
		check("with the log off the control reads off", built_again == 0)
	end
end
