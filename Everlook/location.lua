local _, Everlook = ...

Everlook.location = {}

local function scale(value)
	if type(value) ~= "number" or not Everlook.world.usable(value) then
		return nil
	end
	if value < 0 or value > 1 then
		return nil
	end
	return math.floor(value * 1000 + 0.5)
end

-- Nameplates ask for the player spot in one burst. One map read per timestamp
-- is enough. A shared caller must not set a role or pin on the returned table.
local cached_at
local cached_location
local stored_map

local function copy(location)
	return {
		mapId = location.mapId,
		x = location.x,
		y = location.y,
		zone = location.zone,
		subzone = location.subzone,
	}
end

function Everlook.location.note_area(map_id, x, y, name)
	local reader = C_MapExplorationInfo and C_MapExplorationInfo.GetExploredAreaIDsAtPosition
	if type(reader) ~= "function" or type(map_id) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
		return
	end
	local nx, ny = x / 1000, y / 1000
	local position
	if type(CreateVector2D) == "function" then
		position = CreateVector2D(nx, ny)
	else
		position = { x = nx, y = ny }
	end
	local ok, ids = pcall(reader, map_id, position)
	if not ok or type(ids) ~= "table" then
		return
	end
	local area_id = ids[1]
	if type(area_id) ~= "number" or area_id <= 0 or not Everlook.world.usable(area_id) then
		return
	end
	local area_name = name
	if C_Map and type(C_Map.GetAreaInfo) == "function" then
		local info_name = C_Map.GetAreaInfo(area_id)
		if type(info_name) == "string" and info_name ~= "" and Everlook.world.usable(info_name) then
			area_name = info_name
		end
	end
	if type(area_name) ~= "string" or area_name == "" or not Everlook.world.usable(area_name) then
		return
	end
	Everlook.world.store("maps", {
		id = map_id,
		areas = { { id = area_id, name = area_name } },
	})
end

function Everlook.location.player(share)
	local now
	if type(GetTime) == "function" then
		now = GetTime()
	end
	if type(now) == "number" and now == cached_at then
		if not cached_location then
			return nil
		end
		if share then
			return cached_location
		end
		return copy(cached_location)
	end
	if not C_Map or not C_Map.GetBestMapForUnit then
		return nil
	end
	local mapId = C_Map.GetBestMapForUnit("player")
	if not Everlook.world.usable(mapId) or type(mapId) ~= "number" then
		return nil
	end
	local x, y
	if C_Map.GetPlayerMapPosition then
		local position = C_Map.GetPlayerMapPosition(mapId, "player")
		if position then
			if position.GetXY then
				x, y = position:GetXY()
			else
				x = position.x
				y = position.y
			end
		end
	end
	x = scale(x)
	y = scale(y)
	if not x or not y then
		if type(now) == "number" then
			cached_at = now
			cached_location = nil
		end
		return nil
	end
	local location = {
		mapId = mapId,
		x = x,
		y = y,
		zone = GetZoneText and GetZoneText() or nil,
		subzone = GetSubZoneText and GetSubZoneText() or nil,
	}
	-- Name, parent, and type do not change while the player stays on that map.
	if mapId ~= stored_map and C_Map.GetMapInfo then
		local info = C_Map.GetMapInfo(mapId)
		if type(info) == "table" and type(info.name) == "string" and Everlook.world.usable(info.name) then
			Everlook.world.store("maps", {
				id = mapId,
				name = info.name,
				parentMapId = info.parentMapID,
				mapType = info.mapType,
			})
			stored_map = mapId
		end
	end
	Everlook.location.note_area(mapId, x, y, location.subzone)
	if type(now) == "number" then
		cached_at = now
		cached_location = location
	end
	if share then
		return location
	end
	return copy(location)
end
