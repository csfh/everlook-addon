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

-- A table's value columns are this wide, with the island's `near` gap between them.
local COLUMN_WIDTH = 84

local BAR_ART = "Interface\\AddOns\\Everlook_Island\\assets\\island_white.tga"

-- options: title_role (the font of a row's title, "text" unless told), row_height (a row's height,
-- the control height unless told) and across (how many cells share a row, two unless told). A pane
-- takes the defaults; the header and the metrics under it set their own.
function blocks.new(parent, host, options)
	return setmetatable({ parent = parent, host = host, options = options or {}, rows = {}, texts = {}, headings = {}, meters = {}, cells = {}, tables = {} }, View)
end

-- The title of the first row drawn, for the one thing that has to know where it sits.
function View:first_title()
	return self.rows[1] and self.rows[1].row.title or nil
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

local function table_slot(self, index)
	local slot = self.tables[index]
	if slot then return slot end
	local host = self.host
	slot = { heads = {}, names = {}, values = {} }
	slot.title = host.label(self.parent, "LEFT", "heading")
	call(slot.title, "SetWordWrap", false)
	slot.footer = host.label(self.parent, "LEFT", "caption")
	-- The action is a small button after the title, like the one on a row.
	slot.button = host.link(self.parent, nil, "Action", function()
		if slot.action then run(slot.action, slot.handle) end
	end)
	self.tables[index] = slot
	return slot
end

local function table_label(slot, list, index, host, parent, role)
	local label = list[index]
	if not label then
		label = host.label(parent, "RIGHT", role)
		call(label, "SetWordWrap", false)
		list[index] = label
	end
	return label
end

-- A cell is a mark in a ring, and a small name over its value. It is the same part
-- the open island's metrics use, so a figure from a section looks like one of ours.
local function cell_slot(self, index)
	local slot = self.cells[index]
	if slot then return slot end
	local host, space = self.host, self.host.space
	-- A cell is part of the background: it shows a tooltip, and a click on it does what a click beside it does.
	slot = { frame = CreateFrame("Button", nil, self.parent), node = {} }
	call(slot.frame, "RegisterForClicks", "LeftButtonUp")
	host.hover(slot.frame, slot.node)
	if host.click then call(slot.frame, "SetScript", "OnClick", host.click) end
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

-- Turns every arrow that asks for its angle. Cheap: it moves no frame and lays nothing out.
function View:tick()
	for index = 1, self.used_rows or 0 do self.rows[index].row:tick() end
end

