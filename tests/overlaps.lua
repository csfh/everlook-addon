-- Telling the player when a module is on beside an addon that changes the same thing.
return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)
	local function load(loaded_addons, enabled_modules)
		local said = {}
		local Everlook
		Everlook = {
			say = function(text) said[#said + 1] = text end,
			module = { enabled = function(id) return enabled_modules[id] == true end },
		}
		local env = setmetatable({
			C_AddOns = { IsAddOnLoaded = function(name) return loaded_addons[name] == true end },
		}, { __index = _G })
		env._G = env
		local chunk = assert(loadfile(source("overlaps")))
		setfenv(chunk, env)
		chunk("Everlook", Everlook)
		return Everlook, said
	end

	local addon, said = load({ Bagnon = true, Plater = true }, { bags = true, nameplates = false })
	check("the addons loaded beside a module are named", table.concat(addon.overlaps.for_module("bags"), ",") == "Bagnon")
	check("a module with no overlapping addon loaded has none", #addon.overlaps.for_module("coordinates") == 0 and #addon.overlaps.for_module("unknown") == 0)
	addon.overlaps.warn({ id = "bags", name = "Bags" })
	check("a module that is on is told about the addon beside it, once", #said == 1 and said[1]:find("Bags and Bagnon", 1, true))
	addon.overlaps.warn({ id = "bags", name = "Bags" })
	check("the same module is not told again in the session", #said == 1)
	addon.overlaps.warn({ id = "nameplates", name = "Nameplates" })
	check("a module that is off is not told", #said == 1)
	local plain, plain_said = load({}, { bags = true })
	plain.overlaps.warn({ id = "bags", name = "Bags" })
	check("nothing is said when no other addon is loaded", #plain_said == 0)
end
