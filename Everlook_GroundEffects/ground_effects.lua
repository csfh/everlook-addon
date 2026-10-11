local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "ground_effects"

-- Each option sets one of the game's ground clutter settings.
local cvars = {
	density = "groundEffectDensity",
	distance = "groundEffectDist",
	fade = "groundEffectFade",
}
local order = { "density", "distance", "fade" }

-- What each setting was before this was turned on. The game keeps a setting between sessions, so what was there
-- first has to be kept between sessions too, or turning this off after a reload would put back our own numbers.
local function before()
	EverlookDB = EverlookDB or {}
	EverlookDB.groundEffectsBefore = EverlookDB.groundEffectsBefore or {}
	return EverlookDB.groundEffectsBefore
end

local function read(name)
	local ok, value = pcall(GetCVar, name)
	if ok then return value end
end

local function write(name, value)
	return pcall(SetCVar, name, value)
end

local function apply(enabled)
	if type(GetCVar) ~= "function" or type(SetCVar) ~= "function" then
		return
	end
	local previous = before()
	for _, key in ipairs(order) do
		local name = cvars[key]
		if not enabled then
			-- What the game had before this was turned on goes back, for each setting that was changed.
			if previous[name] ~= nil then
				write(name, previous[name])
				previous[name] = nil
			end
		else
			local current = read(name)
			-- A setting this client does not have is left alone.
			if current ~= nil then
				if previous[name] == nil then previous[name] = current end
				write(name, tostring(module.get(id, key)))
			end
		end
	end
end

module.register({
	addon = addon_name, page = "interface", order = 75,
	id = id,
	name = "Ground effects",
	description = "Sets how much ground clutter, such as grass, the game draws, how far from you it is drawn, and how far it fades out. Each number does nothing until this is on, a setting the client does not have is left alone, the game may keep a value inside its own limits, and turning this off puts back what each setting was before this was turned on.",
	options = {
		density = { name = "Ground clutter density", default = 256, min = 0, max = 512, step = 16, description = "Sets how much ground clutter the game draws. A higher number draws more. This does nothing until Ground effects is on, and the game may keep it inside its own limits." },
		distance = { name = "Ground clutter distance", default = 500, min = 0, max = 1000, step = 25, description = "Sets how far from you ground clutter is drawn. A higher number draws it farther out. This does nothing until Ground effects is on, and the game may keep it inside its own limits." },
		fade = { name = "Ground clutter fade", default = 500, min = 0, max = 1000, step = 25, description = "Sets how far out ground clutter fades away. A higher number fades it farther out. This does nothing until Ground effects is on, and the game may keep it inside its own limits." },
	},
	apply = apply,
})
