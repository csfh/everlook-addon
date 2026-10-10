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

local BAR_ART = "Interface\\AddOns\\Everlook_Island\\assets\\island_white.tga"

function blocks.new(parent, host)
	return setmetatable({ parent = parent, host = host, rows = {}, texts = {}, headings = {}, meters = {}, cells = {} }, View)
end

local function meter_slot(self, index)
	local slot = self.meters[index]
	if slot then return slot end
	local host = self.host
	slot = { label = host.label(self.parent, "LEFT", "caption"), value = host.label(self.parent, "RIGHT", "caption") }
	call(slot.value, "SetWordWrap", false)
	slot.bar = CreateFrame("StatusBar", nil, self.parent)
	call(slot.bar, "EnableMouse", false)
	call(slot.bar, "SetStatusBarTexture", BAR_ART)
	call(slot.bar, "SetMinMaxValues", 0, 1)
	local track = call(slot.bar, "CreateTexture", nil, "BACKGROUND")
	call(track, "SetAllPoints", slot.bar)
	call(track, "SetColorTexture", 1, 1, 1, 0.12)
	self.meters[index] = slot
	return slot
end

-- A cell is a mark in a ring, and a small name over its value. It is the same part
-- the open island's metrics use, so a figure from a section looks like one of ours.
local function cell_slot(self, index)
	local slot = self.cells[index]
	if slot then return slot end
	local host, space = self.host, self.host.space
	slot = { frame = CreateFrame("Frame", nil, self.parent) }
	call(slot.frame, "EnableMouse", false)
	slot.icon = call(slot.frame, "CreateTexture", nil, "OVERLAY")
	call(slot.icon, "SetSize", space.icon, space.icon)
	call(slot.icon, "SetPoint", "TOPLEFT", slot.frame, "TOPLEFT", (space.ring - space.icon) / 2, -(space.ring - space.icon) / 2)
	slot.ring = host.rings.make(slot.frame, space.ring)
	host.rings.place(slot.ring, slot.frame, 0, 0)
	slot.label = host.label(slot.frame, "LEFT", "caption")
	slot.value = host.label(slot.frame, "LEFT")
	call(slot.value, "SetWordWrap", false)
	self.cells[index] = slot
	return slot
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
	local used = { rows = 0, texts = 0, headings = 0, meters = 0, cells = 0 }
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
			elseif kind == "meter" then
				used.meters = used.meters + 1
				local slot = meter_slot(self, used.meters)
				call(slot.label, "SetText", block.label)
				call(slot.value, "SetText", block.value)
				local value_width = call(slot.value, "GetStringWidth") or 0
				local line = call(slot.label, "GetLineHeight") or 12
				for _, region in ipairs({ slot.label, slot.value }) do
					call(region, "ClearAllPoints")
				end
				call(slot.label, "SetPoint", "TOPLEFT", self.parent, "TOPLEFT", inset, -y)
				call(slot.label, "SetWidth", math.max(1, inner - value_width - space.near))
				call(slot.value, "SetPoint", "TOPRIGHT", self.parent, "TOPRIGHT", -inset, -y)
				call(slot.value, "SetWidth", math.max(1, value_width))
				call(slot.bar, "ClearAllPoints")
				call(slot.bar, "SetPoint", "TOPLEFT", self.parent, "TOPLEFT", inset, -(y + line + space.within))
				call(slot.bar, "SetSize", inner, space.within)
				call(slot.bar, "SetStatusBarColor", block.tone[1], block.tone[2], block.tone[3], 1)
				call(slot.bar, "SetValue", block.fraction)
				for _, region in ipairs({ slot.label, slot.value, slot.bar }) do call(region, "Show") end
				y = y + line + space.within + space.within
			elseif kind == "cells" then
				-- Two across, on the grid's gutter, and as many rows as it takes.
				local gutter = Everlook.island_grid.gutter
				local across = 2
				local column_width = math.floor((inner - (across - 1) * gutter) / across)
				local label_height, value_height = nil, nil
				local lead = space.ring + space.near
				local row_top = y
				local row_height = 0
				for position, cell in ipairs(block.cells) do
					used.cells = used.cells + 1
					local slot = cell_slot(self, used.cells)
					label_height = call(slot.label, "GetLineHeight") or 12
					value_height = call(slot.value, "GetLineHeight") or 14
					local text_height = math.max(label_height + space.within + value_height, space.ring)
					local column = (position - 1) % across
					if column == 0 and position > 1 then row_top = row_top + row_height + space.near end
					row_height = text_height
					call(slot.frame, "ClearAllPoints")
					call(slot.frame, "SetPoint", "TOPLEFT", self.parent, "TOPLEFT", inset + column * (column_width + gutter), -row_top)
					call(slot.frame, "SetSize", column_width, text_height)
					local box_top = math.floor((text_height - space.ring) / 2)
					host.rings.place(slot.ring, slot.frame, 0, box_top)
					if cell.ring then
						host.rings.set(slot.ring, cell.ring.fraction, cell.ring.tone)
					else
						host.rings.track(slot.ring)
					end
					call(slot.icon, "ClearAllPoints")
					call(slot.icon, "SetPoint", "TOPLEFT", slot.frame, "TOPLEFT", (space.ring - space.icon) / 2, -(box_top + (space.ring - space.icon) / 2))
					if cell.icon then
						Everlook.island_capsule.apply(slot.icon, cell.icon)
						call(slot.icon, "Show")
					else
						call(slot.icon, "Hide")
					end
					local text_top = math.floor((text_height - (label_height + space.within + value_height)) / 2)
					call(slot.label, "SetText", cell.label)
					call(slot.label, "ClearAllPoints")
					call(slot.label, "SetPoint", "TOPLEFT", slot.frame, "TOPLEFT", lead, -text_top)
					call(slot.label, "SetWidth", math.max(1, column_width - lead))
					call(slot.value, "SetText", cell.value)
					call(slot.value, "ClearAllPoints")
					call(slot.value, "SetPoint", "TOPLEFT", slot.frame, "TOPLEFT", lead, -(text_top + label_height + space.within))
					call(slot.value, "SetWidth", math.max(1, column_width - lead))
					call(slot.frame, "Show")
				end
				y = row_top + row_height
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
	for index = used.meters + 1, #self.meters do
		local slot = self.meters[index]
		for _, region in ipairs({ slot.label, slot.value, slot.bar }) do call(region, "Hide") end
	end
	for index = used.cells + 1, #self.cells do call(self.cells[index].frame, "Hide") end
	for index = used.texts + 1, #self.texts do call(self.texts[index], "Hide") end
	for index = used.headings + 1, #self.headings do call(self.headings[index], "Hide") end
	return #sections > 0 and y or top
end
