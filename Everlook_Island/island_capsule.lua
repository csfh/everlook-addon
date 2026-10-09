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
}
local CAPSULE_KEYS = { text = true, icon = true, trailing = true, progress = true }
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
	if any_secret(value) or not plain_line(value.text, 24) then return nil, "invalid_capsule" end
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
	return { text = value.text, icon = icon, trailing = trailing, progress = value.progress }
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

function capsule.compile(runs, money)
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
	return table.concat(parts, " ")
end

local function mark_key(mark)
	if type(mark) == "string" then return "i:" .. mark end
	if type(mark) ~= "table" then return "" end
	if mark.atlas then return "a:" .. mark.atlas end
	if mark.item_id then return "n:" .. mark.item_id end
	if mark.spell_id then return "s:" .. mark.spell_id end
	return ""
end

function capsule.signature(spec)
	if type(spec) ~= "table" then return nil end
	local trailing = spec.trailing
	local trailing_key = type(trailing) == "string" and ("t:" .. trailing) or mark_key(trailing)
	return mark_key(spec.icon) .. "|" .. trailing_key
end

function capsule.layout(spec, measure, ceiling)
	if type(spec) ~= "table" or type(spec.text) ~= "string" then return nil end
	-- Progress is a percent in the purple of experience, unless the spec has its own trailing mark.
	local trailing = spec.trailing
	if trailing == nil and type(spec.progress) == "number" then
		trailing = "|cffad76ef" .. math.floor(math.max(0, math.min(1, spec.progress)) * 100 + 0.5) .. "%|r"
	end
	local limit = 280
	if type(ceiling) == "number" and ceiling == ceiling and ceiling > 0 and ceiling < math.huge then
		limit = math.max(64, math.min(280, ceiling))
	end
	local function width_of(text)
		local measured = type(measure) == "function" and measure(text) or nil
		if type(measured) == "number" and measured == measured and measured >= 0 and measured < math.huge then return measured end
		return #text * 8
	end
	local leading = spec.icon and MARK or 0
	local text_width = width_of(spec.text)
	local trailing_width, show_trailing = 0, false
	if trailing ~= nil then
		show_trailing = true
		trailing_width = type(trailing) == "string" and width_of(trailing) or MARK
	end
	local function span(with_trailing)
		local pieces = (leading > 0 and 1 or 0) + 1 + (with_trailing and 1 or 0)
		local body = leading + text_width + (with_trailing and trailing_width or 0)
		return PAD * 2 + body + math.max(0, pieces - 1) * GAP
	end
	local width = span(show_trailing)
	if width > limit and show_trailing then
		show_trailing = false
		width = span(false)
	end
	if width > limit then width = limit end
	if width < 64 then width = 64 end
	local line = spec.text
	if show_trailing then
		if type(trailing) == "string" then
			line = spec.text .. "  " .. trailing
		else
			line = spec.text .. "  " .. escape_mark(trailing)
		end
	end
	local gaps = (leading > 0 and 1 or 0) + (show_trailing and 1 or 0)
	local line_width = math.max(1, width - PAD * 2 - leading - gaps * GAP)
	return { width = width, height = 36, show_trailing = show_trailing, line = line, line_width = line_width, leading = leading }
end
