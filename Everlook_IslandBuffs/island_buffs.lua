local addon_name = ...
local Everlook = Everlook
local kit = Everlook.island_feed_kit
local plain_number, now, option, dismiss, notify = kit.plain_number, kit.now, kit.option, kit.dismiss, kit.notify
local dismiss_map, map_pending = kit.dismiss_map, kit.map_pending
local state = {}

-- Long buffs (food, flasks, world buffs) are the ones worth a warning. A buff
-- already inside the window when the feed starts stays quiet, and combat is
-- skipped because the aura list can be restricted there.
local BUFF_MIN_DURATION, BUFF_WARN_SECONDS = 300, 60

local function buffs()
	if not option("feed_buffs") then
		dismiss_map(state.buff_handles)
		if not map_pending(state.buff_handles) then state.buff_seen, state.buff_handles = nil, nil end
		return
	end
	if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then return end
	local combat = InCombatLockdown and InCombatLockdown()
	if combat ~= false then return end
	local quiet = state.buff_seen == nil
	state.buff_seen = state.buff_seen or {}
	state.buff_handles = state.buff_handles or {}
	local time = now()
	local live = {}
	for index = 1, 40 do
		local aura = C_UnitAuras.GetAuraDataByIndex("player", index, "HELPFUL")
		if aura == nil then break end
		if type(aura) == "table" and not (issecretvalue and issecretvalue(aura)) then
			local spell_id, expires, duration = plain_number(aura.spellId), plain_number(aura.expirationTime), plain_number(aura.duration)
			local name = aura.name
			if spell_id and expires and duration and expires > 0 and duration >= BUFF_MIN_DURATION
				and type(name) == "string" and not (issecretvalue and issecretvalue(name)) and name ~= "" then
				local key = spell_id .. ":" .. math.floor(expires)
				live[key] = true
				local left = expires - time
				if left > 0 and left <= BUFF_WARN_SECONDS and not state.buff_seen[key] then
					state.buff_seen[key] = true
					if not quiet then
						state.buff_handles[key] = notify({
							source = "everlook.buffs", key = "buff:" .. key, kind = "buff", severity = "warning", duration = 8,
							text = name .. " is about to run out", detail = "Less than a minute left", spell_id = spell_id,
						})
					end
				end
			end
		end
	end
	for key in pairs(state.buff_seen) do
		if not live[key] then state.buff_seen[key] = nil end
	end
	for key, handle in pairs(state.buff_handles) do
		if not live[key] and dismiss(handle) then state.buff_handles[key] = nil end
	end
end

local function poll()
	if not kit.due(state.slow_at) then return end
	state.slow_at = now()
	buffs()
end

Everlook.module.extend("smart_island", {
	id = "buffs", addon = addon_name, order = 80,
	options = {
		feed_buffs = { name = "Buff expiry", default = false, description = "Warns when a long buff, such as food, a flask or a world buff, has under a minute left. Buffs shorter than five minutes are ignored. Buffs already that low when you turn this on stay quiet, and combat is skipped.", presets = { Quiet = false, Standard = false, Informative = true } },
	},
	sections = { { name = "Notices", keys = { "feed_buffs" } } },
	events = { "PLAYER_ENTERING_WORLD" },
	on_event = function() poll() end,
	apply = function(enabled)
		if not enabled then state = {}; return end
		state.slow_at = nil
		poll()
	end,
	refresh = function(force)
		if not force then poll() end
	end,
})
