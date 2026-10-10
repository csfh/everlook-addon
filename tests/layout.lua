-- Resolves the anchors that the fake frames record into rectangles, so a test
-- can check where things land and not only which anchor was set. It reads the
-- same anchor rules the game does for the cases the island uses: a point, a
-- relative region and point, an offset, two-sided anchors that give a size, and
-- SetAllPoints. Text takes the width and height the fake reports.
--
-- Rectangles are in screen units with y growing downward, so `top` is the
-- distance from the top of the screen.
local layout = {}

local SCREEN = { left = 0, top = 0, width = 1920, height = 1080 }

local function across(point)
	if point:find("LEFT", 1, true) then return 0 end
	if point:find("RIGHT", 1, true) then return 1 end
	return 0.5
end

local function down(point)
	if point:find("TOP", 1, true) then return 0 end
	if point:find("BOTTOM", 1, true) then return 1 end
	return 0.5
end

local function parse(point)
	local relative, relative_point, x, y
	local index = 2
	if type(point[index]) == "table" then relative, index = point[index], index + 1 end
	if type(point[index]) == "string" then relative_point, index = point[index], index + 1 end
	x, y = tonumber(point[index]) or 0, tonumber(point[index + 1]) or 0
	return { name = point[1], relative = relative, relative_point = relative_point or point[1], x = x, y = y }
end

local function rectangle(left, top, width, height)
	return { left = left, top = top, width = width, height = height, right = left + width, bottom = top + height }
end

function layout.new()
	local resolved, active = {}, {}
	local resolve

	local function natural(region)
		-- A width or height of 0 on text means "as large as the text".
		local width, height = region.width, region.height
		if (width == nil or width == 0) and region.GetStringWidth then width = region:GetStringWidth() end
		if (height == nil or height == 0) and region.GetStringHeight then height = region:GetStringHeight() end
		return width, height
	end

	local function anchor_rectangle(region, relative)
		if relative == nil or relative == true then relative = region.parent end
		if relative == nil or relative == region then return SCREEN end
		if type(relative) ~= "table" or (relative.points == nil and relative.all_points == nil and relative.width == nil and relative.parent == nil) then
			return SCREEN
		end
		return resolve(relative)
	end

	resolve = function(region)
		if resolved[region] then return resolved[region] end
		if active[region] then error("anchor cycle at " .. tostring(region.name or region.text)) end
		active[region] = true
		local rect
		if region.all_points then
			local target = region.all_points
			local box = anchor_rectangle(region, target)
			rect = rectangle(box.left, box.top, box.width, box.height)
		else
			local width, height = natural(region)
			local points = {}
			for _, raw in ipairs(region.points or {}) do points[#points + 1] = parse(raw) end
			local left_edge, right_edge, top_edge, bottom_edge
			for _, point in ipairs(points) do
				local box = anchor_rectangle(region, point.relative)
				local anchor_x = box.left + across(point.relative_point) * box.width + point.x
				local anchor_y = box.top + down(point.relative_point) * box.height - point.y
				if point.name:find("LEFT", 1, true) then left_edge = left_edge or anchor_x end
				if point.name:find("RIGHT", 1, true) then right_edge = right_edge or anchor_x end
				if point.name:find("TOP", 1, true) then top_edge = top_edge or anchor_y end
				if point.name:find("BOTTOM", 1, true) then bottom_edge = bottom_edge or anchor_y end
				point.x_anchor, point.y_anchor = anchor_x, anchor_y
			end
			if left_edge and right_edge then width = right_edge - left_edge end
			if top_edge and bottom_edge then height = bottom_edge - top_edge end
			width, height = width or 0, height or 0
			local first = points[1]
			local left, top = 0, 0
			if first then
				left = left_edge or (right_edge and right_edge - width) or (first.x_anchor - across(first.name) * width)
				top = top_edge or (bottom_edge and bottom_edge - height) or (first.y_anchor - down(first.name) * height)
			end
			rect = rectangle(left, top, width, height)
		end
		active[region], resolved[region] = nil, rect
		return rect
	end

	return { rectangle = resolve }
end

-- The fake frames cannot play an animation, so this plays every one to its end:
-- each animation reports full progress, then every frame's OnUpdate runs and
-- each group's OnFinished fires. What the island sized or faded is then final.
function layout.settle(frames)
	for _ = 1, 3 do
		for _, frame in ipairs(frames) do
			for _, group in ipairs(frame.animation_groups or {}) do
				for _, animation in ipairs(group.animations) do animation.progress = 1 end
			end
		end
		for _, frame in ipairs(frames) do
			if frame.scripts and frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, 1) end
		end
	end
	for _, frame in ipairs(frames) do
		for _, group in ipairs(frame.animation_groups or {}) do
			if group.scripts and group.scripts.OnFinished then group.scripts.OnFinished(group) end
		end
	end
end

-- A frame is shown when it and every ancestor is not hidden.
local function visible(region)
	while region do
		if region.shown == false then return false end
		region = region.parent
	end
	return true
end

