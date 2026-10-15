local _, Everlook = ...

-- What a bug report needs first: the client, the versions and where the player stands. `text`
-- reads the game and `lines` formats what it was given, so the format is testable on its own.
Everlook.where = {}

local function clean(value)
	if value == nil then return nil end
	if issecretvalue and issecretvalue(value) then return nil end
	return value
end

-- `facts` holds build, locale, toc, core, modules = { { id, addon, enabled, version } }, map_id, map_name, x, y.
function Everlook.where.lines(facts)
	local out = {}
	out[#out + 1] = "Everlook " .. (facts.core or "?") .. " on client build " .. (facts.build or "?") .. " (" .. (facts.locale or "?") .. ", interface " .. (facts.toc or "?") .. ")"
	if facts.map_id then
		local at = facts.map_name and (facts.map_name .. " ") or ""
		local spot = (facts.x and facts.y) and string.format(" at %.1f, %.1f", facts.x * 100, facts.y * 100) or ""
		out[#out + 1] = "Map " .. at .. "(" .. facts.map_id .. ")" .. spot
	else
		out[#out + 1] = "Map unknown"
	end
	local on, off = {}, {}
	for _, module in ipairs(facts.modules or {}) do
		local label = module.id .. ((module.version and module.version ~= facts.core) and (" " .. module.version) or "")
		if module.enabled then on[#on + 1] = label else off[#off + 1] = label end
	end
	table.sort(on)
	table.sort(off)
	out[#out + 1] = "Modules on (" .. #on .. "): " .. (#on > 0 and table.concat(on, ", ") or "none")
	out[#out + 1] = "Modules off (" .. #off .. "): " .. (#off > 0 and table.concat(off, ", ") or "none")
	return out
end

local function metadata(addon)
	if C_AddOns and C_AddOns.GetAddOnMetadata then
		local ok, value = pcall(C_AddOns.GetAddOnMetadata, addon, "Version")
		if ok and type(value) == "string" and value ~= "" then return value end
	end
end

function Everlook.where.facts()
	local facts = { modules = {}, core = metadata("Everlook") }
	if GetBuildInfo then
		local _, build, _, toc = GetBuildInfo()
		facts.build, facts.toc = clean(build), clean(toc)
	end
	facts.locale = GetLocale and clean(GetLocale()) or nil
	if C_Map and C_Map.GetBestMapForUnit then
		local ok, map_id = pcall(C_Map.GetBestMapForUnit, "player")
		map_id = ok and clean(map_id) or nil
		if type(map_id) == "number" then
			facts.map_id = map_id
			if C_Map.GetMapInfo then
				local info = C_Map.GetMapInfo(map_id)
				facts.map_name = type(info) == "table" and clean(info.name) or nil
			end
			if C_Map.GetPlayerMapPosition then
				local position = C_Map.GetPlayerMapPosition(map_id, "player")
				if type(position) == "table" and position.GetXY then
					local x, y = position:GetXY()
					x, y = clean(x), clean(y)
					if type(x) == "number" and type(y) == "number" then facts.x, facts.y = x, y end
				end
			end
		end
	end
	for _, module in ipairs(Everlook.module and Everlook.module.modules or {}) do
		facts.modules[#facts.modules + 1] = { id = module.id, addon = module.addon, enabled = Everlook.module.enabled(module.id), version = metadata(module.addon) }
	end
	return facts
end

function Everlook.where.text()
	return table.concat(Everlook.where.lines(Everlook.where.facts()), "\n")
end

function Everlook.where.print()
	for _, line in ipairs(Everlook.where.lines(Everlook.where.facts())) do
		if Everlook.say then Everlook.say(line) end
	end
end
