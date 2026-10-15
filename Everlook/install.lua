local _, Everlook = ...

-- Everlook ships as about fifty folders in one archive, and a player updates by unzipping. A
-- folder left from an older release loads next to a newer core and misbehaves in ways nobody
-- can explain. At login each module addon's version is compared with the core's. The release
-- archive stamps the core's version into every module's TOC; a folder with no version at all
-- (a development install that links the source folders) is left out of the check.
Everlook.install = {}

local function version_of(addon)
	if not (C_AddOns and C_AddOns.GetAddOnMetadata) then return nil end
	local ok, version = pcall(C_AddOns.GetAddOnMetadata, addon, "Version")
	if ok and type(version) == "string" and version ~= "" then return version end
end

-- The module addons that report a version other than the core's, as a sorted list of names.
function Everlook.install.mismatches()
	local core = version_of("Everlook")
	if not core then return {} end
	local seen, found = {}, {}
	for _, module in ipairs(Everlook.module.modules) do
		local addon = module.addon
		if not seen[addon] then
			seen[addon] = true
			local version = version_of(addon)
			if version and version ~= core then found[#found + 1] = addon end
		end
	end
	table.sort(found)
	return found, core
end

function Everlook.install.report()
	local found, core = Everlook.install.mismatches()
	if #found == 0 then return nil end
	return "These Everlook folders are from another release than Everlook " .. core .. ": " .. table.concat(found, ", ")
		.. ". Delete every Everlook folder in Interface\\AddOns and unzip the current release again."
end

if EventUtil and EventUtil.ContinueOnPlayerLogin then
	EventUtil.ContinueOnPlayerLogin(function()
		local text = Everlook.install.report()
		if text and Everlook.say then Everlook.say(text) end
	end)
end
