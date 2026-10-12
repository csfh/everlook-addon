-- The settings page is built a few frames after login, or at once when it is opened first.
return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)

	local function load(with_sched, cvars)
		local said = {}
		local Everlook = {
			module = { chapters = function() return {}, {}, {} end },
			scan = { now = function() end },
			collected = { page = function() return {} end },
			say = function(text) said[#said + 1] = text end,
			said = said,
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
		env.CreateSettingsButtonInitializer = function(name, label, click, tooltip, search)
			return { name = name, label = label, click = click, tooltip = tooltip, search = search, button = true }
		end
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

	-- The Debug subpage: one button that turns the game's taint log off. Turning it on from the
	-- page crashed the client at level 2, so the page cannot do that.
	local function build_with(cvars)
		local addon, game = load(true, cvars)
		game.login()
		game.deferred.settings()
		game.addon = addon
		return game
	end
	local function debug_button(game)
		for _, row in ipairs(game.headers) do
			if row.button then return row end
		end
	end
	do
		local cvars = { taintLog = "2" }
		local game = build_with(cvars)
		check("the Debug subpage is the last one in the list", game.subpages[#game.subpages] == "Debug")
		check("it opens with a Taint log heading", game.headers[1] and game.headers[1].name == "Taint log")
		local button = debug_button(game)
		check("the page has a button to turn the taint log off", button ~= nil and button.label == "Turn off")
		check("the button can be found by searching the settings", button.search == true)
		check("nothing on the page can turn the taint log on", next(game.proxies) == nil and next(game.dropdowns) == nil)
		button.click()
		check("the button turns the game's taint log off", cvars.taintLog == "0")
		check("it says so", #game.addon.said == 1 and game.addon.said[1]:find("off", 1, true) ~= nil)
		check("the help says where the log goes and what leaving it on can cost",
			button.tooltip:find("Logs/taint.log", 1, true) ~= nil and button.tooltip:find("attempt to call a nil value", 1, true) ~= nil)
		check("the help says how to turn it on again", button.tooltip:find("/console taintLog", 1, true) ~= nil)
		check("the heading carries the same help", game.headers[1].tooltip == button.tooltip)
	end
	do
		local cvars = { taintLog = "0" }
		local game = build_with(cvars)
		debug_button(game).click()
		check("pressing it with the log already off leaves it off", cvars.taintLog == "0")
	end
	do
		local game = build_with(nil)
		check("a client without the console variable calls has no Debug subpage", #game.subpages == 0)
	end
	do
		local game = build_with({})
		check("a client that has no taintLog variable has no Debug subpage", #game.subpages == 0)
	end
end
