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

local function rounded_layer(parent, color, inset, sublevel, draw_layer)
	local layer = { parent = parent, pieces = {}, corners = {}, inset = inset, color = color }
	if color == FILL then surface_layers[#surface_layers + 1] = layer end
	for row = 1, 3 do
		for column = 1, 3 do
			local texture = call(parent, "CreateTexture", nil, draw_layer or "BACKGROUND", nil, sublevel)
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

-- The colour the open island's body shows, as one opaque-ish colour, so a fade
-- laid over its content ends in the same dark as the surface around it.
function surface.body_color()
	if native_available() then
		local red, green, blue = FILL[1], FILL[2], FILL[3]
		local color = TOOLTIP_DEFAULT_BACKGROUND_COLOR
		if color and color.GetRGB then red, green, blue = color:GetRGB() end
		return red, green, blue, 1 - (1 - native_alpha) * (1 - native_alpha * BACKING_SHARE)
	end
	return FILL[1], FILL[2], FILL[3], FILL[4]
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

-- Sizes one rounded layer to `width` by `height`, `drop` lower than the frame's top.
-- A layer that something else shows and hides (the glow) is sized and left as it is.
local function size_layer(layer, width, height, radius, drop, leave_visibility)
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
			call(texture, "SetPoint", "TOPLEFT", layer.parent, "TOPLEFT", inset + x, -inset - y - drop)
			call(texture, "SetSize", widths[column], heights[row])
			if not leave_visibility then call(texture, widths[column] > 0 and heights[row] > 0 and "Show" or "Hide") end
			x = x + widths[column]
		end
		y = y + heights[row]
	end
end

function surface.size(layers, width, height, radius)
	if layers.native then return end
	for index, layer in ipairs(layers) do size_layer(layer, width, height, radius, index == 1 and 3 or 0) end
end

-- A quiet button's surface: a thin outline around a fill a shade off the panel's, so it reads as
-- a control without shouting. It rests, lights a little under the pointer and darkens when pressed.
local BUTTON_RADIUS = 6
local BUTTON_STATES = {
	rest = { edge = { 1, 1, 1, 0.2 }, fill = { 22 / 255, 25 / 255, 32 / 255, 1 } },
	hover = { edge = { 1, 1, 1, 0.45 }, fill = { 38 / 255, 43 / 255, 55 / 255, 1 } },
	press = { edge = { 1, 1, 1, 0.45 }, fill = { 14 / 255, 16 / 255, 21 / 255, 1 } },
}

function surface.make_button(parent)
	local rest = BUTTON_STATES.rest
	return {
		edge = rounded_layer(parent, { unpack(rest.edge) }, 0, -3),
		fill = rounded_layer(parent, { unpack(rest.fill) }, 1, -2),
	}
end

function surface.size_button(button, width, height)
	size_layer(button.edge, width, height, BUTTON_RADIUS, 0)
	size_layer(button.fill, width, height, BUTTON_RADIUS, 0)
end

-- state is "rest", "hover" or "press".
function surface.tint_button(button, state)
	local colors = BUTTON_STATES[state] or BUTTON_STATES.rest
	for name, layer in pairs(button) do
		local color = colors[name]
		for index, texture in ipairs(layer.pieces) do
			tint_piece(texture, layer.corners[index], color)
		end
	end
end

-- A reaction's colour on a surface: a tint over the body that follows its rounded shape, and
-- a line along each straight edge. Both sit above the fill and below the text, start
-- invisible, and take no art but the corner piece the surface already uses.
local EDGE_THICKNESS = 2

function surface.make_glow(parent)
	local glow = { parent = parent, tint = rounded_layer(parent, { 1, 1, 1, 0 }, 1, 2, "ARTWORK"), edges = {} }
	for index = 1, 4 do
		glow.edges[index] = call(parent, "CreateTexture", nil, "ARTWORK", nil, 3)
		call(glow.edges[index], "SetColorTexture", 1, 1, 1, 0)
		call(glow.edges[index], "Hide")
	end
	surface.set_glow(glow, nil, 0, 0)
	return glow
end

function surface.size_glow(glow, width, height, radius)
	if not glow then return end
	size_layer(glow.tint, width, height, radius, 0, true)
	local top, bottom, left, right = unpack(glow.edges)
	local run_x, run_y = math.max(0, width - radius * 2), math.max(0, height - radius * 2)
	local parent = glow.parent
	for _, edge in ipairs(glow.edges) do call(edge, "ClearAllPoints") end
	call(top, "SetPoint", "TOPLEFT", parent, "TOPLEFT", radius, 0)
	call(top, "SetSize", run_x, EDGE_THICKNESS)
	call(bottom, "SetPoint", "BOTTOMLEFT", parent, "BOTTOMLEFT", radius, 0)
	call(bottom, "SetSize", run_x, EDGE_THICKNESS)
	call(left, "SetPoint", "TOPLEFT", parent, "TOPLEFT", 0, -radius)
	call(left, "SetSize", EDGE_THICKNESS, run_y)
	call(right, "SetPoint", "TOPRIGHT", parent, "TOPRIGHT", 0, -radius)
	call(right, "SetSize", EDGE_THICKNESS, run_y)
end

-- Shows the glow in `color` ({ r, g, b }) at the given opacities, or hides it when both are zero.
function surface.set_glow(glow, color, tint, edge)
	if not glow then return end
	local red, green, blue = 1, 1, 1
	if color then red, green, blue = color[1], color[2], color[3] end
	for index, texture in ipairs(glow.tint.pieces) do
		if tint > 0 then
			if glow.tint.corners[index] then
				call(texture, "SetVertexColor", red, green, blue, tint)
			else
				call(texture, "SetColorTexture", red, green, blue, tint)
			end
		end
		call(texture, tint > 0 and "Show" or "Hide")
	end
	for _, texture in ipairs(glow.edges) do
		if edge > 0 then call(texture, "SetColorTexture", red, green, blue, edge) end
		call(texture, edge > 0 and "Show" or "Hide")
	end
end
