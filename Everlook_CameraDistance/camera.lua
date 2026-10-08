local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "camera"
local cvar = "cameraDistanceMaxZoomFactor"
local previous

local function apply(enabled)
	if type(GetCVar) ~= "function" or type(SetCVar) ~= "function" then
		return
	end
	if not enabled then
		if previous ~= nil then
			SetCVar(cvar, previous)
			previous = nil
		end
		return
	end
	if previous == nil then
		previous = GetCVar(cvar)
	end
	SetCVar(cvar, tostring(module.get(id, "distance")))
end

module.register({
	addon = addon_name, page = "interface", order = 70,
	id = id,
	name = "Camera distance",
	description = "Sets the farthest the camera can zoom out, using the factor on Maximum camera distance, from 1 to 4. A higher number lets the camera sit farther out, other camera settings stay as they are, the number does nothing until this is on, nothing changes when the client has no way to set it, and turning this off puts back the factor from before this was turned on.",
	options = {
		distance = { name = "Maximum camera distance", default = 2.6, min = 1, max = 4, step = 0.1, description = "Sets the game's maximum zoom factor, from 1 to 4, in steps of 0.1. A higher number lets the camera sit farther out, other camera settings stay as they are, this number does nothing until Camera distance is on, nothing changes when the client has no way to set it, and turning Camera distance off puts the previous factor back." },
	},
	apply = apply,
})
