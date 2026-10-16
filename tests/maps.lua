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
		local state = { waiting = {}, map = 1429, pieces = { { offsetX = 231, offsetY = 129, textureWidth = 462, textureHeight = 210, fileDataIDs = { 31, 32, 33, 34 }, isDrawOnTopLayer = true, isShownByMouseOver = false } } }
		local env = setmetatable({
			C_Map = {
				GetBestMapForUnit = function() return state.map end,
				GetMapInfo = function(map) return ({ [1429] = { parentMapID = 1415 }, [1415] = { parentMapID = 947 }, [947] = { parentMapID = 0 } })[map] end,
				GetMapArtID = function(map) return map + 1000 end,
				GetMapArtLayers = function() return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256, minScale = 0.5, maxScale = 1, additionalZoomSteps = 2 } } end,
				GetMapArtLayerTextures = function() return { 11, 12, 12, 0 } end,
				GetMapChildrenInfo = function(map) if map == 947 then return { { mapID = 1415, parentMapID = 947 }, { mapID = 1429, parentMapID = 1415 }, { mapID = 1430, parentMapID = 1415 } } end end,
				GetMapRectOnMap = function(map, parent) if parent == 1415 then return 0.4, 0.42, 0.5, 0.53 elseif parent == 947 then return 0.3, 0.5, 0.2, 0.6 end end,
			},
			C_MapExplorationInfo = { GetExploredMapTextures = function() return state.pieces end },
			C_Timer = { After = function(_, fn) state.waiting[#state.waiting + 1] = fn end },
			GetBuildInfo = function() return "1.60.1", "70374" end,
			EverlookDB = {},
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

	local function drain(state)
		local ticks = 0
		while #state.waiting > 0 and ticks < 50 do
			local run = table.remove(state.waiting, 1)
			run()
			ticks = ticks + 1
		end
		return ticks
	end
	local sweeper, sweep_state, sweep_stored, sweep_env = load()
	sweeper.maps.sweep()
	check("a sweep waits for a tick before it looks at any map", #sweep_stored == 0 and #sweep_state.waiting == 1)
	drain(sweep_state)
	local swept_art = of(sweep_stored, "mapArt")
	check("a sweep records the art of the top map and every map below it, and each map's place on its parent", #swept_art == 4 and swept_art[1].mapId == 947
		and #of(sweep_stored, "mapRects") == 3 and of(sweep_stored, "mapRects")[2].parentId == 1415)
	check("a sweep needs no exploration: it writes no explored pieces", #of(sweep_stored, "mapOverlays") == 0)
	check("a finished sweep is remembered for the client build", sweep_env.EverlookDB.mapsSwept == "70374")
	sweeper.maps.sweep()
	check("a build that was swept is not swept again", #sweep_state.waiting == 0)
	sweep_env.GetBuildInfo = function() return "1.61.0", "70400" end
	sweeper.maps.sweep()
	check("a new build is swept again", #sweep_state.waiting == 1)

	local many, many_state, many_stored, many_env = load()
	many_env.C_Map.GetMapChildrenInfo = function()
		local list = {}
		for index = 1, 45 do list[index] = { mapID = 2000 + index, parentMapID = 947 } end
		return list
	end
	many.maps.sweep()
	local ticks = drain(many_state)
	check("a long list is spread over several ticks, twenty maps at a time", ticks >= 3 and #of(many_stored, "mapArt") == 46)
	local cut, cut_state, cut_stored, cut_env = load()
	cut_env.EverlookDB = false
	cut.maps.sweep()
	check("without its saved table a sweep does nothing", #cut_state.waiting == 0 and #cut_stored == 0)
end
