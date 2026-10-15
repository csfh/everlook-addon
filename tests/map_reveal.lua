-- Map reveal: the tile maths, the explored match, the art guard, and the provider on a stand-in world map.
return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)

	local function load(extra)
		local Everlook
		Everlook = { module = {
			enabled = function() return true end,
			get = function(_, key) return key == "dim" end,
			register = function(spec) Everlook.spec = spec end,
		} }
		local env = setmetatable({ Everlook = Everlook }, { __index = _G })
		env._G = env
		for key, value in pairs(extra or {}) do env[key] = value end
		for _, file in ipairs({ "tiling", "map_reveal" }) do
			local chunk = assert(loadfile(source(file)))
			setfenv(chunk, env)
			chunk("Everlook_MapReveal")
		end
		return Everlook, env
	end

	local addon = load()
	local reveal = addon.map_reveal

	-- A 300 x 200 overlay at (600, 100) on 256-pixel tiles: two tiles, the second cropped from a 64-pixel file.
	local placed = {}
	reveal.each_overlay_tile(256, 256, 300, 200, 600, 100, { 1, 1, 1, 1, 7001, 7002 }, 5, function(...) placed[#placed + 1] = { ... } end)
	check("an overlay is cut into one tile per column and row", #placed == 2 and placed[1][1] == 7001 and placed[2][1] == 7002)
	check("a tile sits at the overlay's offset plus its place in the grid", placed[1][2] == 600 and placed[1][3] == 100 and placed[2][2] == 856 and placed[2][3] == 100)
	check("a full tile uses all of its file", placed[1][4] == 256 and placed[1][5] == 200 and placed[1][6] == 0 and placed[1][7] == 1)
	check("the last column is cropped from the smallest power of two that holds it", placed[2][4] == 44 and placed[2][7] == 44 / 64)
	check("the last row is cropped the same way", placed[1][9] == 200 / 256 and placed[2][9] == 200 / 256)

	local tall = {}
	reveal.each_overlay_tile(256, 256, 256, 300, 0, 0, { 1, 1, 1, 1, 1, 2 }, 5, function(...) tall[#tall + 1] = { ... } end)
	check("a second row sits one tile lower and is cropped from a 64-pixel file", #tall == 2 and tall[2][3] == 256 and tall[2][5] == 44 and tall[2][9] == 44 / 64)
	local exact = {}
	reveal.each_overlay_tile(256, 256, 512, 256, 0, 0, { 1, 1, 1, 1, 1, 2 }, 5, function(...) exact[#exact + 1] = { ... } end)
	check("an overlay that is a whole number of tiles has no cropped tile", #exact == 2 and exact[2][4] == 256 and exact[2][7] == 1)

	local entry = { 256, 256, { 300, 200, 600, 100, 7001, 7002 }, { 64, 64, 5, 6, 7003 } }
	local left = reveal.unexplored(entry, { { offsetX = 600, offsetY = 100, textureWidth = 300, textureHeight = 200 } })
	check("an explored overlay is left to the game", #left == 1 and left[1][5] == 7003)
	check("with nothing explored every overlay is unexplored", #reveal.unexplored(entry, {}) == 2 and #reveal.unexplored(entry, nil) == 2)
	check("an explored texture that matches no overlay changes nothing", #reveal.unexplored(entry, { { offsetX = 1, offsetY = 1, textureWidth = 9, textureHeight = 9 } }) == 2)

	reveal.register("test", { [1200] = entry })
	local function client(art_id, tile)
		return {
			C_Map = { GetMapArtID = function() return art_id end, GetMapArtLayers = function() return { { tileWidth = tile, tileHeight = tile } } end },
		}
	end
	local _, matching = load(client(1200, 256))
	check("the table is used when the client shows the art it was made for", matching ~= nil)
	local function art_for(art_id, tile)
		local reg, env = load(client(art_id, tile))
		reg.map_reveal.register("test", { [1200] = entry })
		return reg.map_reveal.art_for(1), env
	end
	check("the art id and tile size the client reports are what the table holds", art_for(1200, 256) == entry)
	check("another art draws nothing", art_for(1201, 256) == nil)
	check("another tile size draws nothing", art_for(1200, 512) == nil)

	-- The generated table holds whole overlays: each one has exactly the tiles its size needs.
	do
		local shipped = load({})
		local chunk = assert(loadfile(source("overlays")))
		setfenv(chunk, setmetatable({ Everlook = shipped }, { __index = _G }))
		chunk()
		local arts, overlays, wrong = 0, 0, nil
		for art_id, art in pairs(shipped.map_reveal.arts) do
			arts = arts + 1
			for index = 3, #art do
				local overlay = art[index]
				overlays = overlays + 1
				local needed = math.ceil(overlay[1] / art[1]) * math.ceil(overlay[2] / art[2])
				if #overlay - 4 ~= needed then wrong = wrong or ("art " .. art_id .. " overlay " .. index) end
			end
		end
		check("the generated table has the arts of the zone maps (" .. arts .. ") and a build", arts > 40 and overlays > 500 and shipped.map_reveal.build ~= nil)
		check("every generated overlay has exactly the tiles its size needs" .. (wrong and (" (" .. wrong .. ")") or ""), wrong == nil)
	end

	-- The provider on a stand-in world map.
	local function scenario(art_id, tile)
		local run = { providers = {}, pins = {}, textures = {} }
		local explored = { { offsetX = 5, offsetY = 6, textureWidth = 64, textureHeight = 64 } }
		local Base = { OnAdded = function(self, canvas) self.canvas = canvas end, OnRemoved = function() end }
		local PinBase = {}
		local env = client(art_id, tile)
		env.MapCanvasDataProviderMixin = Base
		env.MapCanvasPinMixin = PinBase
		env.CreateFromMixins = function(...)
			local made = {}
			for _, mixin in ipairs({ ... }) do for key, value in pairs(mixin) do made[key] = value end end
			return made
		end
		env.CreateTexturePool = function()
			local pool = {}
			function pool:Acquire()
				local texture = { shown = false }
				function texture:SetSize(width, height) self.width, self.height = width, height end
				function texture:SetTexCoord(...) self.coords = { ... } end
				function texture:SetPoint(_, x, y) self.x, self.y = x, y end
				function texture:SetTexture(file) self.file = file end
				function texture:SetVertexColor(red) self.red = red end
				function texture:Show() self.shown = true end
				run.textures[#run.textures + 1] = texture
				return texture
			end
			function pool:ReleaseAll() run.textures = {} end
			return pool
		end
		env.C_MapExplorationInfo = { GetExploredMapTextures = function() return explored end }
		local map = {}
		function map:GetMapID() return 1 end
		function map:AddMaskableTexture() end
		function map:GetGlobalAlpha() return 0.75 end
		function map:DenormalizeHorizontalSize(value) return 1000 * value end
		function map:DenormalizeVerticalSize(value) return 600 * value end
		function map:RemoveAllPinsByTemplate() run.pins = {} end
		env.WorldMapFrame = { AddDataProvider = function(_, provider) run.providers[#run.providers + 1] = provider end }
		local installed, inner = load(env)
		installed.map_reveal.register("test", { [1200] = entry })
		function map:AcquirePin(template, owner)
			local pin = env.CreateFromMixins(PinBase, inner.EverlookMapRevealPinMixin)
			function pin:GetMap() return map end
			function pin:SetPosition() end
			function pin:SetAlpha(value) self.alpha = value end
			function pin:SetSize(width, height) self.width, self.height = width, height end
			pin:OnAcquired(owner)
			run.pins[#run.pins + 1] = pin
			return pin
		end
		run.spec = installed.spec
		run.map = map
		run.attach = function()
			run.spec.apply(true)
			local provider = run.providers[1]
			if provider then
				provider.GetMap = function() return map end
				provider.RegisterEvent = function() end
				provider.UnregisterEvent = function() end
				provider:OnAdded(map)
				provider:RefreshAllData()
			end
			return provider
		end
		return run
	end

	local live = scenario(1200, 256)
	check("nothing is attached to the world map until the module is on", #live.providers == 0)
	local provider = live.attach()
	check("turning it on adds one provider to the world map", #live.providers == 1 and provider ~= nil)
	check("the overlay the game has not explored is drawn, one texture per tile", #live.textures == 2 and live.textures[1].file == 7001 and live.textures[2].file == 7002)
	check("it sits at the overlay's offset, downward in the map's own coordinates", live.textures[1].x == 600 and live.textures[1].y == -100 and live.textures[2].x == 856)
	check("a cropped tile is cut with the right coordinates", live.textures[2].width == 44 and live.textures[2].coords[2] == 44 / 64)
	check("unexplored areas are dimmed when that is chosen", live.textures[1].red < 1)
	check("the explored overlay is not drawn by us", live.textures[1].file ~= 7003 and live.textures[2].file ~= 7003)
	check("the pin follows the map's own alpha", live.pins[1].alpha == 0.75)
	live.pins[1]:OnCanvasSizeChanged()
	check("the pin takes the size of the canvas", live.pins[1].width == 1000 and live.pins[1].height == 600)
	live.spec.apply(false)
	check("turning it off takes the drawing away", #live.textures == 0)

	local wrong = scenario(9999, 256)
	wrong.attach()
	check("a client whose art is not the table's draws nothing", #wrong.textures == 0)
	local other_tile = scenario(1200, 512)
	other_tile.attach()
	check("a client whose tiles are another size draws nothing", #other_tile.textures == 0)

	local bare, bare_env = load({})
	bare.spec.apply(true)
	check("a client with no stock world map is left alone and says so once", bare.map_reveal.noted == true and bare_env.WorldMapFrame == nil)
end
