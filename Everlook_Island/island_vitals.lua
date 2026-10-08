local Everlook = Everlook

-- Level, experience, money, durability and bag readings, and the words for those
-- figures. follow("refresh") copies them out through smart_island.pull before
-- the extensions hear the signal, so a warning never paints a stale total.
local vitals = {}
Everlook.island_vitals = vitals

local state = {}
local snapshot = {}

local function usable(value)
	if issecretvalue and issecretvalue(value) then return false end
	return value ~= nil
end

local function finite(value)
	return usable(value) and type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

-- UnitXP can return a secret value in combat. type() may not be "number".
local function bar_value(value)
	return type(value) == "number" or (issecretvalue and issecretvalue(value))
end

local function plain_number(value)
	if not usable(value) or type(value) ~= "number" then return nil end
	return value
end

-- One split for plain text, signed deltas, and native coin colors.
local function split_copper(copper)
	copper = plain_number(copper)
	if not copper then return nil end
	local sign = ""
	if copper < 0 then
		sign = "-"
		copper = -copper
	end
	copper = math.floor(copper)
	return sign, math.floor(copper / 10000), math.floor((copper % 10000) / 100), copper % 100
end

function vitals.money(copper)
	local sign, gold, silver, coins = split_copper(copper)
	if not sign then return "" end
	local parts = {}
	if gold > 0 then parts[#parts + 1] = gold .. "g" end
	if silver > 0 then parts[#parts + 1] = silver .. "s" end
	if coins > 0 or #parts == 0 then parts[#parts + 1] = coins .. "c" end
	return sign .. table.concat(parts, " ")
end

function vitals.rich(copper)
	local sign, gold, silver, coins = split_copper(copper)
	if not sign then return "" end
	if not GetMoneyString then return vitals.money(copper) end
	local parts = {}
	if gold > 0 then parts[#parts + 1] = "|cffffd166" .. GetMoneyString(gold * 10000, true, false) .. "|r" end
	if silver > 0 then parts[#parts + 1] = "|cffc6cbd4" .. GetMoneyString(silver * 100, false, false) .. "|r" end
	if coins > 0 or #parts == 0 then parts[#parts + 1] = "|cffdfaa7a" .. GetMoneyString(coins, false, false) .. "|r" end
	return sign .. table.concat(parts, " ")
end

function vitals.delta(copper)
	local amount = plain_number(copper)
	if not amount or amount == 0 then return "" end
	local text = vitals.money(amount)
	if amount > 0 then return "+" .. text end
	return text
end

function vitals.percent(current, maximum)
	if not usable(current) or not usable(maximum) then return "" end
	if type(current) ~= "number" or type(maximum) ~= "number" or maximum <= 0 then return "" end
	return string.format("%d%%", math.floor((current / maximum) * 100 + 0.5))
end

function vitals.bags(count)
	if not usable(count) or type(count) ~= "number" then return "" end
	if count == 1 then return "1 free slot" end
	return count .. " free slots"
end

-- The experience bar arithmetic that experience detail and the session recap
-- share.
local function whole(value)
	value = plain_number(value)
	if value == nil or value < 0 or value % 1 ~= 0 then return nil end
	return value
end

function vitals.at_cap(level)
	if type(GetMaxPlayerLevel) ~= "function" then return false end
	local cap = whole(GetMaxPlayerLevel())
	return cap ~= nil and cap >= 1 and level == cap
end

-- A nil gain is a reading we refuse to invent.
local function measure(base, now)
	if now.xp_max == 0 then
		if not vitals.at_cap(now.level) then return nil end
		if now.level == base.level then return 0, 0 end
		if now.level == base.level + 1 and base.xp_max >= base.xp then return base.xp_max - base.xp, 1 end
		return nil
	end
	if now.level == base.level then
		if now.xp < base.xp then return nil end
		return now.xp - base.xp, 0
	end
	if now.level == base.level + 1 and base.xp_max >= base.xp then
		return (base.xp_max - base.xp) + now.xp, 1
	end
end

function vitals.advance(previous, reading)
	if type(previous) ~= "table" or type(reading) ~= "table" then return nil end
	return measure(previous, reading)
end

local function phrase()
	snapshot.money_text = snapshot.money ~= nil and vitals.money(snapshot.money) or nil
	snapshot.durability_text = snapshot.durability ~= nil and vitals.percent(snapshot.durability, 100) or nil
	snapshot.bags_text = snapshot.bags ~= nil and vitals.bags(snapshot.bags) or nil
end

local function read_bar()
	if UnitXP and UnitXPMax then
		local xp, xp_max = UnitXP("player"), UnitXPMax("player")
		if bar_value(xp) then snapshot.xp = xp end
		if bar_value(xp_max) then snapshot.xp_max = xp_max end
	end
	local experience = vitals.percent(snapshot.xp, snapshot.xp_max)
	snapshot.xp_text = experience ~= "" and experience or nil
	if not UnitLevel then return end
	local level = UnitLevel("player")
	local pending = state.level_pending
	if finite(level) then
		if pending and level < pending then level = pending else state.level_pending = nil end
		snapshot.level = level
	elseif pending then
		snapshot.level = pending
	end
end

local function read_money()
	if not GetMoney then return end
	local copper = GetMoney()
	if not finite(copper) then return end
	snapshot.money = copper
end

local function read_durability()
	if not GetInventoryItemDurability then return end
	local first, last = INVSLOT_FIRST_EQUIPPED or 1, INVSLOT_LAST_EQUIPPED or 19
	local lowest
	for slot = first, last do
		local value, cap = GetInventoryItemDurability(slot)
		if finite(value) and finite(cap) and cap > 0 and value >= 0 then
			local percentage = value / cap * 100
			lowest = lowest and math.min(lowest, percentage) or percentage
		end
	end
	snapshot.durability = lowest
end

local function read_bags()
	if not C_Container or not C_Container.GetContainerNumFreeSlots then return end
	local first = BACKPACK_CONTAINER or 0
	local last = Constants and Constants.InventoryConstants and Constants.InventoryConstants.NumBagSlots or NUM_BAG_SLOTS
	if not finite(last) then last = 4 end
	last = math.min(last, 4) -- Native ContainerFrame classifies bag 5 as reagent-only.
	local free, total, capacity_unknown = 0, 0, false
	for bag = first, last do
		local slots, family = C_Container.GetContainerNumFreeSlots(bag)
		if not finite(slots) or slots < 0 then return end
		if bag == first or (finite(family) and family == 0) then
			free = free + slots
			local capacity = C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag)
			if finite(capacity) then total = total + capacity else capacity_unknown = true end
		elseif slots > 0 and not finite(family) then
			return -- Unclassified capacity cannot support a general-space warning.
		end
	end
	snapshot.bags = free
	snapshot.bags_total = not capacity_unknown and total > 0 and total or nil
end

local function refresh()
	snapshot.level, snapshot.xp, snapshot.xp_max = nil, nil, nil
	snapshot.money, snapshot.durability, snapshot.bags, snapshot.bags_total = nil, nil, nil, nil
	snapshot.money_text, snapshot.durability_text, snapshot.bags_text, snapshot.xp_text = nil, nil, nil, nil
	read_bar()
	read_money()
	read_durability()
	read_bags()
	phrase()
end

function vitals.snapshot()
	return snapshot
end

local function publish()
	local host = Everlook.smart_island
	if host and host.pull then host.pull() end
end

local function sync_level()
	if not state.level_ready then
		state.seen_level = snapshot.level
		state.level_ready = true
	end
end

local function note_level(level)
	if not finite(level) or level < 1 then return end
	state.level_pending = math.max(level, state.level_pending or level)
end

local function level_notice()
	if finite(snapshot.level) and finite(state.seen_level) and snapshot.level > state.seen_level then
		Everlook.island.notify({
			source = "smart_island", kind = "level", text = "Level " .. snapshot.level, severity = "success",
		})
	end
	if finite(snapshot.level) then
		state.seen_level = finite(state.seen_level) and math.max(state.seen_level, snapshot.level) or snapshot.level
	end
end

-- Extensions of the island, such as the warnings, read the same snapshot once
-- it is fresh.
local function tell_extensions(signal, a, b, c)
	for _, extension in ipairs(Everlook.module.extensions("smart_island")) do
		if extension.follow then extension.follow(signal, snapshot, a, b, c) end
	end
end

local function reset()
	state = {}
	snapshot.level, snapshot.xp, snapshot.xp_max = nil, nil, nil
	snapshot.money, snapshot.durability, snapshot.bags, snapshot.bags_total = nil, nil, nil, nil
	snapshot.money_text, snapshot.durability_text, snapshot.bags_text, snapshot.xp_text = nil, nil, nil, nil
end

function vitals.follow(signal, a, b, c)
	if signal == "hide" then reset(); tell_extensions(signal); return nil end
	if signal == "notice" then tell_extensions(signal, a, b, c); return snapshot end
	if signal == "sync" then sync_level(); tell_extensions(signal); return snapshot end
	if signal == "PLAYER_LEVEL_UP" then note_level(a) end
	if signal == "PLAYER_XP_UPDATE" or signal == "CHAT_MSG_COMBAT_XP_GAIN" or signal == "UPDATE_EXHAUSTION" then
		read_bar()
		return snapshot
	end
	refresh()
	publish()
	if signal == "PLAYER_LEVEL_UP" then
		level_notice()
	elseif signal == "catchup" then
		state.seen_level = snapshot.level
		state.level_ready = true
	end
	tell_extensions(signal)
	return snapshot
end
