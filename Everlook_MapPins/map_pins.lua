local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "map_pins"
local provider
local attached = false
local refresh_queued = false
local pins_stale = false

Everlook.map_pins = {}

local QUEST_LABELS = { [1] = "giver", [2] = "turn-in", [4] = "objective" }
local TINT = {
	quest = { 1, 0.82, 0.2 },
	object = { 0.25, 0.75, 0.35 },
	rare = { 0.85, 0.2, 0.2 },
	flight = { 0.3, 0.55, 1 },
	vendor = { 0.65, 0.4, 0.9 },
}

local function rare(classification)
	if type(classification) ~= "string" then
		return false
	end
	local value = classification:lower()
	return value == "rare" or value == "rareelite" or value == "worldboss"
end

local function row_name(row)
	if type(row) ~= "table" then
		return nil
	end
	if type(row.name) == "string" and row.name ~= "" then
		return row.name
	end
	if type(row.title) == "string" and row.title ~= "" then
		return row.title
	end
	return nil
end

function Everlook.map_pins.for_map(map_id)
	local pins = {}
	if type(map_id) ~= "number" or not Everlook.world or not Everlook.world.on_map then
		return pins
	end
	local function add(bucket, row, key, location, kind, label)
		if type(location) ~= "table" or location.mapId ~= map_id then
			return
		end
		if type(location.x) ~= "number" or type(location.y) ~= "number" then
			return
		end
		local name = row_name(row)
		pins[#pins + 1] = {
			bucket = bucket,
			id = type(row) == "table" and row.id or key,
			x = location.x,
			y = location.y,
			role = location.role,
			kind = kind,
			label = label,
			name = name or tostring(type(row) == "table" and row.id or key),
		}
	end
	local function add_locations(bucket, row, key, kind, label)
		if type(row) ~= "table" or type(row.locations) ~= "table" then
			return
		end
		for index = 1, #row.locations do
			add(bucket, row, key, row.locations[index], kind, label)
		end
	end
	-- Only the rows that have a place on this map are read.
	local candidates = Everlook.world.on_map(map_id)
	for index = 1, #candidates do
		local bucket, row, key = candidates[index].bucket, candidates[index].row, candidates[index].key
		if type(row) == "table" then
			if bucket == "quests" then
				if type(row.locations) == "table" then
					for position = 1, #row.locations do
						local location = row.locations[position]
						local label = type(location) == "table" and QUEST_LABELS[location.role] or nil
						if label then
							add("quests", row, key, location, "quest", label)
						end
					end
				end
			elseif bucket == "objects" then
				add_locations("objects", row, key, "object", "object")
			elseif bucket == "npcs" then
				if rare(row.classification) then
					add_locations("npcs", row, key, "rare", "rare")
				else
					local trainer = row.isTrainer == true
					local seller = Everlook.world.sells(row.id)
					if trainer or seller then
						local label = "vendor"
						if trainer and seller then
							label = "vendor, trainer"
						elseif trainer then
							label = "trainer"
						end
						add_locations("npcs", row, key, "vendor", label)
					end
				end
			elseif bucket == "taxiNodes" then
				add("taxiNodes", row, key, row, "flight", "flight master")
			end
		end
	end
	return pins
end

function Everlook.map_pins.tint(kind)
	return TINT[kind] or TINT.object
end

function Everlook.map_pins.attached()
	return attached
end

local function ensure_pin_mixin()
	if type(EverlookMapPinMixin) == "table" and type(EverlookMapPinMixin.OnAcquired) == "function" then
		return
	end
	local base = MapCanvasPinMixin or {}
	if CreateFromMixins then
		EverlookMapPinMixin = CreateFromMixins(base)
	else
		EverlookMapPinMixin = {}
	end
	function EverlookMapPinMixin:OnAcquired(info)
		if type(info) ~= "table" then
			return
		end
		if self.SetSize then
			self:SetSize(14, 14)
		end
		local x = type(info.x) == "number" and (info.x / 1000) or 0
		local y = type(info.y) == "number" and (info.y / 1000) or 0
		if self.SetPosition then
			self:SetPosition(x, y)
		end
		self.info = info
		local tint = Everlook.map_pins.tint(info.kind)
		local texture = self.texture
		if type(texture) == "table" and type(texture.SetVertexColor) == "function" then
			texture:SetVertexColor(tint[1], tint[2], tint[3])
		end
		if self.SetScript then
			self:SetScript("OnEnter", self.OnMouseEnter or EverlookMapPinMixin.OnMouseEnter)
			self:SetScript("OnLeave", self.OnMouseLeave or EverlookMapPinMixin.OnMouseLeave)
		end
	end
	function EverlookMapPinMixin:OnMouseEnter()
		local info = self.info
		local tooltip = GameTooltip
		if type(info) ~= "table" or type(tooltip) ~= "table" then
			return
		end
		if type(tooltip.SetOwner) == "function" then
			tooltip:SetOwner(self, "ANCHOR_RIGHT")
		end
		if type(tooltip.ClearLines) == "function" then
			tooltip:ClearLines()
		end
		if type(tooltip.AddLine) ~= "function" then
			return
		end
		local name = type(info.name) == "string" and info.name ~= "" and info.name or "Collected"
		tooltip:AddLine(name)
		if type(info.label) == "string" and info.label ~= "" then
			tooltip:AddLine(info.label)
		end
		if type(tooltip.Show) == "function" then
			tooltip:Show()
		end
	end
	function EverlookMapPinMixin:OnMouseLeave()
		local tooltip = GameTooltip
		if type(tooltip) == "table" and type(tooltip.Hide) == "function" then
			tooltip:Hide()
		end
	end
