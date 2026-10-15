local _, Everlook = ...

-- Addons that already change what an Everlook module changes. A module that is turned on beside one of
-- them is not switched off: the player turned it on. The player is told once per session, in one line,
-- so two addons fighting over the same frames is not a mystery.
Everlook.overlaps = {}

local KNOWN = {
	bags = { "Bagnon", "AdiBags", "ArkInventory", "BaudBag", "Baganator", "ElvUI" },
	nameplates = { "Plater", "Platynator", "Kui_Nameplates", "TidyPlates_ThreatPlates", "ElvUI" },
	quest_nameplates = { "Plater", "Platynator", "Kui_Nameplates", "TidyPlates_ThreatPlates", "ElvUI" },
	chat_tweaks = { "Prat-3.0", "Chatter", "Glass", "ElvUI" },
	chat_format = { "Prat-3.0", "Chatter", "Glass", "ElvUI" },
	coordinates = { "ElvUI", "TomTom" },
}

local told = {}

local function loaded(addon)
	if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(addon) == true end
	return false
end

-- The names of the addons loaded beside a module that change the same thing.
function Everlook.overlaps.for_module(id)
	local found = {}
	for _, addon in ipairs(KNOWN[id] or {}) do
		if loaded(addon) then found[#found + 1] = addon end
	end
	return found
end

-- Says it once per module and session, when the module is on and an overlapping addon is loaded.
function Everlook.overlaps.warn(module)
	if told[module.id] or not Everlook.module.enabled(module.id) then return end
	local found = Everlook.overlaps.for_module(module.id)
	if #found == 0 then return end
	told[module.id] = true
	if Everlook.say then
		Everlook.say(module.name .. " and " .. table.concat(found, ", ") .. " both change the same part of the interface. If they get in each other's way, turn one of them off.")
	end
end
