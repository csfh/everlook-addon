local Everlook = Everlook

-- Reads one notification payload from a producer into a clean record, or says
-- why it cannot. smart_island.lua decides what to do with the record.
local notice = {}
Everlook.island_notice = notice

local capsule = Everlook.island_capsule
local actions = Everlook.island_actions

local ICONS = { generic = true, money = true, bags = true, repair = true, level = true, quest = true, flight = true,
	mail = true, hearth = true, reputation = true, profession = true, loot = true, clock = true, invite = true, buff = true }
local SEVERITIES = { info = true, success = true, warning = true, error = true }
local PRESENTATIONS = { toast = true, status = true, inbox = true }

local function usable(value)
	if issecretvalue and issecretvalue(value) then return false end
	return value ~= nil
end

local function finite(value)
	return usable(value) and type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function plain_string(value, maximum)
	return usable(value) and type(value) == "string" and #value <= maximum and value:find("%S") ~= nil
end

notice.plain_string = plain_string

-- The mark a notice shows when its producer names none: its kind, else generic.
function notice.icon_for(icon, kind)
	return icon and (ICONS[icon] and icon or "generic") or (ICONS[kind] and kind or kind == "durability" and "repair" or "generic")
end

function notice.read(payload, default_duration)
	local text, source, kind, key, duration = payload.text, payload.source, payload.kind, payload.key, payload.duration
	if not usable(source) then
		if issecretvalue and issecretvalue(source) then return nil, "invalid_source" end
		source = "everlook"
	end
	if not usable(kind) then
		if issecretvalue and issecretvalue(kind) then return nil, "invalid_kind" end
		kind = "info"
	end
	if not usable(duration) then
		if issecretvalue and issecretvalue(duration) then return nil, "invalid_duration" end
		duration = default_duration
	end
	if not plain_string(text, 512) then return nil, "invalid_text" end
	if not plain_string(source, 64) then return nil, "invalid_source" end
	if not plain_string(kind, 32) then return nil, "invalid_kind" end
	if issecretvalue and issecretvalue(key) then return nil, "invalid_key" end
	if key ~= nil and not plain_string(key, 64) then return nil, "invalid_key" end
	if type(duration) ~= "number" or duration ~= duration or duration < 1 or duration > 30 then
		return nil, "invalid_duration"
	end
	local persist, stack = payload.persist, payload.stack
	if issecretvalue and issecretvalue(persist) then return nil, "invalid_persist" end
	if persist ~= nil and type(persist) ~= "boolean" then return nil, "invalid_persist" end
	if issecretvalue and issecretvalue(stack) then return nil, "invalid_stack" end
	if stack ~= nil and not plain_string(stack, 64) then return nil, "invalid_stack" end
	local severity, detail, icon = payload.severity, payload.detail, payload.icon
	local money, progress, presentation = payload.money, payload.progress, payload.presentation
	for _, name in ipairs({ "severity", "detail", "icon", "money", "progress", "presentation" }) do
		if issecretvalue and issecretvalue(payload[name]) then return nil, "invalid_" .. name end
	end
	if severity == nil then severity = "info" end
	if presentation == nil then presentation = "toast" end
	if type(severity) ~= "string" or not SEVERITIES[severity] then return nil, "invalid_severity" end
	if type(presentation) ~= "string" or not PRESENTATIONS[presentation] then return nil, "invalid_presentation" end
	local compact, runs, compact_reason = capsule.read(payload, presentation)
	if compact_reason then return nil, compact_reason end
	if presentation == "status" and payload.source == nil then return nil, "invalid_status_source" end
	if presentation == "status" and key == nil then return nil, "invalid_status_key" end
	if detail ~= nil and not plain_string(detail, 512) then return nil, "invalid_detail" end
	if icon ~= nil and not plain_string(icon, 64) then return nil, "invalid_icon" end
	if money ~= nil and (not finite(money) or math.abs(money) > 9007199254740991 or money ~= math.floor(money)) then return nil, "invalid_money" end
	if progress ~= nil and (not finite(progress) or progress < 0 or progress > 1) then return nil, "invalid_progress" end
	local spec, spec_reason = actions.read(payload)
	if not spec then return nil, spec_reason end
	icon = notice.icon_for(icon, kind)
	return {
		text = text, source = source, kind = kind, key = key, duration = duration, persist = persist, stack = stack,
		severity = severity, detail = detail, icon = icon, money = money, progress = progress, presentation = presentation,
		compact = compact, runs = runs, spec = spec,
	}
end
