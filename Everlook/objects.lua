local _, Everlook = ...

Everlook.objects = {}

local function public(value)
	if Everlook.world.usable(value) then
		return value
	end
end

local function tooltip_lines()
	if not C_TooltipInfo or type(C_TooltipInfo.GetUnit) ~= "function" then
		return nil
	end
	local ok, data = pcall(C_TooltipInfo.GetUnit, "mouseover")
	if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then
		return nil
	end
	return data.lines
end

local function line_body(line)
	if type(line) ~= "table" then
		return nil
	end
	local text = public(line.leftText)
	if type(text) == "string" and text ~= "" then
		return text
	end
end

local function game_object_type(guid)
	local reader = C_GameObject and C_GameObject.GetGameObjectType
	if type(reader) ~= "function" then
		return nil
	end
	local ok, value = pcall(reader, guid)
	if not ok then
		return nil
	end
	value = public(value)
	if type(value) == "string" and value ~= "" then
		return value
	end
end

local function is_status_line(body)
	local locked = public(LOCKED)
	if type(locked) == "string" and locked ~= "" and body == locked then
		return true
	end
	return body:match("^Requires ") ~= nil
end

local function object_type(lines)
	if type(lines) ~= "table" then
		return nil
	end
	local locked = public(LOCKED)
	for i = 1, #lines do
		local body = line_body(lines[i])
		if body then
			if type(locked) == "string" and locked ~= "" and body == locked then
				return "chest"
			end
			local skill = body:match("^Requires ([%a%s]+)%s*%(")
			if not skill then
				skill = body:match("^Requires ([%a%s]+)$")
			end
			if type(skill) == "string" then
				skill = skill:lower():gsub("%s+$", "")
				if skill == "mining" then
					return "mining"
				end
				if skill == "herbalism" then
					return "herb"
				end
				if skill == "lockpicking" then
					return "chest"
				end
			end
		end
	end
end

-- The first tooltip line is the object's own name. UnitName often misses game
-- objects, so a mouseover that already built a tooltip still records the name.
local function tooltip_name(lines)
	if type(lines) ~= "table" then
		return nil
	end
	for i = 1, #lines do
		local body = line_body(lines[i])
		if body and not is_status_line(body) then
			return body
		end
	end
end

-- Mouseover refires while the cursor stays on a node. A known type skips later
-- tooltip reads and only moves the pin. Without a type, the five-second window
-- starts once a location is in hand and two reads saw the same line count.
-- Until then the tooltip is read again.
local sightings = Everlook.sightings.window()
local plain_guid = Everlook.sightings.plain_guid
local seen_lines = {}
-- The node type does not change once the object API or the tooltip knows it.
-- Later sightings only move the pin, so gathering does not build another tooltip.
local quiet = {}
local refresh_locations = {}
local refresh_row = { sources = {} }

local function mark_quiet(guid, source)
	local by_source = quiet[guid]
	if not by_source then
		by_source = {}
		quiet[guid] = by_source
	end
	by_source[source] = true
end

local function refresh_object(id, source)
	local location = Everlook.location.player(true)
	if not location then
		return false
	end
	refresh_row.id = id
	refresh_row.sources[1] = source
	refresh_locations[1] = location
	refresh_row.locations = refresh_locations
	Everlook.world.store("objects", refresh_row)
	return true
end

function Everlook.objects.record(guid, source, name)
	local id = Everlook.world.guid_id(guid, "GameObject")
	if not id then
		return nil
	end
	source = source or "mouseover"
	if sightings.same(guid, source) then
		return id
	end
	local by_source = quiet[guid]
	if by_source and by_source[source] then
		if refresh_object(id, source) then
			sightings.note(guid, source)
		end
		return id
	end
	name = public(name)
	if type(name) ~= "string" or name == "" then
		name = public(UnitName and UnitName(source == "mouseover" and "mouseover" or "npc"))
	end
	local lines = tooltip_lines()
	if type(name) ~= "string" or name == "" then
		name = tooltip_name(lines)
	end
	local row = {
		id = id,
		sources = { source },
	}
	if type(name) == "string" and name ~= "" then
		row.name = name
	end
	local kind = game_object_type(guid) or object_type(lines)
	if kind then
		row.objectType = kind
	end
	local location = Everlook.location.player(true)
	if location then
		row.locations = { location }
	end
	Everlook.world.store("objects", row)
	local line_count = type(lines) == "table" and #lines or 0
	local seen_key = guid .. "\0" .. source
	local settled = line_count > 0 and seen_lines[seen_key] == line_count
	if kind then
		mark_quiet(guid, source)
	end
	if location and (kind or settled) then
		sightings.note(guid, source)
	end
	if line_count > 0 then
		seen_lines[seen_key] = line_count
	end
	return id
end

-- Mouseover keeps firing while the cursor stays on a creature or player.
-- Those guids are not objects, so one failed parse covers the window.
function Everlook.objects.watch(guid)
	-- A secret guid errors on this comparison. false is a plain sentinel for an empty mouseover.
	if not Everlook.world.usable(guid) then
		return
	end
	if guid == false then
		return
	end
	if guid == nil and UnitGUID then
		guid = UnitGUID("mouseover")
	end
	if not plain_guid(guid) then
		return
	end
	if sightings.same(guid, "mouseover") then
		return
	end
	if Everlook.world.guid_id(guid, "GameObject") then
		Everlook.objects.record(guid, "mouseover")
		return
	end
	sightings.note(guid, "mouseover")
end
