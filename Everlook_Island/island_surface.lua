local Everlook = Everlook

-- The Island's rounded surface: a tintable quarter circle supplies the corners
-- and straight sections stretch without stretching the radius. Layers stay
-- allocated across repaints. smart_island.lua owns when and how big.
local surface = {}
Everlook.island_surface = surface

local ART = "Interface\\AddOns\\Everlook_Island\\assets\\"
local EDGE = { 1, 1, 1, 0.12 }
local FILL = { 13 / 255, 15 / 255, 20 / 255, 0.96 }

local function call(object, method, ...)
	local fn = object and object[method]
	if type(fn) == "function" then return fn(object, ...) end
end

local surface_layers = {}

local function tint_piece(texture, corner, color)
	if corner then
		call(texture, "SetVertexColor", unpack(color))
	else
		call(texture, "SetColorTexture", unpack(color))
	end
end

local function rounded_layer(parent, color, inset, sublevel)
	local layer = { parent = parent, pieces = {}, corners = {}, inset = inset, color = color }
	if color == FILL then surface_layers[#surface_layers + 1] = layer end
	for row = 1, 3 do
		for column = 1, 3 do
			local texture = call(parent, "CreateTexture", nil, "BACKGROUND", nil, sublevel)
			if row ~= 2 and column ~= 2 then
				call(texture, "SetTexture", ART .. "island_corner.tga")
				call(texture, "SetTexCoord", column == 1 and 0 or 1, column == 1 and 1 or 0,
					row == 1 and 0 or 1, row == 1 and 1 or 0)
				call(texture, "SetVertexColor", unpack(color))
				layer.corners[#layer.pieces + 1] = true
			else
				call(texture, "SetColorTexture", unpack(color))
			end
			layer.pieces[#layer.pieces + 1] = texture
		end
	end
	return layer
end

-- The game's own tooltip border and fill, laid on the parent frame. The pieces
-- anchor to the parent's edges, so sizing the parent sizes the surface. Without
-- NineSliceUtil the hand-drawn layers below stand in.
local NATIVE_LAYOUT = "TooltipDefaultLayout"
local natives = {}
local native_alpha = FILL[4]
-- Half the opacity again keeps nameplates out of the text without turning the panel black.
local BACKING_SHARE = 0.5

local function native_available()
	return NineSliceUtil and NineSliceUtil.GetLayout and NineSliceUtil.ApplyLayoutByName
		and NineSliceUtil.GetLayout(NATIVE_LAYOUT) ~= nil
end

local function tint_native(handle)
	local color = TOOLTIP_DEFAULT_BACKGROUND_COLOR
	local red, green, blue = FILL[1], FILL[2], FILL[3]
	if color and color.GetRGB then red, green, blue = color:GetRGB() end
	call(handle.parent.Center, "SetVertexColor", red, green, blue, native_alpha)
	-- The game's fill lets a lot of the world through. A dark backing under it
	-- follows the same opacity, so names and bars behind the Island stay out of the text.
	call(handle.backing, "SetColorTexture", FILL[1], FILL[2], FILL[3], native_alpha * BACKING_SHARE)
end

-- Every card, the pill and the open island share the one surface color, so
-- the opacity option changes that color and retints the layers already built.
function surface.set_opacity(alpha)
	if FILL[4] == alpha then return end
	FILL[4] = alpha
	native_alpha = alpha
	for _, handle in ipairs(natives) do tint_native(handle) end
	for _, layer in ipairs(surface_layers) do
		for index, texture in ipairs(layer.pieces) do tint_piece(texture, layer.corners[index], layer.color) end
	end
end

function surface.make(parent)
	if native_available() then
		NineSliceUtil.ApplyLayoutByName(parent, NATIVE_LAYOUT)
		local handle = { native = true, parent = parent }
		handle.backing = call(parent, "CreateTexture", nil, "BACKGROUND", nil, -8)
		call(handle.backing, "SetPoint", "TOPLEFT", parent, "TOPLEFT", 4, -4)
		call(handle.backing, "SetPoint", "BOTTOMRIGHT", parent, "BOTTOMRIGHT", -4, 4)
		natives[#natives + 1] = handle
		tint_native(handle)
		return handle
	end
	return {
		rounded_layer(parent, { 0, 0, 0, 0.18 }, -2, -8),
		rounded_layer(parent, EDGE, 0, -7),
		rounded_layer(parent, FILL, 1, -6),
	}
end

function surface.size(layers, width, height, radius)
	if layers.native then return end
	for index, layer in ipairs(layers) do
		local inset = layer.inset
		local w, h = width - inset * 2, height - inset * 2
		local r = math.min(radius - inset, w / 2, h / 2)
		local widths, heights = { r, math.max(0, w - r * 2), r }, { r, math.max(0, h - r * 2), r }
		local y = 0
		for row = 1, 3 do
			local x = 0
			for column = 1, 3 do
				local texture = layer.pieces[(row - 1) * 3 + column]
				call(texture, "ClearAllPoints")
				call(texture, "SetPoint", "TOPLEFT", layer.parent, "TOPLEFT", inset + x, -inset - y - (index == 1 and 3 or 0))
				call(texture, "SetSize", widths[column], heights[row])
				call(texture, widths[column] > 0 and heights[row] > 0 and "Show" or "Hide")
				x = x + widths[column]
			end
			y = y + heights[row]
		end
	end
end
