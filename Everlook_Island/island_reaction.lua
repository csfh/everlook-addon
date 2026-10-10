local Everlook = Everlook

-- A reaction is a brief tint and edge flash on the island's body. This file is
-- the arithmetic only: which kinds there are, when a new one merges into the one
-- already playing, how many may start a second, and how bright it is at a moment.
-- smart_island.lua turns the numbers into colours on its surfaces.
local reaction = {}
Everlook.island_reaction = reaction

-- tone names a colour in island_capsule's TONES. Strength is how bright the peak is,
-- from 0 to 1. A kind shows a tint over the body, a flash on the edge, or both. A warning and an
-- error are mostly edge, with a light tint (`tint_share` of a full one) so the small closed pill,
-- whose straight edges are short, still shows them.
reaction.kinds = {
	kill = { tone = "accent", strength = 0.5, duration = 0.32, beats = 1, tint = true, edge = true },
	loot = { tone = "success", strength = 0.35, duration = 0.24, beats = 1, tint = true, edge = false },
	level = { tone = "gold", strength = 1, duration = 0.6, beats = 1, tint = true, edge = true },
	warning = { tone = "warning", strength = 0.7, duration = 0.48, beats = 2, tint = true, tint_share = 0.4, edge = true },
	error = { tone = "error", strength = 0.8, duration = 0.32, beats = 1, tint = true, tint_share = 0.4, edge = true },
	info = { tone = "secondary", strength = 0.25, duration = 0.2, beats = 1, tint = true, edge = false },
}

-- The tint never goes past this opacity, whatever the strength, so text over it stays readable.
reaction.tint_ceiling = 0.18
reaction.edge_ceiling = 0.9
-- A reaction that starts this soon after another joins it.
reaction.merge_window = 0.25
-- At most this many start in one second.
reaction.per_second = 4
local ATTACK = 0.06
-- With reduced motion a reaction is one short fade to a fixed, lower brightness.
local REDUCED_DURATION, REDUCED_TINT, REDUCED_EDGE = 0.15, 0.12, 0.6

function reaction.new()
	return { pulse = nil, starts = {} }
end

local function clamp(value)
	return math.max(0, math.min(1, value))
end

-- Starts a reaction of `kind`. `strength` (0 to 1) replaces the kind's own. Returns true,
-- or nil and a reason: invalid_reaction (no such kind) or limited (too many this second).
function reaction.start(state, kind, strength, now, reduced)
	local spec = type(kind) == "string" and reaction.kinds[kind]
	if not spec then return nil, "invalid_reaction" end
	if strength ~= nil and (type(strength) ~= "number" or strength ~= strength) then return nil, "invalid_reaction" end
	strength = clamp(strength or spec.strength)
	local recent = {}
	for _, started in ipairs(state.starts) do
		if now - started < 1 then recent[#recent + 1] = started end
	end
	state.starts = recent
	if #recent >= reaction.per_second then return nil, "limited" end
	recent[#recent + 1] = now
	local current = state.pulse
	if current and now - current.start < reaction.merge_window then
		-- Joining keeps the louder of the two and starts the decay again from now.
		if strength >= current.strength then
			current.kind, current.spec, current.strength = kind, spec, strength
		end
		current.start, current.reduced = now, reduced == true
		return true
	end
	state.pulse = { kind = kind, spec = spec, strength = strength, start = now, reduced = reduced == true }
	return true
end

-- How bright the reaction is at `now`: { tone, tint, edge } with tint and edge as opacities,
-- or nil when none is playing. A finished reaction is dropped.
function reaction.sample(state, now)
	local pulse = state.pulse
	if not pulse then return nil end
	local spec, elapsed = pulse.spec, now - pulse.start
	local duration = pulse.reduced and REDUCED_DURATION or spec.duration
	if elapsed >= duration then
		state.pulse = nil
		return nil
	end
	local level
	if pulse.reduced then
		level = 1 - elapsed / duration
	else
		local beat = duration / spec.beats
		local into = elapsed - math.floor(elapsed / beat) * beat
		local attack = math.min(ATTACK, beat * 0.3)
		if into < attack then
			level = into / attack
		else
			local share = (into - attack) / (beat - attack)
			level = (1 - share) * (1 - share)
		end
	end
	local tint_peak = pulse.reduced and REDUCED_TINT * pulse.strength or reaction.tint_ceiling * pulse.strength
	local edge_peak = pulse.reduced and REDUCED_EDGE * pulse.strength or reaction.edge_ceiling * pulse.strength
	return { tone = spec.tone, tint = spec.tint and tint_peak * (spec.tint_share or 1) * level or 0, edge = spec.edge and edge_peak * level or 0 }
end