local function children(frame)
	local list = {}
	for _, region in ipairs(frame.regions or {}) do list[#list + 1] = region end
	return list
end

-- Walks every shown region under `frames` (a list of frames) and reports the
-- breaks of the layout rules that do not need a picture to see: a part outside
-- the frame that holds it, and two pieces of text that overlap.
function layout.lint(frames, options)
	options = options or {}
	local measure = layout.new()
	local found = {}
	local function label(region)
		return tostring(region.name or region.text or region.atlas or region.path or "region")
	end
	for _, frame in ipairs(frames) do
		if visible(frame) then
			local box = measure.rectangle(frame)
			local texts = {}
			for _, region in ipairs(children(frame)) do
				-- Text with nothing to draw takes no room, so it cannot break a rule.
				if visible(region) and not (region.GetStringWidth and (region.text or "") == "") then
					local rect = measure.rectangle(region)
					local inside = rect.left >= box.left - 0.5 and rect.right <= box.right + 0.5
						and rect.top >= box.top - 0.5 and rect.bottom <= box.bottom + 0.5
					if not inside and not frame.clips and not (options.skip and options.skip(frame, region)) then
						found[#found + 1] = string.format("%s leaves %s: [%g..%g, %g..%g] outside [%g..%g, %g..%g]", label(region), label(frame),
							rect.left, rect.right, rect.top, rect.bottom, box.left, box.right, box.top, box.bottom)
					end
					if region.GetStringWidth and (region.text or "") ~= "" then texts[#texts + 1] = { region = region, rect = rect } end
				end
			end
			for first = 1, #texts do
				for second = first + 1, #texts do
					local a, b = texts[first].rect, texts[second].rect
					local overlap = math.min(a.right, b.right) - math.max(a.left, b.left) > 0.5
						and math.min(a.bottom, b.bottom) - math.max(a.top, b.top) > 0.5
					if overlap then
						found[#found + 1] = string.format("%q overlaps %q in %s", texts[first].region.text, texts[second].region.text, label(frame))
					end
				end
			end
		end
	end
	return found
end

-- One line per shown frame and region, positions relative to the root's top
-- left corner. It is how to read what a change did to the layout.
function layout.describe(frames, root)
	local measure = layout.new()
	local origin = measure.rectangle(root)
	local lines = {}
	local function name_of(region)
		return tostring(region.text or region.atlas or (region.path and region.path:match("[^\\]+$")) or "?"):sub(1, 34)
	end
	local function walk(frame, depth)
		if frame.shown == false then return end
		local rect = measure.rectangle(frame)
		lines[#lines + 1] = string.rep("  ", depth) .. string.format("[%s] x=%g y=%g w=%g h=%g", frame.name or "frame", rect.left - origin.left, rect.top - origin.top, rect.width, rect.height)
		for _, region in ipairs(frame.regions or {}) do
			if region.shown ~= false then
				local box = measure.rectangle(region)
				lines[#lines + 1] = string.rep("  ", depth + 1) .. string.format("%-34s x=%g y=%g w=%g h=%g", name_of(region), box.left - origin.left, box.top - origin.top, box.width, box.height)
			end
		end
		for _, child in ipairs(frames) do
			if child.parent == frame then walk(child, depth + 1) end
		end
	end
	walk(root, 0)
	return table.concat(lines, "\n")
end

local function quote(text)
	return '"' .. tostring(text):gsub('[%c"\\]', function(char)
		if char == '"' then return '\\"' end
		if char == "\\" then return "\\\\" end
		if char == "\n" then return "\\n" end
		return string.format("\\u%04x", char:byte())
	end) .. '"'
end

local function number_list(values)
	if type(values) ~= "table" then return "null" end
	local out = {}
	for index = 1, #values do out[index] = tostring(tonumber(values[index]) or 0) end
	return "[" .. table.concat(out, ",") .. "]"
end

-- The shown frames and regions under `root` as JSON, positions relative to its
-- corner, in the order they are drawn. `now` is the game time, which a ring needs
-- to turn its cooldown into a fraction. scripts/island_layout_html.py turns this
-- into a picture.
function layout.export(frames, root, now)
	local measure = layout.new()
	local origin = measure.rectangle(root)
	local items = {}
	local function box(rect)
		return string.format('"x":%g,"y":%g,"w":%g,"h":%g', rect.left - origin.left, rect.top - origin.top, rect.width, rect.height)
	end
	-- A frame faded to nothing, and everything inside it, is left out.
	local function walk(frame, depth, inherited)
		if frame.shown == false then return end
		local alpha = inherited * (frame.alpha or 1)
		if alpha < 0.01 then return end
		items[#items + 1] = string.format('{"kind":"frame","name":%s,%s,"alpha":%g,"clips":%s,"cooldown":%s,"swipe":%s}',
			quote(frame.name or ""), box(measure.rectangle(frame)), alpha, tostring(frame.clips == true),
			(frame.cooldown and now) and string.format("%g", (now - frame.cooldown.start) / frame.cooldown.duration) or "null",
			number_list(frame.swipe_color))
		for _, region in ipairs(frame.regions or {}) do
			if region.shown ~= false then
				local rect = measure.rectangle(region)
				local region_alpha = alpha * (region.alpha or 1)
				if region.GetStringWidth then
					items[#items + 1] = string.format('{"kind":"text","text":%s,%s,"font":%s,"color":%s,"justify":%s,"alpha":%g}', quote(region.text or ""), box(rect),
						quote(region.font or ""), number_list(region.color), quote(region.justify or "LEFT"), region_alpha)
				else
					items[#items + 1] = string.format('{"kind":"texture","path":%s,"atlas":%s,%s,"color":%s,"rotation":%g,"alpha":%g}',
						quote(region.path or ""), quote(region.atlas or ""), box(rect), number_list(region.color), region.rotation or 0, region_alpha)
				end
			end
		end
		for _, child in ipairs(frames) do
			if child.parent == frame then walk(child, depth + 1, alpha) end
		end
	end
	walk(root, 0, 1)
	return "[" .. table.concat(items, ",\n") .. "]"
end

return layout
