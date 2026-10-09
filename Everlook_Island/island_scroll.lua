local Everlook = Everlook

-- A slim scroll bar for the inbox: a dim track and a thumb you can drag. The
-- mouse wheel still works. The bar sits in the right margin of the open
-- island, so it never covers a row.
local scroll = {}
Everlook.island_scroll = scroll

-- The thumb sits inside the experience rim, in the margin the quest panel leaves.
local THUMB_MIN, WIDTH, OFFSET = 24, 6, 14
-- A fade this tall tells you the list goes on past that edge. It sits above the
-- rows and below the thumb.
local FADE_HEIGHT, FADE_LEVEL = 20, 58

local function call(object, method, ...)
	local fn = object and object[method]
	if type(fn) == "function" then return fn(object, ...) end
end

-- options.scroll_to(offset) moves the list. options.ratio() is screen pixels
-- per Island unit, so a drag follows the pointer at any scale.
function scroll.make(parent, options)
	local handle = { parent = parent, options = options, travel = 0, range = 0, offset = 0 }
	handle.track = call(parent, "CreateTexture", nil, "ARTWORK")
	call(handle.track, "SetColorTexture", 1, 1, 1, 0.1)
	call(handle.track, "Hide")
	handle.thumb = CreateFrame("Button", "EverlookIslandScrollThumb", parent)
	call(handle.thumb, "SetFrameLevel", 60)
	call(handle.thumb, "RegisterForClicks", "LeftButtonUp")
	local face = call(handle.thumb, "CreateTexture", nil, "OVERLAY")
	call(face, "SetAllPoints", handle.thumb)
	call(face, "SetColorTexture", 0.75, 0.78, 0.85, 0.55)
	handle.face = face
	call(handle.thumb, "Hide")
	handle.fades = CreateFrame("Frame", nil, parent)
	call(handle.fades, "SetAllPoints", parent)
	call(handle.fades, "SetFrameLevel", FADE_LEVEL)
	call(handle.fades, "EnableMouse", false)
	handle.fade_top = call(handle.fades, "CreateTexture", nil, "OVERLAY")
	handle.fade_bottom = call(handle.fades, "CreateTexture", nil, "OVERLAY")
	-- A gradient only tints a texture that already draws, so each starts as plain white.
	call(handle.fade_top, "SetColorTexture", 1, 1, 1, 1)
	call(handle.fade_bottom, "SetColorTexture", 1, 1, 1, 1)
	call(handle.fade_top, "Hide")
	call(handle.fade_bottom, "Hide")
	local function stop()
		handle.drag = nil
		call(handle.thumb, "SetScript", "OnUpdate", nil)
	end
	call(handle.thumb, "SetScript", "OnMouseDown", function(_, button)
		if button ~= "LeftButton" or handle.travel <= 0 then return end
		local _, cursor_y = GetCursorPosition()
		handle.drag = { cursor_y = cursor_y, offset = handle.offset }
		call(handle.thumb, "SetScript", "OnUpdate", function()
			local drag = handle.drag
			if not drag then return end
			-- Letting go away from the thumb sends no mouse-up to it, so the button is checked here.
			if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then stop(); return end
			local _, now_y = GetCursorPosition()
			local moved = (drag.cursor_y - now_y) / options.ratio()
			options.scroll_to(drag.offset + moved / handle.travel * handle.range)
		end)
	end)
	call(handle.thumb, "SetScript", "OnMouseUp", stop)
	return handle
end

-- Thumb size and position for a list of content_height seen through view_height.
function scroll.metrics(view_height, content_height, offset)
	if view_height <= 0 or content_height <= view_height then return nil end
	local thumb = math.max(THUMB_MIN, math.floor(view_height * view_height / content_height))
	thumb = math.min(thumb, view_height)
	local range = content_height - view_height
	local travel = view_height - thumb
	local at = range > 0 and math.max(0, math.min(1, offset / range)) * travel or 0
	return { thumb = thumb, travel = travel, range = range, at = at }
end

-- One edge's fade: dark at the edge it sits on, clear toward the rows. The
-- colour is the surface's own, so the rows seem to slide under it.
local function fade(handle, texture, edge, top, view_height, width, visible)
	if not visible then
		call(texture, "Hide")
		return
	end
	local red, green, blue, alpha = Everlook.island_surface.body_color()
	local dark, clear = CreateColor(red, green, blue, alpha), CreateColor(red, green, blue, 0)
	call(texture, "ClearAllPoints")
	if edge == "top" then
		call(texture, "SetPoint", "TOPLEFT", handle.parent, "TOPLEFT", 12, -top)
		call(texture, "SetGradient", "VERTICAL", clear, dark)
	else
		call(texture, "SetPoint", "TOPLEFT", handle.parent, "TOPLEFT", 12, -(top + view_height - math.min(FADE_HEIGHT, view_height / 3)))
		call(texture, "SetGradient", "VERTICAL", dark, clear)
	end
	call(texture, "SetSize", width, math.min(FADE_HEIGHT, view_height / 3))
	call(texture, "Show")
end

-- width is the list's width. Each edge fades while there is more past it.
function scroll.layout(handle, top, view_height, content_height, offset, width)
	if not handle then return end
	local m = scroll.metrics(view_height, content_height, offset)
	handle.above = m ~= nil and offset > 0.5
	handle.below = m ~= nil and offset < m.range - 0.5
	fade(handle, handle.fade_top, "top", top, view_height, width or 0, handle.above)
	fade(handle, handle.fade_bottom, "bottom", top, view_height, width or 0, handle.below)
	if not m then
		call(handle.track, "Hide")
		call(handle.thumb, "Hide")
		handle.travel, handle.range, handle.offset = 0, 0, 0
		return
	end
	handle.travel, handle.range, handle.offset = m.travel, m.range, offset
	call(handle.track, "ClearAllPoints")
	call(handle.track, "SetPoint", "TOPRIGHT", handle.parent, "TOPRIGHT", -OFFSET, -top)
	call(handle.track, "SetSize", WIDTH, view_height)
	call(handle.track, "Show")
	call(handle.thumb, "ClearAllPoints")
	call(handle.thumb, "SetPoint", "TOPRIGHT", handle.parent, "TOPRIGHT", -OFFSET, -(top + m.at))
	call(handle.thumb, "SetSize", WIDTH, m.thumb)
	call(handle.thumb, "Show")
end

function scroll.hide(handle)
	if not handle then return end
	handle.above, handle.below = false, false
	call(handle.fade_top, "Hide")
	call(handle.fade_bottom, "Hide")
	call(handle.track, "Hide")
	call(handle.thumb, "Hide")
end
