local Everlook = Everlook

-- Compact resting-pill content and structured notice runs. notify copies
-- these before the island paints them.
local capsule = {}
Everlook.island_capsule = capsule

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local MARKS = {
	generic = { texture = QUESTION },
	money = { texture = "Interface\\Icons\\inv_misc_coin_01" },
	bags = { texture = "Interface\\Icons\\Inv_misc_bag_08" },
	repair = { atlas = "SpellIcon-256x256-RepairAll" },
	level = { atlas = "questlog-questtypeicon-quest" },
	quest = { atlas = "questlog-questtypeicon-quest" },
	flight = { atlas = "Taxi_Frame_Gray" },
	mail = { texture = "Interface\\Icons\\INV_Letter_15" },
	hearth = { texture = "Interface\\Icons\\INV_Misc_Rune_01" },
	reputation = { texture = "Interface\\Icons\\Achievement_Reputation_01" },
	profession = { texture = "Interface\\Icons\\Trade_BlackSmithing" },
	loot = { texture = "Interface\\Icons\\INV_Misc_Bag_10" },
	clock = { texture = "Interface\\Icons\\INV_Misc_PocketWatch_01" },
	experience = { texture = "Interface\\Icons\\XP_Icon" },
	rested = { texture = "Interface\\Icons\\Spell_Nature_Sleep" },
	buff = { texture = "Interface\\Icons\\Spell_Holy_WordFortitude" },
	invite = { texture = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend" },
}
local TONES = {
	primary = "fff5f7fa",
	secondary = "ffaeb6c3",
	accent = "ffad76ef",
	success = "ff80e6a6",
	warning = "ffff9e40",
	error = "ffff8080",
	gold = "ffffd24a",
	muted = "ff8891a0",
}
local MAX_LABELS = 3
local CAPSULE_KEYS = { text = true, icon = true, trailing = true, progress = true, arrow = true, ring = true, labels = true, badge = true, min_width = true }
local MARK_KEYS = { atlas = true, item_id = true, spell_id = true }
local RUN_KEYS = { text = true, tone = true, icon = true, atlas = true, item_id = true, spell_id = true, money = true }
local PAD, GAP, MARK = 8, 4, 16

local function secret(value)
	return issecretvalue and issecretvalue(value)
end

local function plain_table(value)
	return type(value) == "table" and getmetatable(value) == nil
end

local function any_secret(value)
	if secret(value) then return true end
	if not plain_table(value) then return false end
	for key, item in pairs(value) do
		if secret(key) or any_secret(item) then return true end
	end
	return false
end

local function known_keys(value, allowed)
	for key in pairs(value) do
		if not allowed[key] then return false end
	end
	return true
end

local function plain_line(value, maximum)
	return type(value) == "string" and #value >= 1 and #value <= maximum
		and value:find("%S") ~= nil and value:find("|", 1, true) == nil and value:find("\n", 1, true) == nil
end

local function whole(value)
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge and value % 1 == 0
end

local function positive_id(value)
	return whole(value) and value >= 1 and value <= 9007199254740991
end

local function money_value(value)
	return whole(value) and math.abs(value) <= 9007199254740991
end

local function copy_mark(value)
	if type(value) == "string" then
		if not plain_line(value, 64) then return nil end
		return value
	end
	if not plain_table(value) or not known_keys(value, MARK_KEYS) then return nil end
	local fields = (value.atlas ~= nil and 1 or 0) + (value.item_id ~= nil and 1 or 0) + (value.spell_id ~= nil and 1 or 0)
	if fields ~= 1 then return nil end
	if value.atlas ~= nil then
		if type(value.atlas) ~= "string" or #value.atlas < 1 or #value.atlas > 64 or value.atlas:find("^[%w_%-]+$") == nil then
			return nil, "invalid_atlas"
		end
		return { atlas = value.atlas }
	end
	if value.item_id ~= nil then
		if not positive_id(value.item_id) then return nil end
		return { item_id = value.item_id }
	end
	if not positive_id(value.spell_id) then return nil end
	return { spell_id = value.spell_id }
end

local function read_capsule(value, presentation)
	if value == nil then return nil end
	if secret(value) or presentation ~= "status" or not plain_table(value) or not known_keys(value, CAPSULE_KEYS) then
		return nil, "invalid_capsule"
	end
	if any_secret(value) then return nil, "invalid_capsule" end
	-- The title is optional now that a capsule can be an arrow and a distance, but a capsule has to have something to show.
	if value.text ~= nil and not plain_line(value.text, 64) then return nil, "invalid_capsule" end
	local icon, icon_reason
	if value.icon ~= nil then
		icon, icon_reason = copy_mark(value.icon)
		if icon_reason then return nil, icon_reason end
		if not icon then return nil, "invalid_capsule" end
	end
	local trailing, trailing_reason
	if value.trailing ~= nil then
		if type(value.trailing) == "string" then
			if not plain_line(value.trailing, 16) then return nil, "invalid_capsule" end
			trailing = value.trailing
		else
			trailing, trailing_reason = copy_mark(value.trailing)
			if trailing_reason then return nil, trailing_reason end
			if not trailing then return nil, "invalid_capsule" end
		end
	end
	if value.progress ~= nil and (secret(value.progress) or type(value.progress) ~= "number"
		or value.progress ~= value.progress or value.progress < 0 or value.progress > 1
		or value.progress == math.huge or value.progress == -math.huge) then
		return nil, "invalid_capsule"
	end
	local capsule_spec = { text = value.text, icon = icon, trailing = trailing, progress = value.progress }
	-- The parts a row has are read by the row's own reader, with tones kept as names.
	local shared = { arrow = value.arrow, ring = value.ring, labels = value.labels, badge = value.badge }
	if next(shared) ~= nil then
		local row, reason = capsule.read_row(shared, true)
		if not row then return nil, reason == "invalid_row" and "invalid_capsule" or reason end
		capsule_spec.arrow, capsule_spec.ring, capsule_spec.labels, capsule_spec.badge = row.arrow, row.ring, row.labels, row.badge
	end
	-- A trailing string or mark counts as one of the three labels.
	if (trailing ~= nil and 1 or 0) + #(capsule_spec.labels or {}) > MAX_LABELS then return nil, "invalid_capsule" end
	local width = value.min_width
	if width ~= nil then
		if secret(width) or type(width) ~= "number" or width ~= width or width % 1 ~= 0 or width < 64 or width > 360 then return nil, "invalid_capsule" end
		capsule_spec.min_width = width
	end
	if capsule_spec.text == nil and icon == nil and trailing == nil and capsule_spec.arrow == nil and capsule_spec.ring == nil
		and capsule_spec.labels == nil and capsule_spec.badge == nil and value.progress == nil then
		return nil, "invalid_capsule"
	end
	return capsule_spec
end

-- A copy of a capsule as the island keeps it, so a producer that changes its own table changes nothing here.
function capsule.copy(spec)
	if type(spec) ~= "table" then return nil end
	local copy = {}
	for name, value in pairs(spec) do copy[name] = value end
	if spec.ring then copy.ring = { fraction = spec.ring.fraction, tone = spec.ring.tone } end
	if spec.labels then
		copy.labels = {}
		for index, label in ipairs(spec.labels) do
			copy.labels[index] = type(label) == "table" and { text = label.text, tone = label.tone } or label
		end
	end
	return copy
end

-- A mark read from a producer: a name, an atlas, an item or a spell. Returns it copied, or nil and a reason.
capsule.read_mark = copy_mark

-- A tone is a name from TONES. Callers that paint get it as a colour table.
function capsule.tone_color(name)
	local hex = TONES[name]
	if not hex then return nil end
	return { tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255, 1 }
end

local ROW_KEYS = { icon = true, arrow = true, title = true, ring = true, labels = true, badge = true }
local RING_KEYS = { fraction = true, tone = true }
local LABEL_KEYS = { text = true, tone = true }

-- A tone as a colour table, or as its name when `names` is set (a notice keeps names, so an update can read it again).
local function read_tone(value, default, names)
	local name = value == nil and default or value
	if type(name) ~= "string" or not TONES[name] then return nil end
	return names and name or capsule.tone_color(name)
end

-- Reads one row: the same parts the capsule has, each optional but at least one,
-- as { icon, title, ring = { fraction, tone }, labels = { text or { text, tone } }, badge }.
-- Returns a copy with tones turned into colour tables, or nil and a reason.
function capsule.read_row(value, names)
	if secret(value) or not plain_table(value) or not known_keys(value, ROW_KEYS) or any_secret(value) then return nil, "invalid_row" end
	local row = {}
	if value.icon ~= nil then
		local icon, reason = copy_mark(value.icon)
		if reason then return nil, reason end
		if not icon then return nil, "invalid_row" end
		row.icon = icon
	end
	-- An arrow turns to an angle in radians. A function gives the angle each time it is asked, for a
	-- direction that changes as you move; the island asks it only while the row shows.
	if value.arrow ~= nil then
		local arrow = value.arrow
		if type(arrow) == "number" then
			if arrow ~= arrow or arrow == math.huge or arrow == -math.huge then return nil, "invalid_row" end
		elseif type(arrow) ~= "function" then
			return nil, "invalid_row"
		end
		row.arrow = arrow
	end
	if value.title ~= nil then
		if not plain_line(value.title, 64) then return nil, "invalid_row" end
		row.title = value.title
	end
	if value.ring ~= nil then
		local ring = value.ring
		if not plain_table(ring) or not known_keys(ring, RING_KEYS) then return nil, "invalid_row" end
		local fraction = ring.fraction
		if type(fraction) ~= "number" or fraction ~= fraction or fraction < 0 or fraction > 1 then return nil, "invalid_row" end
		local tone = read_tone(ring.tone, "accent", names)
		if not tone then return nil, "invalid_row" end
		row.ring = { fraction = fraction, tone = tone }
	end
	if value.labels ~= nil then
		local labels = value.labels
		if not plain_table(labels) or #labels > MAX_LABELS then return nil, "invalid_row" end
		for key in pairs(labels) do
			if type(key) ~= "number" or key < 1 or key > #labels or key % 1 ~= 0 then return nil, "invalid_row" end
		end
		row.labels = {}
		for index = 1, #labels do
			local label = labels[index]
			if type(label) == "string" then
				if not plain_line(label, 24) then return nil, "invalid_row" end
				row.labels[index] = label
			else
				if not plain_table(label) or not known_keys(label, LABEL_KEYS) or not plain_line(label.text, 24) then return nil, "invalid_row" end
				local tone = read_tone(label.tone, "secondary", names)
				if not tone then return nil, "invalid_row" end
				row.labels[index] = { text = label.text, tone = tone }
			end
		end
	end
	if value.badge ~= nil then
		if not plain_line(value.badge, 16) then return nil, "invalid_row" end
		row.badge = value.badge
	end
	if row.title == nil and row.labels == nil and row.badge == nil and row.icon == nil and row.ring == nil and row.arrow == nil then return nil, "invalid_row" end
	return row
end

local function read_run(value)
	if secret(value) or not plain_table(value) or not known_keys(value, RUN_KEYS) then return nil, "invalid_run" end
	if any_secret(value) then return nil, "invalid_run" end
	local kind, count = nil, 0
	for _, name in ipairs({ "text", "icon", "atlas", "item_id", "spell_id", "money" }) do
		if value[name] ~= nil then kind, count = name, count + 1 end
	end
	if count ~= 1 then return nil, "invalid_run" end
	if kind == "text" then
		if not plain_line(value.text, 128) then return nil, "invalid_run" end
		local tone = value.tone or "primary"
		if (value.tone ~= nil and type(value.tone) ~= "string") or not TONES[tone] then return nil, "invalid_run" end
		return { text = value.text, tone = tone }
	end
	if value.tone ~= nil then return nil, "invalid_run" end
	if kind == "money" then
		if not money_value(value.money) then return nil, "invalid_run" end
		return { money = value.money }
	end
	if kind == "icon" then
		local icon = copy_mark(value.icon)
		if type(icon) ~= "string" then return nil, "invalid_run" end
		return { icon = icon }
	end
	local mark, reason = copy_mark({ [kind] = value[kind] })
	if reason then return nil, reason end
	if not mark then return nil, "invalid_run" end
	return mark
end

local function read_runs(value)
	if value == nil then return nil end
	if secret(value) or not plain_table(value) then return nil, "invalid_runs" end
	local count = #value
	if count < 1 or count > 6 then return nil, "invalid_runs" end
	for key in pairs(value) do
		if type(key) ~= "number" or key < 1 or key > count or key % 1 ~= 0 then return nil, "invalid_runs" end
	end
	local runs = {}
	for index = 1, count do
		local run, reason = read_run(value[index])
		if not run then return nil, reason end
		runs[index] = run
	end
	return runs
end

function capsule.read(payload, presentation)
	if type(payload) ~= "table" then return nil, nil, "invalid_capsule" end
	local compact, compact_reason = read_capsule(payload.capsule, presentation)
	if compact_reason then return nil, nil, compact_reason end
	local runs, runs_reason = read_runs(payload.runs)
	if runs_reason then return nil, nil, runs_reason end
	return compact, runs
end

local function resolved_icon(name)
	return MARKS[name] or MARKS.generic
end

local function call(object, method, ...)
	local fn = object and object[method]
	if type(fn) == "function" then return fn(object, ...) end
end

function capsule.resolve(mark)
	if type(mark) == "string" then return resolved_icon(mark) end
	if type(mark) ~= "table" then return MARKS.generic end
	if mark.atlas then return { atlas = mark.atlas } end
	if mark.item_id and C_Item and C_Item.GetItemIconByID then
		local image = C_Item.GetItemIconByID(mark.item_id)
		if image and not secret(image) and (type(image) == "number" or type(image) == "string") then return { texture = image } end
	end
	if mark.spell_id and C_Spell and C_Spell.GetSpellTexture then
		local image = C_Spell.GetSpellTexture(mark.spell_id)
		if image and not secret(image) and (type(image) == "number" or type(image) == "string") then return { texture = image } end
	end
	return MARKS.generic
end

function capsule.apply(texture, mark)
	local resolved = capsule.resolve(mark)
	if resolved.atlas then
		call(texture, "SetAtlas", resolved.atlas)
	else
		call(texture, "SetTexture", resolved.texture or QUESTION)
	end
end

local function escape_mark(mark)
	local resolved = capsule.resolve(mark)
	if resolved.atlas then return "|A:" .. resolved.atlas .. ":16:16|a" end
	return "|T" .. tostring(resolved.texture or QUESTION) .. ":16|t"
end

-- The runs of a text, read: each one text in a tone. Money and marks are not allowed in a section's text.
function capsule.read_text_runs(value)
	local runs, reason = read_runs(value)
	if not runs then return nil, reason end
	for _, run in ipairs(runs) do
		if not run.text then return nil, "invalid_runs" end
	end
	return runs
end

-- joiner goes between the runs: a space for a notice's runs, nothing for a text that is one line in tones.
function capsule.compile(runs, money, joiner)
	if type(runs) ~= "table" then return nil end
	local parts = {}
	for index = 1, #runs do
		local run = runs[index]
		if run.text then
			parts[#parts + 1] = "|c" .. (TONES[run.tone] or TONES.primary) .. run.text .. "|r"
		elseif run.money ~= nil and type(money) == "function" then
			parts[#parts + 1] = money(run.money)
		elseif run.icon or run.atlas or run.item_id or run.spell_id then
			parts[#parts + 1] = escape_mark(run.icon or run)
		end
	end
	if #parts == 0 then return nil end
	return table.concat(parts, joiner or " ")
end

local function mark_key(mark)
	if type(mark) == "string" then return "i:" .. mark end
	if type(mark) ~= "table" then return "" end
	if mark.atlas then return "a:" .. mark.atlas end
	if mark.item_id then return "n:" .. mark.item_id end
	if mark.spell_id then return "s:" .. mark.spell_id end
	return ""
end

-- What a capsule's shape depends on: which parts it has, not what they say. A tick of the distance or a
-- turn of an arrow does not change it, so it does not crossfade; a new mark or a new part does.
function capsule.signature(spec)
	if type(spec) ~= "table" then return nil end
	local trailing = spec.trailing
	local trailing_key = type(trailing) == "string" and "t" or mark_key(trailing)
	local labels = type(spec.labels) == "table" and #spec.labels or 0
	return table.concat({ mark_key(spec.icon), trailing_key, tostring(spec.arrow ~= nil), tostring(spec.ring ~= nil), labels,
		tostring(spec.badge ~= nil), tostring(spec.progress ~= nil), tostring(spec.text ~= nil) }, "|")
end

-- A capsule spec as the parts of a row. The older fields map one to one: `text` is the title, a
-- `trailing` string or mark is a label, and `progress` is a percent in the purple of experience, shown as
-- the badge when the spec has no trailing, labels or badge of its own.
function capsule.row_spec(spec)
	local labels = {}
	for index, label in ipairs(spec.labels or {}) do
		-- A tone is kept as a name and turned into a colour here, where it is drawn.
		labels[index] = type(label) == "table" and { text = label.text, tone = capsule.tone_color(label.tone or "secondary") } or label
	end
	local ring = spec.ring and { fraction = spec.ring.fraction, tone = capsule.tone_color(spec.ring.tone or "accent") } or nil
	local trailing = spec.trailing
	if type(trailing) == "string" then
		labels[#labels + 1] = trailing
	elseif trailing ~= nil then
		labels[#labels + 1] = escape_mark(trailing)
	end
	local badge = spec.badge
	if badge == nil and trailing == nil and #labels == 0 and type(spec.progress) == "number" then
		badge = math.floor(math.max(0, math.min(1, spec.progress)) * 100 + 0.5) .. "%"
	end
	return { icon = spec.icon, arrow = spec.arrow, title = spec.text, ring = ring, labels = labels, badge = badge }
end

-- The widest a capsule goes unless it asks for more with min_width, and the narrowest.
local WIDEST, NARROWEST, HEIGHT = 280, 64, 36

-- Lays a capsule out: the parts of its row and the width they ask for. `measure(text, role)` gives the width
-- of text in a font role, `ceiling` is the room there is, and `reserve` is room kept at the right edge.
function capsule.layout(spec, measure, ceiling, reserve)
	if type(spec) ~= "table" then return nil end
	-- A capsule that asks for a width holds it, so it does not resize as its words change, and it may be wider than the usual limit.
	local limit = spec.min_width and math.huge or WIDEST
	if type(ceiling) == "number" and ceiling == ceiling and ceiling > 0 then limit = math.min(limit, ceiling) end
	local function measured(text, role)
		local width = type(measure) == "function" and measure(text, role) or nil
		if type(width) == "number" and width == width and width >= 0 and width < math.huge then return width end
		return #text * 8
	end
	local row = capsule.row_spec(spec)
	local width = Everlook.island_row.natural_width(row, measured, 14, reserve)
	if type(spec.min_width) == "number" then width = math.max(width, spec.min_width + (reserve or 0)) end
	width = math.max(NARROWEST, math.min(math.max(NARROWEST, limit), width))
	-- An even width keeps the capsule's centre, and so everything in it, on whole pixels.
	width = math.ceil(width / 2) * 2
	return { width = width, height = HEIGHT, row = row, reserve = reserve or 0 }
end
