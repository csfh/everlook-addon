local _, Everlook = ...

Everlook.maps = {}

-- How the game draws the map the player is on, and the maps above it: the base tiles in the order they lie, the pieces
-- of exploration art with where they sit, and where each map lies on the one above. Only file ids, sizes and places
-- are kept; the pictures are read from the game's own files, later, by id. A map is looked at when the world is
-- entered or left, and again only when its count of explored pieces has changed. The game only returns the pieces the
-- player has explored, so a full set comes from many players over time.
local SCALE = 1000000
local MAX_DEPTH = 6

local seen = {}

local function public(value)
	if Everlook.world.usable(value) then return value end
end

local function whole(value)
	value = public(value)
	return type(value) == "number" and value == value and value % 1 == 0 and value >= 0 and value or nil
end

local function scaled(value)
	value = public(value)
	return type(value) == "number" and value == value and math.floor(value * SCALE + 0.5) or nil
end

local function numbers(list)
	if type(list) ~= "table" then return nil end
	local copy = {}
	for index = 1, #list do
		local id = whole(list[index])
		if not id then return nil end
		copy[index] = id
	end
	return #copy > 0 and copy or nil
end

local function record_art(map_id)
	local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(map_id)
	local layer = type(layers) == "table" and layers[1]
	if type(layer) ~= "table" then return end
	local art_row = { mapId = map_id }
	art_row.artId = C_Map.GetMapArtID and whole(C_Map.GetMapArtID(map_id)) or nil
	art_row.layerWidth, art_row.layerHeight = whole(layer.layerWidth), whole(layer.layerHeight)
	art_row.tileWidth, art_row.tileHeight = whole(layer.tileWidth), whole(layer.tileHeight)
	local min, max = public(layer.minScale), public(layer.maxScale)
	art_row.minScale = type(min) == "number" and math.floor(min * 1000 + 0.5) or nil
	art_row.maxScale = type(max) == "number" and math.floor(max * 1000 + 0.5) or nil
	art_row.zoomSteps = whole(layer.additionalZoomSteps)
	art_row.tiles = C_Map.GetMapArtLayerTextures and numbers(C_Map.GetMapArtLayerTextures(map_id, 1)) or nil
	Everlook.world.store("mapArt", art_row)
end

local function record_overlays(map_id)
	if not (C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures) then return 0 end
	local pieces = C_MapExplorationInfo.GetExploredMapTextures(map_id)
	if type(pieces) ~= "table" then return 0 end
	for index = 1, #pieces do
		local piece = pieces[index]
		local offset_x, offset_y = public(type(piece) == "table" and piece.offsetX), public(type(piece) == "table" and piece.offsetY)
		if type(offset_x) == "number" and type(offset_y) == "number" then
			local overlay_row = { mapId = map_id, offsetX = math.floor(offset_x), offsetY = math.floor(offset_y) }
			overlay_row.width, overlay_row.height = whole(piece.textureWidth), whole(piece.textureHeight)
			overlay_row.files = numbers(piece.fileDataIDs)
			overlay_row.top = public(piece.isDrawOnTopLayer) == true and 1 or 0
			overlay_row.hover = public(piece.isShownByMouseOver) == true and 1 or 0
			Everlook.world.store("mapOverlays", overlay_row)
		end
	end
	return #pieces
end

local function record_rect(map_id, parent_id)
	if not C_Map.GetMapRectOnMap then return end
	local ok, left, right, top, bottom = pcall(C_Map.GetMapRectOnMap, map_id, parent_id)
	left, right, top, bottom = ok and scaled(left), ok and scaled(right), ok and scaled(top), ok and scaled(bottom)
	if not (left and right and top and bottom) then return end
	local rect_row = { mapId = map_id, parentId = parent_id }
	rect_row.left, rect_row.right, rect_row.top, rect_row.bottom = left, right, top, bottom
	Everlook.world.store("mapRects", rect_row)
end

-- The player's map and the ones above it.
function Everlook.maps.scan()
	if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo) then return end
	local map_id = whole(C_Map.GetBestMapForUnit("player"))
	for _ = 1, MAX_DEPTH do
		if not map_id or map_id <= 0 then return end
		local info = C_Map.GetMapInfo(map_id)
		local parent = type(info) == "table" and whole(info.parentMapID) or nil
		local pieces = record_overlays(map_id)
		if seen[map_id] ~= pieces or seen[map_id] == nil then
			record_art(map_id)
			if parent and parent > 0 then record_rect(map_id, parent) end
			seen[map_id] = pieces
		end
		map_id = parent
	end
end
