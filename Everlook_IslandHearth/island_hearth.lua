local addon_name = ...
local Everlook = Everlook
local kit = Everlook.island_feed_kit
local plain_number, now, option, dismiss, notify = kit.plain_number, kit.now, kit.option, kit.dismiss, kit.notify
local inspect_item = kit.inspect_item
local HEARTH_ID = 6948
local state = {}

-- A notice when the Hearthstone comes off cooldown.
-- C_Item.GetItemCooldown reports enableCooldownTimer as a boolean.
-- The older item cooldown function reports 1 or 0. Either form counts.
local function timer_enabled(enable)
	if enable == true then return true end
	if enable == false then return false end
	local value = plain_number(enable)
	return value ~= nil and value ~= 0
end

-- GetItemCooldown reports the global cooldown, at most 1.5 seconds, while the
-- stone itself is ready. The hearthstone cooldown is minutes.
local function cooldown_ready(start, duration, enable)
	start, duration = plain_number(start), plain_number(duration)
	if not start or not duration then return nil end
	if enable ~= nil and not timer_enabled(enable) then return false end
	if duration > 0 and start > 0 and duration <= 2 and now() < start + duration then return true end
	if duration <= 0 or start <= 0 then return true end
	return now() >= start + duration
end

local function hearth()
	if not option("feed_hearth") then
		if dismiss(state.hearth_handle) then state.hearth_handle = nil end
		state.hearth = nil
		return
	end
	if not C_Item or not C_Item.GetItemCount or not C_Item.GetItemCooldown then return end
	local count = plain_number(C_Item.GetItemCount(HEARTH_ID))
	if not count then return end
	if count < 1 then
		if dismiss(state.hearth_handle) then state.hearth_handle = nil end
		state.hearth = { owned = false }
		return
	end
	local ready = cooldown_ready(C_Item.GetItemCooldown(HEARTH_ID))
	if ready == nil then return end
	local prior = state.hearth
	if not prior or not prior.owned then
		state.hearth = { owned = true, ready = ready }
		return
	end
	if prior.ready == false and ready then
		state.hearth_handle = notify({
			source = "everlook.hearth", key = "hearth:ready", kind = "hearth", persist = true,
			text = "Hearthstone ready", item_id = HEARTH_ID,
			actions = {
				{ id = "hearth", label = "Hearth", type = "item", item_id = HEARTH_ID },
				{ id = "inspect", label = "Inspect", type = "callback", on_click = inspect_item(HEARTH_ID) },
			},
		})
	elseif prior.ready and not ready then
		if dismiss(state.hearth_handle) then state.hearth_handle = nil end
	end
	state.hearth.ready = ready
end

Everlook.module.extend("smart_island", {
	id = "hearth", addon = addon_name, order = 30,
	options = {
		feed_hearth = { name = "Hearthstone", default = false, description = "Tells you when your Hearthstone finishes its cooldown. A stone you do not have, one already ready the first time it is seen, the pause after a spell, or a cooldown the client hides or has switched off stays quiet, the notice goes away when that cooldown starts again, and turning this off clears it once combat allows.", presets = { Quiet = false, Standard = true, Informative = true } },
	},
	sections = { { name = "Notices", keys = { "feed_hearth" } } },
	events = { "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD" },
	on_event = function() hearth() end,
	apply = function(enabled)
		if enabled then hearth() else state = {} end
	end,
	refresh = function(force)
		if not force then hearth() end
	end,
})
