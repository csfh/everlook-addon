-- The install check: module folders from another release than the core.
return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)
	local function load(versions, modules)
		local Everlook
		Everlook = { module = { modules = modules }, say = function(text) Everlook.said = text end }
		local logged_in
		local env = setmetatable({
			C_AddOns = { GetAddOnMetadata = function(addon) return versions[addon] end },
			EventUtil = { ContinueOnPlayerLogin = function(callback) logged_in = callback end },
		}, { __index = _G })
		env._G = env
		local chunk = assert(loadfile(source("install")))
		setfenv(chunk, env)
		chunk("Everlook", Everlook)
		return Everlook, logged_in
	end
	local modules = { { addon = "Everlook_Bags" }, { addon = "Everlook_Island" }, { addon = "Everlook_Island" }, { addon = "Everlook_Maps" } }

	local addon, login = load({ Everlook = "0.28.0", Everlook_Bags = "0.28.0", Everlook_Island = "0.28.0", Everlook_Maps = "0.28.0" }, modules)
	login()
	check("a matching install says nothing", addon.said == nil and #addon.install.mismatches() == 0)

	addon, login = load({ Everlook = "0.28.0", Everlook_Bags = "0.27.2", Everlook_Island = "0.28.0", Everlook_Maps = "0.26.0" }, modules)
	login()
	check("a folder from another release is named once, with what to do", addon.said and addon.said:find("Everlook_Bags, Everlook_Maps", 1, true)
		and addon.said:find("0.28.0", 1, true) and addon.said:find("unzip", 1, true))

	addon, login = load({ Everlook = "0.28.0", Everlook_Bags = "0.28.0" }, modules)
	login()
	check("a folder with no stamped version, as in a development install, is skipped", addon.said == nil)

	addon, login = load({ Everlook_Bags = "0.27.2" }, modules)
	login()
	check("a core with no version has nothing to compare with", addon.said == nil)
end
