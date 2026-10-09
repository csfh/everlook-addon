local addon_name = ...
local Everlook = Everlook
local vitals = Everlook.island_vitals

-- Warnings for low bag space and worn equipment, and a short net summary of
-- routine money changes. The island refreshes the snapshot before it calls
-- follow, so a warning never paints a stale total.
local state = {}
local snapshot = vitals.snapshot()

local function usable(value)
	if issecretvalue and issecretvalue(value) then return false end
	return value ~= nil
end

local function finite(value)
	return usable(value) and type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function option(key)
	return Everlook.module.get("smart_island", key)
end

local function dismiss(handle)
	if handle and Everlook.island and Everlook.island.dismiss then Everlook.island.dismiss(handle) end
end

local function post_condition(kind, key, handle, text, severity, announce)
	local live = Everlook.smart_island and Everlook.smart_island.notice_live and Everlook.smart_island.notice_live(handle)
	if not announce and not live then return handle end
	return Everlook.island.notify({
		source = "everlook." .. kind, key = key, kind = kind, text = text, severity = severity, persist = true,
		presentation = (announce or live == "toast") and "toast" or "inbox",
	})
end

local function bag_policy()
	if not option("source_bags") then
		dismiss(state.bag_handle)
		state.bag_handle, state.bag_band = nil, nil
		return
	end
	local slots = snapshot.bags
	if not finite(slots) then return end
	local threshold = option("low_slots")
	local band = slots == 0 and "full" or slots <= threshold and "low" or "normal"
	local prior = state.bag_band
	if not prior then state.bag_band = band; return end
	if slots > threshold + 2 then
		dismiss(state.bag_handle)
		state.bag_handle, state.bag_band = nil, "normal"
		return
	end
	if band ~= "normal" or prior ~= "normal" then
		local announce = (band == "full" and prior ~= "full") or (band == "low" and prior == "normal")
		state.bag_handle = post_condition("bags", "free-slots", state.bag_handle,
			slots == 0 and "The bags are full" or "Only " .. vitals.bags(slots),
			slots == 0 and "error" or "warning", announce)
		state.bag_band = slots == 0 and "full" or "low"
	end
end

local function durability_policy()
	if not option("source_durability") then
		dismiss(state.durability_handle)
		state.durability_handle, state.durability_bands = nil, nil
		return
	end
	local lowest = snapshot.durability
	if not finite(lowest) then return end
	if not state.durability_bands then
		state.durability_bands = { [30] = lowest <= 30, [10] = lowest <= 10, [0] = lowest == 0 }
		return
	end
	if lowest > 35 then
		dismiss(state.durability_handle)
		state.durability_handle = nil
	end
	local announce = false
	for _, threshold in ipairs({ 30, 10, 0 }) do
		if lowest <= threshold and not state.durability_bands[threshold] then
			state.durability_bands[threshold], announce = true, true
		elseif lowest > threshold + 5 then
			state.durability_bands[threshold] = false
		end
	end
	if lowest <= 35 then
		state.durability_handle = post_condition("durability", "equipment", state.durability_handle,
			lowest == 0 and "Equipment is broken" or "Equipment at " .. vitals.percent(lowest, 100),
			lowest == 0 and "error" or "warning", announce)
	end
end

local function flush_money(batch)
	if state.money_batch ~= batch then return end
	state.money_batch = nil
	if not Everlook.module.enabled("smart_island") or not option("source_money") or batch.delta == 0
		or math.abs(batch.delta) < option("money_min_silver") * 100 then return end
	Everlook.island.notify({
		source = "everlook.money", kind = "money",
		text = batch.delta > 0 and "Money received" or "Money spent", money = batch.delta,
		stack = batch.delta > 0 and "gain" or "spend",
	})
end

local function batch_money(delta)
	if not C_Timer or not C_Timer.After then return end
	local batch = state.money_batch
	if not batch then
		batch = { delta = 0 }
		state.money_batch = batch
		C_Timer.After(3, function() flush_money(batch) end)
	end
	batch.delta = batch.delta + delta
	local token = {}
	batch.quiet = token
	C_Timer.After(0.75, function()
		if batch.quiet == token then flush_money(batch) end
	end)
