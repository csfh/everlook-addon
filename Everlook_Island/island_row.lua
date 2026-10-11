local Everlook = Everlook

-- A generic one-line row for the closed pill. It knows five kinds of part and
-- nothing about what they mean: a lead (an icon, or an arrow turned to an angle),
-- a title, a ring that fills to a fraction, labels, and a badge.
--
--   [lead] [title] ..space.. [ring] [label] [label] [badge]
--
-- The lead and title hang from the left edge, the badge from the right edge, and
-- each other part from the one after it. The title is held between the lead and
-- the first trailing part, so it truncates by itself. Nothing is measured for the
-- layout, only for the width a caller asks for.
local row = {}
Everlook.island_row = row

-- Spacing, in pixels. `lead` is the lead's inset, `title` where the title starts
-- after a lead, and `edge` the inset on both ends otherwise. `gap` separates
-- labels, `ring` the ring from the part after it.
local SPACE = { lead = 9, title = 34, edge = 12, gap = 12, ring = 6 }
row.space = SPACE
row.max_labels = 3

local ARROW_ART = "Interface\\AddOns\\Everlook_Island\\assets\\island_arrow.tga"
local ARROW_TONE = { 1, 0.86, 0.35 }
local BADGE_TONE = { 0.68, 0.46, 0.94, 1 }
local LABEL_TONE = { 174 / 255, 182 / 255, 195 / 255, 1 }

local function call(object, method, ...)
	local fn = object and object[method]
	if type(fn) == "function" then return fn(object, ...) end
end

function row.make_arrow(parent)
	local texture = call(parent, "CreateTexture", nil, "OVERLAY")
	call(texture, "SetTexture", ARROW_ART)
	call(texture, "SetVertexColor", ARROW_TONE[1], ARROW_TONE[2], ARROW_TONE[3])
	call(texture, "SetSize", 16, 16)
	call(texture, "SetSnapToPixelGrid", false)
	call(texture, "SetTexelSnappingBias", 0)
	call(texture, "Hide")
	return texture
end

-- Turns an arrow to an angle in radians and shows it, or hides it for nil.
function row.show_arrow(texture, angle)
	if angle then
		call(texture, "SetRotation", angle)
		call(texture, "Show")
	else
		call(texture, "Hide")
	end
end

-- A label set exactly as wide as its text, in whole pixels. The parts chained from it then land on
-- whole pixels too, and a ring or a texture beside it stays sharp instead of straddling two.
local function whole_width(label)
	call(label, "SetWordWrap", false)
	call(label, "SetWidth", math.ceil(call(label, "GetStringWidth") or 0))
end

-- The width a row asks for, worked out from the width of its words and with no frames: where its title
-- starts, the title, a group gap, then the ring, labels and badge each a gap apart, and the right inset.
-- `measure(text, role)` gives a width, and `ring_size` the ring's, `reserve` the room kept at the right.
function row.natural_width(spec, measure, ring_size, reserve)
	local width = (spec.icon ~= nil or spec.arrow ~= nil) and SPACE.title or SPACE.edge
	if spec.title then width = width + measure(spec.title, "title") end
	local trailing, previous = 0, nil
	local function add(size, gap)
		trailing = trailing + (previous and gap or 0) + size
		previous = true
	end
	if spec.ring then add(ring_size, 0) end
	local after_ring = spec.ring ~= nil
	for _, label in ipairs(spec.labels or {}) do
		local text = type(label) == "table" and label.text or label
		add(math.ceil(measure(text, "body")), after_ring and SPACE.ring or SPACE.gap)
		after_ring = false
	end
	if spec.badge then add(math.ceil(measure(spec.badge, "body")), after_ring and SPACE.ring or SPACE.gap) end
	if trailing > 0 then width = width + (spec.title and SPACE.gap or 0) + trailing end
	return width + SPACE.edge + (reserve or 0)
end

local Row = {}
Row.__index = Row

-- host brings the island's own pieces: label(parent, justify, role), the rings
-- table (make, chain, set, hide), ring_size and, optionally, the font role of the
-- title (the capsule's is the large one; a list row's is the text size).
function row.new(parent, host)
	local self = setmetatable({ parent = parent, host = host, labels = {}, label_count = 0 }, Row)
	self.icon = call(parent, "CreateTexture", nil, "OVERLAY")
	call(self.icon, "SetSize", 16, 16)
	call(self.icon, "SetPoint", "LEFT", parent, "LEFT", SPACE.lead, 0)
	call(self.icon, "Hide")
	self.arrow = row.make_arrow(parent)
	call(self.arrow, "SetPoint", "LEFT", parent, "LEFT", SPACE.lead, 0)
	self.title = host.label(parent, "LEFT", host.title_role)
	call(self.title, "SetMaxLines", 1)
	call(self.title, "Hide")
	self.badge = host.label(parent, "RIGHT", true)
	call(self.badge, "SetTextColor", BADGE_TONE[1], BADGE_TONE[2], BADGE_TONE[3], BADGE_TONE[4])
	call(self.badge, "Hide")
	self.ring = host.rings.make(parent, host.ring_size)
	return self
