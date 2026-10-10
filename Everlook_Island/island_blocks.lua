local Everlook = Everlook

-- Draws the blocks of sections into a pane. It owns frames and reads records from
-- island_section.lua; it knows nothing of the game. Frames are pooled: each paint
-- takes them from the front of a pool and hides what it does not use.
local blocks = {}
Everlook.island_blocks = blocks

local island_row = Everlook.island_row

local function call(object, method, ...)
	local fn = object and object[method]
	if type(fn) == "function" then return fn(object, ...) end
end

-- A producer's callback runs with the handle and the action id, as a notice's does,
-- and its failures go to the error handler instead of stopping the island.
local function run(action, handle)
	local ok, failure = pcall(action.callback, handle, action.id)
	if not ok then
		local handler = geterrorhandler and geterrorhandler()
		if handler then handler("Everlook Smart Island (section action): " .. tostring(failure)) end
	end
end

-- host brings what the island owns: label(parent, justify, role), visual(frame, preview),
-- link(parent, name, title, callback), set_link_text(button, text), hover(frame, node),
-- controls (the list that keeps a hover preview open), heading(label, text), rings,
-- ring_size and space.
local View = {}
View.__index = View

function blocks.new(parent, host)
	return setmetatable({ parent = parent, host = host, rows = {}, texts = {}, headings = {} }, View)
end

local function row_slot(self, index)
	local slot = self.rows[index]
	if slot then return slot end
	local host = self.host
	local frame = CreateFrame("Button", nil, self.parent)
	call(frame, "RegisterForClicks", "LeftButtonUp")
	local visual = host.visual(frame, true)
	slot = { frame = frame, node = { tooltip = nil } }
	slot.row = island_row.new(visual, { label = host.label, rings = host.rings, ring_size = host.ring_size, title_role = "text" })
	slot.link = host.link(frame, nil, "Action", function()
		if slot.action then run(slot.action, slot.handle) end
	end)
	call(slot.link, "SetPoint", "RIGHT", frame, "RIGHT", -host.space.edge, 0)
	host.hover(frame, slot.node)
	self.rows[index] = slot
	return slot
end

local function label_slot(self, pool, index, role)
	local slot = pool[index]
	if slot then return slot end
	slot = self.host.label(self.parent, "LEFT", role)
	pool[index] = slot
	return slot
end

local function tooltip_text(tooltip)
	if not tooltip then return nil end
	local lines = { tooltip.title }
	for _, line in ipairs(tooltip.lines) do lines[#lines + 1] = line end
	return table.concat(lines, "\n")
end

-- Lays `sections` out one after another from `top`, `width` wide, inside the pane's frame.
-- With `title_in_band` the first section's title is left out, because the pane's heading band shows it.
-- Returns where they end (`top` when there is nothing).
function View:paint(sections, top, width, title_in_band)
	local host, space = self.host, self.host.space
	local inset = space.edge
	local inner = width - 2 * inset
	local used = { rows = 0, texts = 0, headings = 0 }
	local y = top
	local function place(region, height)
		call(region, "ClearAllPoints")
		call(region, "SetPoint", "TOPLEFT", self.parent, "TOPLEFT", inset, -y)
		y = y + height
	end
	local function heading(text)
		used.headings = used.headings + 1
		local label = label_slot(self, self.headings, used.headings, "caption")
		host.heading(label, text)
		call(label, "SetWidth", inner)
		place(label, call(label, "GetLineHeight") or 12)
		call(label, "Show")
	end
	for index, record in ipairs(sections) do
		if index > 1 then y = y + space.section end
		if record.title and not (index == 1 and title_in_band) then
			heading(record.title)
			y = y + space.within
		end
		local previous
		for _, block in ipairs(record.blocks) do
			local kind = block.kind
			if previous and previous ~= "gap" and kind ~= "gap" then
				y = y + ((previous == "row" and kind == "row") and space.within or space.near)
			end
			if kind == "gap" then
				y = y + space[block.size]
			elseif kind == "heading" then
				heading(block.text)
			elseif kind == "text" then
				used.texts = used.texts + 1
				local label = label_slot(self, self.texts, used.texts, "text")
				call(label, "SetWidth", inner)
				call(label, "SetText", block.text)
				place(label, call(label, "GetStringHeight") or 14)
				call(label, "Show")
			else
				used.rows = used.rows + 1
				local slot = row_slot(self, used.rows)
				slot.handle, slot.action = record.handle, block.action
				slot.node.tooltip = tooltip_text(block.tooltip)
				-- A row carries its own insets, the same the capsule has, so its frame is the whole pane.
				call(slot.frame, "SetSize", width, space.control)
				call(slot.frame, "ClearAllPoints")
				call(slot.frame, "SetPoint", "TOPLEFT", self.parent, "TOPLEFT", 0, -y)
				local reserve = 0
				if block.action then
					host.set_link_text(slot.link, block.action.label)
					reserve = (call(slot.link, "GetWidth") or 48) + space.near
				end
				call(slot.link, block.action and "Show" or "Hide")
				call(slot.frame, "Show")
				slot.row:set({ icon = block.row.icon, title = block.row.title, ring = block.row.ring, labels = block.row.labels, badge = block.row.badge }, reserve)
				y = y + space.control
			end
			previous = kind
		end
	end
	for index = used.rows + 1, #self.rows do call(self.rows[index].frame, "Hide") end
	for index = used.texts + 1, #self.texts do call(self.texts[index], "Hide") end
	for index = used.headings + 1, #self.headings do call(self.headings[index], "Hide") end
	return #sections > 0 and y or top
end