end

local function sync_options()
	local money_enabled = option("source_money")
	if state.money_enabled ~= money_enabled then
		state.money_batch = nil
		state.seen_money = snapshot.money
		state.money_enabled = money_enabled
	end
	local bags_enabled = option("source_bags")
	local low_slots = option("low_slots")
	if state.bags_enabled ~= bags_enabled or state.low_slots ~= low_slots then
		bag_policy()
		state.bags_enabled, state.low_slots = bags_enabled, low_slots
	end
	local durability_enabled = option("source_durability")
	if state.durability_enabled ~= durability_enabled then
		durability_policy()
		state.durability_enabled = durability_enabled
	end
end

local function money_notice()
	if option("source_money") and finite(snapshot.money) and finite(state.seen_money) and snapshot.money ~= state.seen_money then
		batch_money(snapshot.money - state.seen_money)
	end
	state.seen_money = snapshot.money
end

-- A confirmed personal repair or junk sale retires an equal pending money batch.
local function consume(source, detail, money)
	if (source == "everlook.auto_repair" and detail == "Paid from personal funds") or source == "everlook.sell_junk" then
		if finite(money) and money ~= 0 then
			local batch = state.money_batch
			if batch and batch.delta == money then state.money_batch = nil end
		end
	end
end

local function follow(signal, _, a, b, c)
	if signal == "hide" then state = {}; return end
	if signal == "notice" then consume(a, b, c); return end
	if signal == "sync" then sync_options(); return end
	if signal == "PLAYER_MONEY" then
		money_notice()
	elseif signal == "UPDATE_INVENTORY_DURABILITY" then
		durability_policy()
	elseif signal == "BAG_UPDATE_DELAYED" then
		bag_policy()
	elseif signal == "catchup" then
		state.seen_money = snapshot.money
	end
end

Everlook.module.extend("smart_island", {
	id = "warnings", addon = addon_name, order = 110,
	options = {
		source_bags = { name = "Warn about general bag space", default = true, description = "Warns when general bag space falls to the low free-slot threshold or runs out. Specialty and reagent bags stay out of the count, a bag the client cannot classify stays quiet, space already that low stays quiet until it rises more than two free slots above that threshold and falls again, and turning this off clears the notice.", presets = { Quiet = true, Standard = true, Informative = true } },
		low_slots = { name = "Low free-slot threshold", default = 5, min = 1, max = 15, step = 1, description = "Warns when general free slots fall to this number or below, from 1 to 15, in steps of 1, and stays quiet unless Warn about general bag space is on. Slots already that low stay quiet, the notice goes away once you have more than two free slots above this number, and the warning can return the next time you fall to it." },
		source_durability = { name = "Warn about equipment durability", default = true, description = "Warns when the weakest equipped piece falls to 30%, to 10%, or breaks. Gear already that low stays quiet until it rises more than five points past that mark and falls again, the notice goes away once the piece is above 35%, and turning this off clears it.", presets = { Quiet = true, Standard = true, Informative = true } },
		source_money = { name = "Notify about routine money changes", default = false, description = "Posts one notice for the money you gain and spend once the changes pause for three quarters of a second, or after three seconds. A net of zero, or one smaller than the silver minimum, stays quiet, money already held when you turn this on stays quiet, a personal repair or junk sale that already reported the same amount drops this summary, turning this off drops a summary that has not posted, and your gold total still updates.", presets = { Quiet = false, Standard = false, Informative = true } },
		money_min_silver = { name = "Minimum money change", default = 1, min = 0, max = 100, step = 1, unit = " silver", description = "Keeps the routine money notice quiet when the gain or the spend is under this many silver, from 0 to 100, in steps of 1. A change that reaches this many silver posts, zero lets a copper change through while no change stays quiet, this number does nothing unless Notify about routine money changes is on, and repair notices, junk-sale notices, and your gold total are left alone." },
	},
	sections = { { name = "Activity", keys = { "source_bags", "low_slots", "source_durability", "source_money", "money_min_silver" }, before = "source_repair" } },
	follow = follow,
})
