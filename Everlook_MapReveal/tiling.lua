local Everlook = Everlook

-- The parts of the world map that drawing unexplored areas needs and that can be worked out without the game: how an
-- overlay is cut into tiles the way the game's own map cuts it, and which overlays the character has not explored.
-- overlays.lua (generated from the client's own tables) hands the data in through `register`.
Everlook.map_reveal = { arts = {}, build = nil }
local reveal = Everlook.map_reveal

-- arts[art id] = { tile width, tile height, { width, height, offset x, offset y, file ids... }, ... }
function reveal.register(build, arts)
	reveal.build = build
	for art_id, entry in pairs(arts) do reveal.arts[art_id] = entry end
end

local function file_size(pixels)
	local size = 16
	while size < pixels do size = size * 2 end
	return size
end

-- Calls place(file id, x, y, width, height, left, right, top, bottom) for every tile of one overlay. x and y are pixels from
-- the map's top left corner. The last column and row are cropped: their file is the smallest power of two that holds
-- them, so the texture coordinates reach only the part that is picture. This is how the game places them.
function reveal.each_overlay_tile(tile_width, tile_height, width, height, offset_x, offset_y, files, first, place)
	local wide = math.ceil(width / tile_width)
	local tall = math.ceil(height / tile_height)
	for row = 1, tall do
		local pixel_height, file_height = tile_height, tile_height
		if row == tall then
			pixel_height = height % tile_height
			if pixel_height == 0 then pixel_height = tile_height end
			file_height = file_size(pixel_height)
		end
		for column = 1, wide do
			local pixel_width, file_width = tile_width, tile_width
			if column == wide then
				pixel_width = width % tile_width
				if pixel_width == 0 then pixel_width = tile_width end
				file_width = file_size(pixel_width)
			end
			place(files[first + (row - 1) * wide + column - 1],
				offset_x + tile_width * (column - 1), offset_y + tile_height * (row - 1),
				pixel_width, pixel_height, 0, pixel_width / file_width, 0, pixel_height / file_height)
		end
	end
end

-- The overlays of an art that the game's explored list does not hold. The list carries no ids, so an overlay is matched
-- by its offset and size, as the game's own pin identifies them.
function reveal.unexplored(entry, explored)
	local seen = {}
	for _, texture in ipairs(explored or {}) do
		seen[texture.offsetX .. ":" .. texture.offsetY .. ":" .. texture.textureWidth .. ":" .. texture.textureHeight] = true
	end
	local result = {}
	for index = 3, #entry do
		local overlay = entry[index]
		if not seen[overlay[3] .. ":" .. overlay[4] .. ":" .. overlay[1] .. ":" .. overlay[2]] then result[#result + 1] = overlay end
	end
	return result
end

-- The table's entry for the art the client shows for a map, or nil. The table is used only when the client's own art id and
-- tile size are the ones it was made for, so a table left over from another build draws nothing instead of the wrong thing.
function reveal.art_for(map_id)
	if not (C_Map and C_Map.GetMapArtID and C_Map.GetMapArtLayers) then return nil end
	local ok, art_id = pcall(C_Map.GetMapArtID, map_id)
	local entry = ok and type(art_id) == "number" and reveal.arts[art_id] or nil
	if not entry then return nil end
	local layers_ok, layers = pcall(C_Map.GetMapArtLayers, map_id)
	local layer = layers_ok and type(layers) == "table" and layers[1] or nil
	if type(layer) ~= "table" or layer.tileWidth ~= entry[1] or layer.tileHeight ~= entry[2] then return nil end
	return entry
end