end

local function label_at(self, index)
	local label = self.labels[index]
	if not label then
		label = self.host.label(self.parent, "RIGHT", true)
		self.labels[index] = label
	end
	return label
end

-- A label is a string, or { text, tone } with tone a colour table.
local function text_of(item)
	if type(item) == "table" then return item.text or item[1], item.tone or item[2] end
	return item
end

function Row:width_of(region)
	return call(region, "GetStringWidth") or 0
end

-- The room the labels and badge take together, gaps included.
function Row:trailing_width()
	local total, parts = 0, 0
	for index = 1, self.label_count do
		total, parts = total + self:width_of(self.labels[index]), parts + 1
	end
	if self.has_badge then total, parts = total + self:width_of(self.badge), parts + 1 end
	return total + math.max(0, parts - 1) * SPACE.gap
end

-- The width of one label, or of the badge for "badge".
function Row:part_width(which)
	if which == "badge" then return self.has_badge and self:width_of(self.badge) or 0 end
	return self.labels[which] and self:width_of(self.labels[which]) or 0
end

-- Turns the arrow, and shows the icon in its place when there is none. This is
-- cheap, so it can run every tick.
function Row:aim(angle)
	self.angle = angle
	row.show_arrow(self.arrow, angle)
	call(self.icon, (self.has_icon and angle == nil) and "Show" or "Hide")
end

-- Puts every part from a spec and lays the row out. A part the spec leaves out is
-- hidden. spec = { icon = mark, arrow = angle, title = text, ring = { fraction, tone },
-- labels = { label, ... }, badge = text }. reserve is room kept free at the right edge.
function Row:set(spec, reserve)
	spec = spec or {}
	reserve = reserve or 0
	self.has_icon = spec.icon ~= nil
	if self.has_icon then Everlook.island_capsule.apply(self.icon, spec.icon) end
	self:aim(spec.arrow)
	self.has_lead = self.has_icon or spec.arrow ~= nil

	local title = spec.title
	call(self.title, "SetText", title or "")
	call(self.title, title and "Show" or "Hide")

	local labels = spec.labels or {}
	self.label_count = math.min(#labels, row.max_labels)
	for index = 1, row.max_labels do
		local label = self.labels[index]
		if index <= self.label_count then
			local text, tone = text_of(labels[index])
			label = label_at(self, index)
			call(label, "SetText", text or "")
			whole_width(label)
			-- Labels are reused, so a label without a tone goes back to the plain one.
			tone = tone or LABEL_TONE
			call(label, "SetTextColor", tone[1], tone[2], tone[3], tone[4] or 1)
			call(label, "Show")
		elseif label then
			call(label, "Hide")
		end
	end

	self.has_badge = type(spec.badge) == "string" and spec.badge ~= ""
	call(self.badge, "SetText", self.has_badge and spec.badge or "")
	whole_width(self.badge)
	call(self.badge, self.has_badge and "Show" or "Hide")

	local ring = spec.ring
	self.has_ring = type(ring) == "table"
	if self.has_ring then
		self.host.rings.set(self.ring, ring.fraction or ring[1] or 0, ring.tone or ring[2])
	else
		self.host.rings.hide(self.ring)
	end
	self:layout(reserve)
end

-- Anchors the parts to one another. A part that is hidden is skipped, so no part
-- needs to know what its neighbours are.
function Row:layout(reserve)
	local parent, rings = self.parent, self.host.rings
	local right = SPACE.edge + (reserve or 0)
	local previous
	local function hang(region)
		call(region, "ClearAllPoints")
		if previous then
			call(region, "SetPoint", "RIGHT", previous, "LEFT", -SPACE.gap, 0)
		else
			call(region, "SetPoint", "RIGHT", parent, "RIGHT", -right, 0)
		end
		previous = region
	end
	if self.has_badge then hang(self.badge) end
	for index = self.label_count, 1, -1 do hang(self.labels[index]) end
	local stop = previous
	if self.has_ring then
		if previous then rings.chain(self.ring, previous, SPACE.ring) else rings.chain(self.ring, parent, right, "RIGHT") end
		stop = self.ring.track
	end
	call(self.title, "ClearAllPoints")
	call(self.title, "SetPoint", "LEFT", parent, "LEFT", self.has_lead and SPACE.title or SPACE.edge, 0)
	if stop then
		call(self.title, "SetPoint", "RIGHT", stop, "LEFT", -SPACE.gap, 0)
	else
		call(self.title, "SetPoint", "RIGHT", parent, "RIGHT", -right, 0)
	end
end