local function row_slot(self, index)
	local slot = self.rows[index]
	if slot then return slot end
	local host = self.host
	local frame = CreateFrame("Button", nil, self.parent)
	call(frame, "RegisterForClicks", "LeftButtonUp")
	local visual = host.visual(frame, true)
	slot = { frame = frame, node = { tooltip = nil } }
	-- A row that does something, or says something on hover, lights under the pointer.
	local wash = call(visual, "CreateTexture", nil, "BACKGROUND")
	call(wash, "SetAllPoints", visual)
	call(wash, "SetColorTexture", 1, 1, 1, 0.06)
	call(wash, "Hide")
	slot.node.on_hover = function(inside) call(wash, (inside and slot.interactive) and "Show" or "Hide") end
	slot.row = island_row.new(visual, { label = host.label, rings = host.rings, ring_size = host.ring_size, title_role = self.options.title_role or "text" })
	slot.link = host.link(frame, nil, "Action", function()
		if slot.action then run(slot.action, slot.handle) end
	end)
	call(slot.link, "SetPoint", "RIGHT", frame, "RIGHT", -host.space.edge, 0)
	host.hover(frame, slot.node)
	-- Like a cell, a row does what a click beside it does. Without this the row takes the click and drops it.
	if host.click then call(frame, "SetScript", "OnClick", host.click) end
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
	local used = { rows = 0, texts = 0, headings = 0, meters = 0, cells = 0, tables = 0 }
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
			y = y + space.near
		end
		local previous
		for _, block in ipairs(record.blocks) do
			local kind = block.kind
			if previous and previous ~= "gap" and kind ~= "gap" then
				-- A row after a row is a list, and a text after a row is that row's detail: both sit close.
				y = y + ((previous == "row" and (kind == "row" or kind == "text")) and space.within or space.near)
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
				local across = self.options.across or 2
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
					call(slot.value, "SetText", type(cell.value) == "table" and host.money(cell.value.money) or cell.value)
					local tone = cell.tone or host.primary
					call(slot.value, "SetTextColor", tone[1], tone[2], tone[3], tone[4] or 1)
					slot.node.tooltip = cell.tooltip
					call(slot.value, "ClearAllPoints")
					call(slot.value, "SetPoint", "TOPLEFT", slot.frame, "TOPLEFT", lead, -(text_top + label_height + space.within))
					call(slot.value, "SetWidth", math.max(1, column_width - lead))
					call(slot.frame, "Show")
				end
				y = row_top + row_height
			elseif kind == "table" then
				used.tables = used.tables + 1
				local slot = table_slot(self, used.tables)
				slot.action, slot.handle = block.action, record.handle
				local columns = #block.columns
				local names_width = math.max(40, inner - columns * COLUMN_WIDTH - columns * space.near)
				local line = call(slot.title, "GetLineHeight") or 12
				-- The heading line names the table and the columns. With an action it is as tall as the
				-- button, and the title and the column heads sit on its middle.
				local heading_height = block.action and math.max(line, space.link) or line
				local text_top = y + (heading_height - line) / 2
				host.heading(slot.title, block.title)
				call(slot.title, "ClearAllPoints")
				call(slot.title, "SetPoint", "TOPLEFT", self.parent, "TOPLEFT", inset, -text_top)
				call(slot.title, "SetWidth", math.ceil(call(slot.title, "GetStringWidth") or names_width))
				call(slot.title, "Show")
				if block.action then
					host.set_link_text(slot.button, block.action.label)
					call(slot.button, "ClearAllPoints")
					call(slot.button, "SetPoint", "LEFT", slot.title, "RIGHT", space.near, 0)
					call(slot.button, "Show")
				else
					call(slot.button, "Hide")
				end
				local function column_left(position)
					return inset + names_width + space.near + (position - 1) * (COLUMN_WIDTH + space.near)
				end
				for position = 1, columns do
					local head = table_label(slot, slot.heads, position, host, self.parent, "heading")
					host.heading(head, block.columns[position])
					call(head, "ClearAllPoints")
					call(head, "SetPoint", "TOPLEFT", self.parent, "TOPLEFT", column_left(position), -text_top)
					call(head, "SetWidth", COLUMN_WIDTH)
					call(head, "Show")
				end
				local row_y = y + heading_height + space.near
				for row_index, cells in ipairs(block.rows) do
					local name = table_label(slot, slot.names, row_index, host, self.parent, "text")
					call(name, "SetJustifyH", "LEFT")
					call(name, "SetText", cells[1])
					call(name, "ClearAllPoints")
					call(name, "SetPoint", "TOPLEFT", self.parent, "TOPLEFT", inset, -row_y)
					call(name, "SetWidth", names_width)
					call(name, "Show")
					slot.values[row_index] = slot.values[row_index] or {}
					for position = 1, columns do
						local value = table_label(slot, slot.values[row_index], position, host, self.parent, "text")
						call(value, "SetText", cells[position + 1])
						call(value, "SetTextColor", unpack(host.primary))
						call(value, "ClearAllPoints")
						call(value, "SetPoint", "TOPLEFT", self.parent, "TOPLEFT", column_left(position), -row_y)
						call(value, "SetWidth", COLUMN_WIDTH)
						call(value, "Show")
					end
					for position = columns + 1, #slot.values[row_index] do call(slot.values[row_index][position], "Hide") end
					row_y = row_y + (call(name, "GetLineHeight") or 14) + space.within
				end
				for position = columns + 1, #slot.heads do call(slot.heads[position], "Hide") end
				for row_index = #block.rows + 1, #slot.names do
					call(slot.names[row_index], "Hide")
					for _, value in ipairs(slot.values[row_index] or {}) do call(value, "Hide") end
				end
				if block.footer then
					call(slot.footer, "SetText", block.footer)
					call(slot.footer, "ClearAllPoints")
					call(slot.footer, "SetPoint", "TOPLEFT", self.parent, "TOPLEFT", inset, -row_y)
					call(slot.footer, "SetWidth", inner)
					call(slot.footer, "Show")
					row_y = row_y + (call(slot.footer, "GetStringHeight") or 12)
				else
					call(slot.footer, "Hide")
				end
				y = row_y
			elseif kind == "text" then
				used.texts = used.texts + 1
				local label = label_slot(self, self.texts, used.texts, "text")
				call(label, "SetWidth", inner)
				call(label, "SetText", block.runs and Everlook.island_capsule.compile(block.runs, nil, "") or block.text)
				place(label, call(label, "GetStringHeight") or 14)
				call(label, "Show")
			else
				used.rows = used.rows + 1
				local slot = row_slot(self, used.rows)
				slot.handle, slot.action = record.handle, block.action
				slot.node.tooltip = tooltip_text(block.tooltip)
				slot.interactive = block.action ~= nil or slot.node.tooltip ~= nil
				if host.role then host.role(slot.row.title, block.role or self.options.title_role or "text") end
				-- A row carries its own insets, the same the capsule has, so its frame is the whole pane.
				-- A line of a list is `row` high, and `link` high when it carries a button.
				local row_height = self.options.row_height or (block.action and space.link or space.row)
				call(slot.frame, "SetSize", width, row_height)
				call(slot.frame, "ClearAllPoints")
				call(slot.frame, "SetPoint", "TOPLEFT", self.parent, "TOPLEFT", 0, -y)
				local reserve = 0
				if block.action then
					host.set_link_text(slot.link, block.action.label)
					reserve = (call(slot.link, "GetWidth") or 48) + space.near
				end
				call(slot.link, block.action and "Show" or "Hide")
				call(slot.frame, "Show")
				slot.row:set({ icon = block.row.icon, arrow = block.row.arrow, title = block.row.title, ring = block.row.ring, labels = block.row.labels, badge = block.row.badge }, reserve)
				y = y + row_height
			end
			previous = kind
		end
	end
	self.used_rows = used.rows
	for index = used.rows + 1, #self.rows do call(self.rows[index].frame, "Hide") end
	for index = used.meters + 1, #self.meters do
		local slot = self.meters[index]
		for _, region in ipairs({ slot.label, slot.value, slot.bar }) do call(region, "Hide") end
	end
	for index = used.cells + 1, #self.cells do call(self.cells[index].frame, "Hide") end
	for index = used.tables + 1, #self.tables do
		local slot = self.tables[index]
		for _, region in ipairs({ slot.button, slot.title, slot.footer }) do call(region, "Hide") end
		for _, head in ipairs(slot.heads) do call(head, "Hide") end
		for _, name in ipairs(slot.names) do call(name, "Hide") end
		for _, values in pairs(slot.values) do for _, value in ipairs(values) do call(value, "Hide") end end
	end
	for index = used.texts + 1, #self.texts do call(self.texts[index], "Hide") end
	for index = used.headings + 1, #self.headings do call(self.headings[index], "Hide") end
	return #sections > 0 and y or top
end
