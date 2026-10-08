local addon_name = ...
local Everlook = Everlook
local kit = Everlook.island_feed_kit
local plain_number, option, dismiss, notify = kit.plain_number, kit.option, kit.dismiss, kit.notify
local state = {}

-- A summary every half hour: quests completed, experience, net money and time on.
local function clock()
	local value = GetTime and GetTime()
	return plain_number(value)
end

local function ensure_recap()
	if state.recap then return state.recap end
	local started = clock() or 0
	state.recap = { quests = 0, xp = 0, xp_incomplete = false, started = started, next_at = started + 1800 }
	return state.recap
end

-- UnitXPMax is 0 at the level cap. That empty bar is not a missing reading.
local function empty_cap_bar(level, xp, xp_max)
	if level == nil or xp == nil or level < 1 or level % 1 ~= 0 or xp < 0 or xp % 1 ~= 0 then return false end
	if xp_max ~= nil and xp_max ~= 0 then return false end
	return Everlook.island_vitals.at_cap(level) == true
end

local function bar_reading(level, xp, xp_max)
	if empty_cap_bar(level, xp, xp_max) then return { level = level, xp = 0, xp_max = 0 } end
	if not (level and xp and xp_max and level >= 1 and level % 1 == 0 and xp >= 0 and xp % 1 == 0 and xp_max >= 1 and xp_max % 1 == 0) then
		return nil
	end
	return { level = level, xp = xp, xp_max = xp_max }
end

local function sample_recap()
	local row = ensure_recap()
	local money = type(GetMoney) == "function" and plain_number(GetMoney()) or nil
	if row.money_base == nil and money and money % 1 == 0 then row.money_base = money end
	if row.xp_incomplete then return end
	local level = type(UnitLevel) == "function" and plain_number(UnitLevel("player")) or nil
	local xp = type(UnitXP) == "function" and plain_number(UnitXP("player")) or nil
	local xp_max = type(UnitXPMax) == "function" and plain_number(UnitXPMax("player")) or nil
	local reading = bar_reading(level, xp, xp_max)
	if not reading then
		row.xp_incomplete = true
		return
	end
	if not row.xp_level then
		row.xp_level, row.xp_value, row.xp_max = reading.level, reading.xp, reading.xp_max
		return
	end
	local gain = Everlook.island_vitals.advance(
		{ level = row.xp_level, xp = row.xp_value, xp_max = row.xp_max }, reading)
	if not gain then
		row.xp_incomplete = true
		return
	end
	row.xp = row.xp + gain
	row.xp_level, row.xp_value, row.xp_max = reading.level, reading.xp, reading.xp_max
end

local function elapsed_text(seconds)
	seconds = math.floor(seconds)
	if seconds < 0 then seconds = 0 end
	if seconds < 60 then return seconds .. (seconds == 1 and " second" or " seconds") end
	local minutes = math.floor(seconds / 60)
	if minutes < 60 then return minutes .. (minutes == 1 and " minute" or " minutes") end
	local hours = math.floor(minutes / 60)
	minutes = minutes % 60
	if minutes == 0 then return hours .. (hours == 1 and " hour" or " hours") end
	return hours .. " h " .. minutes .. " m"
end

local function publish_recap()
	local row = state.recap
	if not row then return false end
	local lines = { "Quests completed: " .. row.quests }
	if row.xp_incomplete or not row.xp_level then lines[#lines + 1] = "XP incomplete" else lines[#lines + 1] = "XP gained: " .. row.xp end
	local money = type(GetMoney) == "function" and plain_number(GetMoney()) or nil
	local net = money and row.money_base and money % 1 == 0 and (money - row.money_base) or nil
	if net == nil then lines[#lines + 1] = "Money unavailable" else lines[#lines + 1] = "Net money: " .. (net > 0 and "+" or "") .. Everlook.island_vitals.money(net) end
	local time = clock()
	if not time then lines[#lines + 1] = "Time unavailable" else lines[#lines + 1] = "Elapsed: " .. elapsed_text(time - row.started) end
	state.recap_handle = notify({
		source = "everlook.recap", key = "session-recap", kind = "info", text = "Session recap", duration = 12,
		detail = table.concat(lines, "\n"), interaction = "expand",
	})
	return state.recap_handle ~= nil
end

local function recap()
	if not option("feed_recap") then
		if dismiss(state.recap_handle) then state.recap_handle = nil end
		state.recap = nil
		return
	end
	local created = not state.recap
	sample_recap()
	if created then return end
	local time = clock()
	if time and time >= state.recap.next_at then
		publish_recap()
		state.recap.next_at = time + 1800
	end
end

local function recap_now()
	if not option("feed_recap") then return false end
	sample_recap()
	return publish_recap()
end

local function turned_in(quest_id)
	if not option("feed_recap") then return end
	quest_id = plain_number(quest_id)
	if not quest_id or quest_id < 1 or quest_id % 1 ~= 0 then return end
	sample_recap()
	state.recap.quests = state.recap.quests + 1
end

Everlook.module.extend("smart_island", {
	id = "recap", addon = addon_name, order = 90,
	options = {
		feed_recap = { name = "Session recap", default = false, description = "Posts a summary every 30 minutes: quests completed, experience gained, net money and time on. The first one comes after half an hour. A missing reading is marked incomplete or unavailable, and an empty bar at the level cap counts as no experience. Turning this off clears the notice.", presets = { Quiet = false, Standard = false, Informative = true } },
	},
	sections = { {
		name = "Notices", keys = { "feed_recap" },
		after = function(layout)
			layout:AddInitializer(CreateSettingsButtonInitializer("Session recap", "Show recap", recap_now,
				"Show quests, experience, money, and elapsed time since Session recap was turned on.", true))
		end,
	} },
	events = { "QUEST_TURNED_IN", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_MONEY", "PLAYER_ENTERING_WORLD" },
	on_event = function(event, ...)
		if event == "QUEST_TURNED_IN" then turned_in(...)
		elseif event == "PLAYER_ENTERING_WORLD" then recap()
		elseif option("feed_recap") and state.recap then sample_recap() end
	end,
	apply = function(enabled)
		if enabled then recap() else state = {} end
	end,
	refresh = function(force)
		if not force then recap() end
	end,
})