end

-- MapCanvasDataProviderMixin:OnShow is empty. OnMapChanged is what calls
-- RefreshAllData, and reopening the same map does not change the map id.
-- Sightings while the map is closed wait for OnShow. While it is open, a
-- burst of nameplates shares one refresh.
local function map_open()
	if not WorldMapFrame or type(WorldMapFrame.IsShown) ~= "function" then
		return true
	end
	return not not WorldMapFrame:IsShown()
end

local function refresh_pins()
	if not attached or not provider or type(provider.RefreshAllData) ~= "function" then
		return
	end
	if not map_open() then
		pins_stale = true
		return
	end
	pins_stale = false
	provider:RefreshAllData()
end

-- The map being looked at, when the stock map says.
local function shown_map()
	if WorldMapFrame and type(WorldMapFrame.GetMapID) == "function" then
		local map_id = WorldMapFrame:GetMapID()
		if type(map_id) == "number" then
			return map_id
		end
	end
end

local function row_on_map(row, map_id)
	if row.mapId == map_id then
		return true
	end
	local locations = row.locations
	for index = 1, type(locations) == "table" and #locations or 0 do
		if type(locations[index]) == "table" and locations[index].mapId == map_id then
			return true
		end
	end
	return false
end

local function queue_pins(bucket, row)
	if not attached or not provider then
		return
	end
	-- A place on another map changes nothing here, and drawing a big map reads many pages.
	if type(row) == "table" and bucket ~= "vendors" then
		local looked_at = shown_map()
		if looked_at and not row_on_map(row, looked_at) then
			return
		end
	end
	if not map_open() then
		pins_stale = true
		return
	end
	if refresh_queued then
		return
	end
	refresh_queued = true
	local function run()
		refresh_queued = false
		refresh_pins()
	end
	if C_Timer and type(C_Timer.After) == "function" then
		C_Timer.After(1, run)
	else
		run()
	end
end

local function apply(enabled)
	if not enabled then
		if attached and WorldMapFrame and WorldMapFrame.RemoveDataProvider and provider then
			WorldMapFrame:RemoveDataProvider(provider)
		end
		attached = false
		provider = nil
		refresh_queued = false
		pins_stale = false
		return
	end
	if attached then
		return
	end
	if not MapCanvasDataProviderMixin or not CreateFromMixins or not WorldMapFrame or not WorldMapFrame.AddDataProvider then
		if not Everlook.map_pins.noted and Everlook.say then
			Everlook.map_pins.noted = true
			Everlook.say("Map pins need the stock world map.")
		end
		return
	end
	ensure_pin_mixin()
	provider = CreateFromMixins(MapCanvasDataProviderMixin)
	function provider:RemoveAllData()
		local map = self.GetMap and self:GetMap()
		if map and type(map.RemoveAllPinsByTemplate) == "function" then
			map:RemoveAllPinsByTemplate("EverlookMapPinTemplate")
		end
	end
	function provider:RefreshAllData()
		self:RemoveAllData()
		local map = self.GetMap and self:GetMap()
		if not map or type(map.GetMapID) ~= "function" or type(map.AcquirePin) ~= "function" then
			return
		end
		local pins = Everlook.map_pins.for_map(map:GetMapID())
		for index = 1, #pins do
			map:AcquirePin("EverlookMapPinTemplate", pins[index])
		end
	end
	function provider:OnShow()
		if pins_stale then refresh_pins() end
	end
	WorldMapFrame:AddDataProvider(provider)
	attached = true
end

if Everlook.world and Everlook.world.watch then
	Everlook.world.watch(function(bucket, row)
		queue_pins(bucket, row)
	end)
end

module.register({
	addon = addon_name, page = "map", order = 10,
	id = id,
	name = "Map pins",
	description = "Draws quest givers, turn-ins, objectives, objects, rares, world bosses, flight masters, vendors, and trainers you have seen on the world map. Any other creature stays off it, a spot with no coordinates stays off, a rare or world boss who also sells or trains is drawn as the rare, the minimap is left alone, a client without the stock world map draws nothing and says once that the pins need it, and turning this off removes the pins.",
	apply = apply,
})
