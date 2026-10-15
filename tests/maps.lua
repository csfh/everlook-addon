-- The map layout: the base tiles in order, the explored pieces, and where a map lies on the one above.
return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)
	local function load()
		local stored = {}
		local Everlook = { world = { usable = function(value) return value ~= "hidden" end, store = function(bucket, row)
			local copy = {}
			for key, value in pairs(row) do copy[key] = value end
			stored[#stored + 1] = { bucket = bucket, row = copy }
		end } }
		local state = { map = 1429, pieces = { { offsetX = 231, offsetY = 129, textureWidth = 462, textureHeight = 210, fileDataIDs = { 31, 32, 33, 34 }, isDrawOnTopLayer = true, isShownByMouseOver = false } } }
		local env = setmetatable({
			C_Map = {
				GetBestMapForUnit = function() return state.map end,
				GetMapInfo = function(map) return ({ [1429] = { parentMapID = 1415 }, [1415] = { parentMapID = 947 }, [947] = { parentMapID = 0 } })[map] end,
				GetMapArtID = function(map) return map + 1000 end,
				GetMapArtLayers = function() return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256, minScale = 0.5, maxScale = 1, additionalZoomSteps = 2 } } end,
				GetMapArtLayerTextures = function() return { 11, 12, 12, 0 } end,
				GetMapRectOnMap = function(map, parent) if parent == 1415 then return 0.4, 0.42, 0.5, 0.53 elseif parent == 947 then return 0.3, 0.5, 0.2, 0.6 end end,
			},
			C_MapExplorationInfo = { GetExploredMapTextures = function() return state.pieces end },
		}, { __index = _G })
		env._G = env
		local chunk = assert(loadfile(source("maps")))
		setfenv(chunk, env)
		chunk("Everlook", Everlook)
		return Everlook, state, stored, env
	end
	local function of(stored, bucket)
		local list = {}
		for _, item in ipairs(stored) do if item.bucket == bucket then list[#list + 1] = item.row end end
		return list
	end

	local addon, state, stored = load()
	addon.maps.scan()
	local art, overlays, rects = of(stored, "mapArt"), of(stored, "mapOverlays"), of(stored, "mapRects")
	check("the player's map and the ones above it are each looked at", #art == 3 and art[1].mapId == 1429 and art[2].mapId == 1415 and art[3].mapId == 947)
	check("the art keeps the layer's size and tiles, the tiles in order with repeats and zeros, and scales in thousandths", art[1].artId == 2429 and art[1].layerWidth == 1002
		and art[1].tileWidth == 256 and art[1].minScale == 500 and art[1].maxScale == 1000 and art[1].zoomSteps == 2 and #art[1].tiles == 4 and art[1].tiles[3] == 12 and art[1].tiles[4] == 0)
	check("an explored piece keeps its place, size, files and flags", overlays[1].mapId == 1429 and overlays[1].offsetX == 231 and overlays[1].offsetY == 129
		and overlays[1].width == 462 and overlays[1].height == 210 and #overlays[1].files == 4 and overlays[1].top == 1 and overlays[1].hover == 0)
	check("a map's rectangle on the one above it is kept as a millionth of that map", #rects == 2 and rects[1].mapId == 1429 and rects[1].parentId == 1415
		and rects[1].left == 400000 and rects[1].right == 420000 and rects[1].top == 500000 and rects[1].bottom == 530000)
	check("the continent's rectangle on the world is kept too, and the world, which has no parent, has none", rects[2].mapId == 1415 and rects[2].parentId == 947 and rects[2].left == 300000 and #rects == 2)

	local before = #of(stored, "mapArt")
	addon.maps.scan()
	check("a map seen again with the same pieces is not written again", #of(stored, "mapArt") == before)
	state.pieces[2] = { offsetX = 5, offsetY = 6, textureWidth = 10, textureHeight = 10, fileDataIDs = { 9 } }
	addon.maps.scan()
	check("a new explored piece makes the map be looked at again", #of(stored, "mapArt") > before and #of(stored, "mapOverlays") >= 3)

	local skip, skip_state, skip_stored = load()
	skip_state.pieces = { { offsetX = "hidden", offsetY = 1, fileDataIDs = { 1 } } }
	skip.maps.scan()
	check("a piece whose place the client hides is skipped", #of(skip_stored, "mapOverlays") == 0)
	local clean, clean_state, clean_stored = load()
	clean_state.pieces = { { offsetX = 1, offsetY = 2, textureWidth = 8, textureHeight = 8, fileDataIDs = { 1, "hidden" } } }
	clean.maps.scan()
	check("a list with an id the client hides is left off, the piece stays", of(clean_stored, "mapOverlays")[1] and of(clean_stored, "mapOverlays")[1].files == nil)

	local bare, _, bare_stored, bare_env = load()
	bare_env.C_Map = nil
	check("a client without the map functions records nothing and raises nothing", pcall(bare.maps.scan) and #bare_stored == 0)
	local no_art, no_art_state, no_art_stored, no_art_env = load()
	no_art_env.C_Map.GetMapArtLayers = function() return {} end
	no_art.maps.scan()
	check("a map with no layer has no art row", #of(no_art_stored, "mapArt") == 0)
end
