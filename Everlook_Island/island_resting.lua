local Everlook = Everlook

-- The closed pill's resting display: the level, and the figures the player chose to see beside it.
-- It builds a capsule from the figures the island has read and sends it through Everlook.island.notify
-- as a resting status, the lowest rung of the capsule, so the island draws it the way it draws every
-- other capsule. It reads nothing from the game and draws nothing.
local resting = {}
Everlook.island_resting = resting

local SOURCE = "everlook_resting"
local last_signature
local handle

local TONES = { primary = 1, secondary = 2, warning = 3, error = 4 }

-- Gear and bags share one label, because a capsule keeps three. It takes the tone of the worse reading.
local function warnings(readout, options)
	local texts, worst = {}, "secondary"
	local function add(text, tone)
		texts[#texts + 1] = text
		if TONES[tone] > TONES[worst] then worst = tone end
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
function resting.spec(readout, options)
	local level = options.level
	if type(level) ~= "string" or level == "" then return nil end
	local labels = {}
	if options.xp and readout.xp_text then labels[#labels + 1] = { text = readout.xp_text, tone = "accent" } end
	if options.clock and readout.clock_text and readout.clock_text ~= "" then labels[#labels + 1] = readout.clock_text end
	local extra = warnings(readout, options)
	if extra then labels[#labels + 1] = extra end
	return { text = level, labels = #labels > 0 and labels or nil }
end

local function signature(spec)
	if not spec then return "" end
	local parts = { spec.text }
	for _, label in ipairs(spec.labels or {}) do
		parts[#parts + 1] = type(label) == "table" and (label.text .. "\1" .. label.tone) or label
	end
	return table.concat(parts, "\0")
end

-- Pushes the capsule, unless it is the one pushed last. Returns whether it pushed, which is when the
-- island redraws.
function resting.push(readout, options, force)
	local api = Everlook.island
	if not api or type(api.notify) ~= "function" then return false end
	local spec = resting.spec(readout, options)
	local current = signature(spec)
	if current == last_signature and not force then return false end
	last_signature = current
	if not spec then
		if handle then api.dismiss(handle); handle = nil end
		return true
	end
	handle = api.notify({
		source = SOURCE, key = "chip", kind = "level", text = options.level, presentation = "status", rank = "resting",
		capsule = spec,
	}) or handle
	return true
end

-- Forgets what was pushed, for when the island has cleared what it holds.
function resting.reset()
	last_signature, handle = nil, nil
end
