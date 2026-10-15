local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "map_reveal"
local reveal = Everlook.map_reveal

-- Draws the overlays of a zone map that the character has not explored, on the game's own world map, with the client's own
-- textures. It is a second data provider that sits where the game draws explored areas and draws only what the game does
-- not. Nothing is built until the module is turned on, and a client whose map art is not the one the table was made for
-- draws nothing.
local DIMMED = { 0.55, 0.55, 0.62 }

local provider
local attached = false
local failed = false

local function tint()
	return module.get(id, "dim") and DIMMED or { 1, 1, 1 }
end

local function ensure_pin_mixin()
	if type(EverlookMapRevealPinMixin) == "table" and type(EverlookMapRevealPinMixin.Refresh) == "function" then return end
	EverlookMapRevealPinMixin = CreateFromMixins(MapCanvasPinMixin or {})

	function EverlookMapRevealPinMixin:OnAcquired(owner)
		if self.pool then return end
		self.owner = owner
		if self.SetIgnoreGlobalPinScale then self:SetIgnoreGlobalPinScale(true) end
		if self.UseFrameLevelType then self:UseFrameLevelType("PIN_FRAME_LEVEL_MAP_EXPLORATION") end
		self.pool = CreateTexturePool(self, "ARTWORK", 0)
	end

	function EverlookMapRevealPinMixin:Clear()
		if self.pool then self.pool:ReleaseAll() end
	end

	function EverlookMapRevealPinMixin:Refresh()
		self:Clear()
		if not module.enabled(id) then return end
		local map = self:GetMap()
		local map_id = map:GetMapID()
		local entry = reveal.art_for(map_id)
		if not entry then return end
		local ok, explored = pcall(C_MapExplorationInfo.GetExploredMapTextures, map_id)
		if not ok then return end
		local color = tint()
		for _, overlay in ipairs(reveal.unexplored(entry, explored)) do
			reveal.each_overlay_tile(entry[1], entry[2], overlay[1], overlay[2], overlay[3], overlay[4], overlay, 5,
				function(file, x, y, width, height, left, right, top, bottom)
					local texture = self.pool:Acquire()
					map:AddMaskableTexture(texture)
					texture:SetSize(width, height)
					texture:SetTexCoord(left, right, top, bottom)
					texture:SetPoint("TOPLEFT", x, -y)
					texture:SetTexture(file, nil, nil, "TRILINEAR")
					texture:SetVertexColor(color[1], color[2], color[3])
					texture:Show()
				end)
		end
		self:SetAlpha(map:GetGlobalAlpha())
	end

	function EverlookMapRevealPinMixin:OnCanvasSizeChanged()
		local map = self:GetMap()
		self:SetSize(map:DenormalizeHorizontalSize(1.0), map:DenormalizeVerticalSize(1.0))
	end
end

-- A failure inside the game's map code would show as an error on every refresh. The first one is reported, and the layer
-- then stays off until the module is turned off and on again.
local function guarded(work)
	if failed then return end
	local ok, message = pcall(work)
	if not ok then
		failed = true
		if Everlook.errors then Everlook.errors.note(id, message) end
		local handler = geterrorhandler and geterrorhandler()
		if handler then pcall(handler, message) end
	end
end

local function make_provider()
	local made = CreateFromMixins(MapCanvasDataProviderMixin)

	function made:OnAdded(canvas)
		MapCanvasDataProviderMixin.OnAdded(self, canvas)
		-- A single permanent pin, as the game's own exploration layer has.
		local pin = self:GetMap():AcquirePin("EverlookMapRevealPinTemplate", self)
		pin:SetPosition(0.5, 0.5)
		self.pin = pin
	end

	function made:OnRemoved(canvas)
		self:GetMap():RemoveAllPinsByTemplate("EverlookMapRevealPinTemplate")
		MapCanvasDataProviderMixin.OnRemoved(self, canvas)
	end

	function made:OnShow() self:RegisterEvent("MAP_EXPLORATION_UPDATED") end
	function made:OnHide() self:UnregisterEvent("MAP_EXPLORATION_UPDATED") end
	function made:OnEvent(event)
		if event == "MAP_EXPLORATION_UPDATED" then self:RefreshAllData() end
	end
	function made:OnMapChanged() self:RefreshAllData() end
	function made:RemoveAllData() if self.pin then self.pin:Clear() end end
	function made:RefreshAllData()
		if self.pin then guarded(function() self.pin:Refresh() end) end
	end
	function made:OnGlobalAlphaChanged()
		if self.pin then self.pin:SetAlpha(self:GetMap():GetGlobalAlpha()) end
	end
	return made
end

local function attach()
	if attached then return end
	if not (MapCanvasDataProviderMixin and MapCanvasPinMixin and CreateFromMixins and CreateTexturePool
		and WorldMapFrame and WorldMapFrame.AddDataProvider and C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures) then
		if not reveal.noted then
			reveal.noted = true
			if Everlook.say then Everlook.say("Map reveal needs the stock world map.") end
		end
		return
	end
	ensure_pin_mixin()
	provider = provider or make_provider()
	WorldMapFrame:AddDataProvider(provider)
	attached = true
end

local function detach()
	failed = false
	if not (attached and provider) then return end
	if WorldMapFrame and WorldMapFrame.RemoveDataProvider then WorldMapFrame:RemoveDataProvider(provider) else provider:RemoveAllData() end
	attached = false
end

local function apply(enabled)
	if enabled then
		attach()
		if provider and attached then provider:RefreshAllData() end
	else
		detach()
	end
end

function reveal.refresh()
	if attached and provider then provider:RefreshAllData() end
end

module.register({
	addon = addon_name, page = "map", order = 40,
	id = id, name = "Map reveal",
	description = "Draws the parts of a zone map you have not explored yet on the world map, so the map is whole, without fog of war. Areas you have explored stay as the game draws them, a client whose map art is not the one the table was made for draws nothing, continents and cities with no unexplored areas stay as they are, nothing is built until this is on, and turning this off puts the map back as it was.",
	options = {
		dim = { name = "Dim unexplored areas", default = true, description = "Draws the unexplored areas a little darker, so you can still tell what you have seen from what you have not. Explored areas and the map's own art are not changed, and turning this off draws them at full brightness." },
	},
	apply = apply,
	events = { "PLAYER_ENTERING_WORLD" },
	on_event = function() reveal.refresh() end,
})
