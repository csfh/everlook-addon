local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "coordinates"
local ticker
local label

Everlook.coordinates = {}

function Everlook.coordinates.format(x, y)
	if type(x) ~= "number" or type(y) ~= "number" then
		return ""
	end
	return string.format("%.1f, %.1f", x * 100, y * 100)
end

local function player_xy()
	if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetPlayerMapPosition then
		return nil
	end
	local map_id = C_Map.GetBestMapForUnit("player")
	if type(map_id) ~= "number" then
		return nil
	end
	local position = C_Map.GetPlayerMapPosition(map_id, "player")
	if type(position) ~= "table" then
		return nil
	end
	local x, y
	if position.GetXY then
		x, y = position:GetXY()
	else
		x, y = position.x, position.y
	end
	if type(x) ~= "number" or type(y) ~= "number" then
		return nil
	end
	return x, y
end

function Everlook.coordinates.player_text()
	local x, y = player_xy()
	return Everlook.coordinates.format(x, y)
end

local function hide()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	if label then
		label:Hide()
	end
end

local function apply(enabled)
	if not enabled then
		hide()
		return
	end
	if not label and Minimap and CreateFrame then
		local frame = CreateFrame("Frame", nil, Minimap)
		frame:SetSize(80, 14)
		frame:SetPoint("TOP", Minimap, "BOTTOM", 0, -2)
		label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		label:SetPoint("CENTER")
	end
	if not label or not C_Timer or not C_Timer.NewTicker or ticker then
		return
	end
	label:Show()
	ticker = C_Timer.NewTicker(0.2, function()
		if not module.enabled(id) then
			hide()
			return
		end
		label:SetText(Everlook.coordinates.player_text())
	end)
end

module.register({
	addon = addon_name, page = "map", order = 20,
	id = id,
	name = "Coordinates",
	description = "Shows where you are on the current map, under the minimap, as the horizontal position and then the vertical one, each with one decimal, and keeps that line current while you move. The world map stays as it is, the line stays blank when the client has no map or no position, nothing is shown when there is no minimap to attach it to or no way to keep it current, and turning this off hides it.",
	apply = apply,
})
