-- The settings page is built a few frames after login, or at once when it is opened first.
return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)

	local function load(with_sched)
		local Everlook = {
			module = { chapters = function() return {}, {}, {} end },
			scan = { now = function() end },
			collected = { page = function() return {} end },
		}
		local game = { built = 0, opened = nil, login = nil, deferred = {} }
		if with_sched then
			Everlook.sched = {}
			Everlook.world = { defer = function(key, fn) game.deferred[key] = fn end }
		end
		local env = setmetatable({}, { __index = _G })
		env._G = env
		local category = { GetID = function() return 7 end }
		env.Settings = {
			RegisterProxySetting = function() end,
			RegisterVerticalLayoutSubcategory = function() end,
			RegisterCanvasLayoutSubcategory = function() return {} end,
			RegisterVerticalLayoutCategory = function()
				game.built = game.built + 1
				return category, { AddInitializer = function() end }
			end,
			RegisterAddOnCategory = function() end,
			OpenToCategory = function(id) game.opened = id end,
		}
		env.CreateSettingsButtonInitializer = function() end
		env.CreateSettingsListSectionHeaderInitializer = function() end
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
end
