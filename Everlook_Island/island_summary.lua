local Everlook = Everlook

-- The open island's top: the level line, and the status cells under it. It builds them from the
-- figures the island has read and pushes them through Everlook.island.section like any other
-- source, so the island draws them the way it draws everyone's. It also builds the closed pill's
-- resting display, the level and the figures beside it, and pushes that through Everlook.island.notify
-- as a resting status. It reads nothing from the game and draws nothing.
local summary = {}
Everlook.island_summary = summary

local SOURCE = "everlook_summary"
local last_signature
local handles = {}

local function state_of(percent)
	if not percent then return nil end
	if percent <= 10 then return "error" end
	if percent <= 30 then return "warning" end
	return nil
end

local function header_section(readout)
	local labels = {}
	if readout.clock_text and readout.clock_text ~= "" then labels[#labels + 1] = readout.clock_text end
	if readout.xp_text and readout.xp_text ~= "" then labels[#labels + 1] = { text = readout.xp_text, tone = "accent" } end
	return {
		source = SOURCE, key = "header", region = "header", order = 10,
		blocks = { { kind = "row", row = { title = readout.level and ("Level " .. readout.level) or "Level", labels = labels } } },
	}
end

local function metric_section(readout, low_slots)
	local cells = {}
	if readout.money_text and readout.money then
		cells[#cells + 1] = { icon = "money", label = "Money", value = { money = readout.money }, tooltip = "Money: " .. readout.money_text }
	end
	if readout.coords_text and readout.coords_text ~= "" then
		cells[#cells + 1] = { label = "Position", value = readout.coords_text, tooltip = "Coordinates: " .. readout.coords_text }
	end
	local durability = readout.durability
	if readout.durability_text and readout.durability_text ~= "" then
		local state = state_of(durability)
		cells[#cells + 1] = { icon = "repair", label = "Gear", value = readout.durability_text, tone = state, tooltip = "Lowest durability: " .. readout.durability_text,
			ring = durability and { fraction = math.max(0, math.min(1, durability / 100)), tone = state or "muted" } or nil }
	end
	local free, total = readout.bags, readout.bags_total
	if free then
		local state = (free == 0 and "error") or (low_slots and free <= low_slots and "warning") or nil
		local text = free .. " free" .. (total and (" of " .. total) or "")
		cells[#cells + 1] = { icon = "bags", label = "Bags", value = text, tone = state, tooltip = "Free slots: " .. text,
			ring = (total and total > 0) and { fraction = math.max(0, math.min(1, free / total)), tone = state or "muted" } or nil }
	end
	if #cells == 0 then return nil end
	return { source = SOURCE, key = "status", region = "metrics", order = 10, title = "Status", blocks = { { kind = "cells", cells = cells } } }
end

local function signature(readout, low_slots)
	return table.concat({ tostring(readout.level), tostring(readout.clock_text), tostring(readout.xp_text), tostring(readout.money),
		tostring(readout.money_text), tostring(readout.coords_text), tostring(readout.durability), tostring(readout.durability_text),
		tostring(readout.bags), tostring(readout.bags_total), tostring(low_slots) }, "\0")
end

-- Pushes both sections, unless nothing they show has changed since the last push. Returns
-- whether it pushed, which is when the island redraws.
function summary.push(readout, low_slots, force)
	local api = Everlook.island
	if not api or type(api.section) ~= "function" then return false end
	local current = signature(readout, low_slots)
	if current == last_signature and not force then return false end
	last_signature = current
	handles.header = api.section(header_section(readout))
	local metrics = metric_section(readout, low_slots)
	if metrics then
		handles.metrics = api.section(metrics)
	elseif handles.metrics then
		api.dismiss(handles.metrics)
		handles.metrics = nil
	end
	return true
end

-- The closed pill's resting display. It is pushed as a resting status, the lowest rung of the capsule.
local RESTING_SOURCE = "everlook_resting"
local resting_signature
local resting_handle

local TONE_RANK = { primary = 1, secondary = 2, warning = 3, error = 4 }

-- Gear and bags share one label, because a capsule keeps three. It takes the tone of the worse reading.
local function warnings(readout, options)
	local texts, worst = {}, "secondary"
	local function add(text, tone)
		texts[#texts + 1] = text
		if TONE_RANK[tone] > TONE_RANK[worst] then worst = tone end
	end
	local durability = readout.durability
	if type(durability) == "number" and durability <= 30 and options.gear and readout.durability_text then
		add("Gear " .. readout.durability_text, durability <= 10 and "error" or "warning")
	end
	local slots = readout.bags
	if type(slots) == "number" and options.bags and slots <= options.low_slots then
		add("Bags " .. slots, slots == 0 and "error" or "warning")
	elseif type(slots) == "number" and options.free then
		add(slots .. " free", "secondary")
	end
	if #texts == 0 then return nil end
	return { text = table.concat(texts, "  "), tone = worst }
end

-- The capsule for these figures, or nil while there is no level to show.
function summary.resting_spec(readout, options)
	local level = options.level
	if type(level) ~= "string" or level == "" then return nil end
	local labels = {}
	if options.xp and readout.xp_text then labels[#labels + 1] = { text = readout.xp_text, tone = "accent" } end
	if options.clock and readout.clock_text and readout.clock_text ~= "" then labels[#labels + 1] = readout.clock_text end
	local extra = warnings(readout, options)
	if extra then labels[#labels + 1] = extra end
	return { text = level, labels = #labels > 0 and labels or nil }
end

local function resting_signature_of(spec)
	if not spec then return "" end
	local parts = { spec.text }
	for _, label in ipairs(spec.labels or {}) do
		parts[#parts + 1] = type(label) == "table" and (label.text .. "\1" .. label.tone) or label
	end
	return table.concat(parts, "\0")
end

-- Pushes the capsule, unless it is the one pushed last. Returns whether it pushed, which is when the
-- island redraws.
function summary.push_resting(readout, options, force)
	local api = Everlook.island
	if not api or type(api.notify) ~= "function" then return false end
	local spec = summary.resting_spec(readout, options)
	local current = resting_signature_of(spec)
	if current == resting_signature and not force then return false end
	resting_signature = current
	if not spec then
		if resting_handle then api.dismiss(resting_handle); resting_handle = nil end
		return true
	end
	resting_handle = api.notify({
		source = RESTING_SOURCE, key = "chip", kind = "level", text = options.level, presentation = "status", rank = "resting",
		capsule = spec,
	}) or resting_handle
	return true
end

-- Forgets what was pushed, for when the island has cleared what it holds.
function summary.reset()
	last_signature, handles = nil, {}
	resting_signature, resting_handle = nil, nil
end
