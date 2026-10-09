local addon_name = ...
local Everlook = Everlook

-- Hour and day totals come from the experience bar. Quest turn-ins and named
-- kill lines only label a slice of that bar. A secret reading waits; it is
-- never compared or formatted.
local experience = {}
Everlook.island_experience = experience

local KILL_TEXT = {
	"COMBATLOG_XPGAIN_EXHAUSTION1_RAID",
	"COMBATLOG_XPGAIN_EXHAUSTION1_GROUP",
	"COMBATLOG_XPGAIN_EXHAUSTION1",
	"COMBATLOG_XPGAIN_EXHAUSTION2_RAID",
	"COMBATLOG_XPGAIN_EXHAUSTION2_GROUP",
	"COMBATLOG_XPGAIN_EXHAUSTION2",
	"COMBATLOG_XPGAIN_EXHAUSTION3_RAID",
	"COMBATLOG_XPGAIN_EXHAUSTION3_GROUP",
	"COMBATLOG_XPGAIN_EXHAUSTION3",
	"COMBATLOG_XPGAIN_EXHAUSTION4_RAID",
	"COMBATLOG_XPGAIN_EXHAUSTION4_GROUP",
	"COMBATLOG_XPGAIN_EXHAUSTION4",
	"COMBATLOG_XPGAIN_EXHAUSTION5_RAID",
	"COMBATLOG_XPGAIN_EXHAUSTION5_GROUP",
	"COMBATLOG_XPGAIN_EXHAUSTION5",
	"COMBATLOG_XPGAIN_FIRSTPERSON_RAID",
	"COMBATLOG_XPGAIN_FIRSTPERSON_GROUP",
	"COMBATLOG_XPGAIN_FIRSTPERSON",
}

local HOUR, DAY, KEEP = 3600, 86400, 25 * 3600
local session

local function enabled()
	return Everlook.module and Everlook.module.enabled and Everlook.module.enabled("smart_island") == true
end

local function secret(value)
	return issecretvalue and issecretvalue(value) and true or false
end

local function plain_number(value)
	if secret(value) then return nil end
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return nil end
	return value
end

local function whole(value)
	value = plain_number(value)
	if value == nil or value < 0 or value % 1 ~= 0 then return nil end
	return value
end

local function server_now()
	if type(GetServerTime) == "function" then
		local value = whole(GetServerTime())
		if value then return value end
	end
	if type(time) == "function" then
		local value = whole(time())
		if value then return value end
	end
end

local function character_key()
	if type(UnitGUID) ~= "function" then return nil end
	local guid = UnitGUID("player")
	if secret(guid) or type(guid) ~= "string" or not guid:match("^Player%-") then return nil end
	return guid
end

local function read_bar()
	if type(UnitXP) ~= "function" or type(UnitXPMax) ~= "function" or type(UnitLevel) ~= "function" then return nil end
	local xp, xp_max, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
	if secret(xp) or secret(xp_max) or secret(level) then return "secret" end
	level, xp, xp_max = whole(level), whole(xp), whole(xp_max)
	if not level or level < 1 or not xp or not xp_max then return "invalid" end
	return { level = level, xp = xp, xp_max = xp_max }
end

local function empty_row(now)
	return {
		total = 0, quest = 0, kill = 0, other = 0, unsorted = 0, levels = 0,
		started = now, gap = false, overflow = false, split = false,
	}
end

local function valid_row(row)
	if type(row) ~= "table" then return false end
	for _, name in ipairs({ "total", "quest", "kill", "other", "unsorted", "levels" }) do
		local value = row[name]
		if type(value) ~= "number" or value < 0 or value % 1 ~= 0 or value ~= value then return false end
	end
	return true
end

local function baseline_ok(row)
	if type(row) ~= "table" then return nil end
	local level, xp, xp_max = whole(row.level), whole(row.xp), whole(row.xp_max)
	if not level or level < 1 or not xp or not xp_max then return nil end
	return { level = level, xp = xp, xp_max = xp_max }
end

local function prune(buckets, now)
	local cutoff = now - KEEP
	for key, row in pairs(buckets) do
		local minute = tonumber(key)
		if type(key) ~= "string" or not minute or minute < cutoff or not valid_row(row) then buckets[key] = nil end
	end
end

-- The ledger keeps a minute row for a day. Pruning walks every row, so it runs
-- at most once a minute. rev marks each change for the report cache.
local PRUNE_EVERY = 60

local function persist(current)
	if not current then return end
	current.rev = (current.rev or 0) + 1
	if not current.key then return end
	local now = server_now()
	if now and (not current.pruned_at or now - current.pruned_at >= PRUNE_EVERY or now < current.pruned_at) then
		prune(current.buckets, now)
		current.pruned_at = now
	end
	EverlookDB = EverlookDB or {}
	if type(EverlookDB.experience) ~= "table" then EverlookDB.experience = {} end
	local baseline = current.baseline
	EverlookDB.experience[current.key] = {
		baseline = baseline and { level = baseline.level, xp = baseline.xp, xp_max = baseline.xp_max } or nil,
		buckets = current.buckets,
	}
end

local function load_character(key)
	local current = {
		key = key, buckets = {}, pending_quest = 0, pending_kill = 0, blind = false, latest = nil,
	}
	if not key then return current end
	local saved = EverlookDB and type(EverlookDB.experience) == "table" and EverlookDB.experience[key] or nil
	if type(saved) ~= "table" then return current end
	if type(saved.buckets) == "table" then
		for key_name, row in pairs(saved.buckets) do
			local minute = type(key_name) == "string" and tonumber(key_name) or nil
			if minute and valid_row(row) then
				current.buckets[key_name] = {
					total = row.total, quest = row.quest, kill = row.kill, other = row.other,
					unsorted = row.unsorted, levels = row.levels,
					started = type(row.started) == "number" and row.started or minute,
					gap = row.gap == true, overflow = row.overflow == true, split = row.split == true,
				}
			end
		end
	end
	local baseline = baseline_ok(saved.baseline)
	if baseline then
		current.baseline = baseline
		-- Labels from before this load are gone, so the next gain stays unlabeled.
		current.blind = true
	end
	return current
end

local function current()
	if not enabled() then return nil end
	local key = character_key()
	local id = key or false
	if session and session.key == id then return session end
	if session then persist(session) end
	session = load_character(key)
	if not key then session.key = false end
	return session
end

local function mark_split(row)
	row.split = row.unsorted > 0 or row.overflow == true
end

local function mark_gap(current, now)
	local key = tostring(math.floor(now / 60) * 60)
	local row = current.buckets[key] or empty_row(now)
	row.gap = true
	current.buckets[key] = row
	current.pending_quest, current.pending_kill = 0, 0
	current.blind, current.latest = false, nil
	persist(current)
end

local function add_gain(current, now, gain, levels)
	local key = tostring(math.floor(now / 60) * 60)
	local row = current.buckets[key]
	if not row then
		row = empty_row(now)
		current.buckets[key] = row
	elseif not row.started or now < row.started then
		row.started = now
	end
	local quest = math.min(current.pending_quest, gain)
	local room = gain - quest
	local kill = math.min(current.pending_kill, room)
	room = room - kill
	if current.pending_quest + current.pending_kill > gain then row.overflow = true end
	if current.blind then row.unsorted = row.unsorted + room else row.other = row.other + room end
	row.total = row.total + gain
	row.quest = row.quest + quest
	row.kill = row.kill + kill
	row.levels = row.levels + levels
	mark_split(row)
	current.pending_quest, current.pending_kill = 0, 0
	current.blind = false
	current.latest = { at = now, key = key }
	persist(current)
end

local function sample()
	local current_session = current()
	if not current_session then return end
	local now = server_now()
	if not now then return end
	local reading = read_bar()
	if reading == "secret" then
		current_session.blind = true
		return
	end
	if reading == "invalid" then
		mark_gap(current_session, now)
		return
	end
	if not reading then return end
	if not current_session.baseline then
		current_session.baseline = reading
		persist(current_session)
		return
	end
	local gain, levels = Everlook.island_vitals.advance(current_session.baseline, reading)
	current_session.baseline = reading
	if not gain then
		mark_gap(current_session, now)
		return
	end
	if gain == 0 and levels == 0 then
		current_session.blind = false
		persist(current_session)
		return
	end
	add_gain(current_session, now, gain, levels)
end

local function cover(row, amount)
	if row.unsorted + row.other < amount then return false end
	local taken = math.min(row.unsorted, amount)
	row.unsorted = row.unsorted - taken
	row.other = row.other - (amount - taken)
	mark_split(row)
	return true
end

local function note(current_session, kind, amount)
	local now = server_now()
	local latest = current_session.latest
	-- A label that fits the gain we just counted names that gain. One that does
	-- not fit is waiting for the next bar move, so it stays pending.
	if now and latest and now >= latest.at and now - latest.at <= 1 then
		local row = current_session.buckets[latest.key]
		if row and cover(row, amount) then
			row[kind] = row[kind] + amount
			mark_split(row)
			persist(current_session)
			return
		end
	end
	if kind == "quest" then
		current_session.pending_quest = current_session.pending_quest + amount
	else
		current_session.pending_kill = current_session.pending_kill + amount
	end
end

local function pattern_from(fmt)
	if type(fmt) ~= "string" or secret(fmt) or fmt == "" then return nil end
	local kinds, parts = {}, {}
	local i, size = 1, #fmt
	while i <= size do
		if fmt:sub(i, i) == "%" then
			local digits, spec = fmt:match("^%%(%d+)%$([sd])", i)
			if digits then
				kinds[#kinds + 1] = spec
				parts[#parts + 1] = spec == "d" and "(%d+)" or "(.-)"
				i = i + #digits + 3
			else
				spec = fmt:match("^%%([sd%%])", i)
				if spec == "d" or spec == "s" then
					kinds[#kinds + 1] = spec
					parts[#parts + 1] = spec == "d" and "(%d+)" or "(.-)"
					i = i + 2
				elseif spec == "%" then
					parts[#parts + 1] = "%%"
					i = i + 2
				else
					return nil
				end
			end
		else
			local ch = fmt:sub(i, i)
			if ch:match("[%^%$%(%)%.%[%]%*%+%-%?]") then
				parts[#parts + 1] = "%" .. ch
			else
				parts[#parts + 1] = ch
			end
			i = i + 1
		end
	end
	return "^" .. table.concat(parts) .. "$", kinds
end

local function kill_amount(text)
	if secret(text) or type(text) ~= "string" then return nil end
	for index = 1, #KILL_TEXT do
		local pattern, kinds = pattern_from(_G[KILL_TEXT[index]])
		if pattern then
			local captures = { text:match(pattern) }
			if captures[1] ~= nil then
				for kind_index, kind in ipairs(kinds) do
					if kind == "d" then
						local amount = tonumber(captures[kind_index])
						if amount and amount >= 1 and amount % 1 == 0 then return amount end
						return nil
					end
				end
			end
		end
	end
end

local function window(buckets, now, span)
	local from = now - span
	local totals = {
		total = 0, quest = 0, kill = 0, other = 0, unsorted = 0, levels = 0,
		gap = false, split = false, started = nil,
	}
	for key, row in pairs(buckets) do
		local minute = tonumber(key)
		if minute and minute >= from then
			totals.total = totals.total + row.total
			totals.quest = totals.quest + row.quest
			totals.kill = totals.kill + row.kill
			totals.other = totals.other + row.other
			totals.unsorted = totals.unsorted + row.unsorted
			totals.levels = totals.levels + row.levels
			if row.gap then totals.gap = true end
			if row.split or row.unsorted > 0 then totals.split = true end
			if row.total > 0 and row.started and (not totals.started or row.started < totals.started) then
				totals.started = row.started
			end
		end
	end
	return totals
end

local function digits(value)
	if type(BreakUpLargeNumbers) == "function" then
		local text = BreakUpLargeNumbers(value)
		if type(text) == "string" and not secret(text) and text ~= "" then return text end
	end
	local text = tostring(value)
	local grouped = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if grouped:sub(1, 1) == "," then grouped = grouped:sub(2) end
	return grouped
end

local function headline(name, totals)
	local line = name .. "  " .. digits(totals.total)
	if totals.levels == 1 then
		line = line .. "   1 level"
	elseif totals.levels > 1 then
		line = line .. "   " .. digits(totals.levels) .. " levels"
	end
	if totals.gap then line = line .. "   XP incomplete" end
	return line
end

local function split_line(totals)
	if totals.total <= 0 then return nil end
	local parts = {}
	if totals.quest > 0 then parts[#parts + 1] = "Quests " .. digits(totals.quest) end
	if totals.kill > 0 then parts[#parts + 1] = "Kills " .. digits(totals.kill) end
	if totals.other > 0 then parts[#parts + 1] = "Other " .. digits(totals.other) end
	if totals.unsorted > 0 then parts[#parts + 1] = "Unsorted " .. digits(totals.unsorted) end
	if #parts == 0 then return nil end
	local line = "  " .. table.concat(parts, "   ")
	if totals.split then line = line .. "   XP incomplete" end
	return line
end

local function rested_line(bar)
	if type(GetXPExhaustion) ~= "function" then return nil end
	local rested = GetXPExhaustion()
	if secret(rested) then return nil end
	rested = plain_number(rested)
	if rested == nil or rested <= 0 then return "Not rested" end
	if rested % 1 ~= 0 or type(bar) ~= "table" or bar.xp_max < 1 then return nil end
	local levels = math.floor(rested / bar.xp_max)
	local remainder = rested % bar.xp_max
	if levels >= 1 and remainder == 0 then
		return levels == 1 and "Rested 1 level" or "Rested " .. digits(levels) .. " levels"
	end
	if levels >= 1 then
		local phrase = levels == 1 and "1 level" or digits(levels) .. " levels"
		return "Rested " .. phrase .. " and " .. digits(remainder)
	end
	return "Rested " .. digits(remainder)
end

local function pace_line(hour, now, bar)
	if hour.total <= 0 or not hour.started or type(bar) ~= "table" or bar.xp_max < 1 or bar.xp >= bar.xp_max then return nil end
	local span = now - hour.started
	if span < 60 then return nil end
	local seconds = (bar.xp_max - bar.xp) / (hour.total / span)
	if seconds < 90 then return "About a minute to this level" end
	if seconds < 90 * 60 then
		local minutes = math.floor(seconds / 60 + 0.5)
		if minutes < 2 then minutes = 2 end
		return "About " .. minutes .. " minutes to this level"
	end
	local hours = math.floor(seconds / 3600 + 0.5)
	if hours < 2 then hours = 2 end
	return "About " .. hours .. " hours to this level"
end

local function render(hour, day, now, bar)
	local lines = { headline("Hour", hour) }
	local hour_split = split_line(hour)
	if hour_split then lines[#lines + 1] = hour_split end
	lines[#lines + 1] = headline("Day", day)
	local day_split = split_line(day)
	if day_split then lines[#lines + 1] = day_split end
	local foot = {}
	local rested = rested_line(bar)
	local pace = pace_line(hour, now, bar)
	if rested then foot[#foot + 1] = rested end
	if pace then foot[#foot + 1] = pace end
	if #foot > 0 then lines[#lines + 1] = table.concat(foot, "   ") end
	return lines, #foot > 0 and table.concat(foot, "   ") or nil
end

function experience.report()
	local current_session = current()
	if not current_session then return nil end
	local now = server_now()
	if not now or not current_session.baseline then return { ready = false, lines = {} } end
	local reading = read_bar()
	local bar = type(reading) == "table" and reading or nil
	-- The open island asks several times a second. Within one second and one
	-- ledger revision the answer is the same, and so is the bar it was drawn from.
	local rested = type(GetXPExhaustion) == "function" and plain_number(GetXPExhaustion()) or "x"
	local signature = now .. ":" .. (current_session.rev or 0) .. ":" .. rested .. ":" .. (bar and (bar.level .. "/" .. bar.xp .. "/" .. bar.xp_max) or "none")
	if current_session.report_signature == signature then return current_session.report end
	local hour = window(current_session.buckets, now, HOUR)
	local day = window(current_session.buckets, now, DAY)
	local lines, footer = render(hour, day, now, bar)
	local report = { ready = true, hour = hour, day = day, lines = lines, footer = footer }
	current_session.report_signature, current_session.report = signature, report
	return report
end

-- The same figures as a small table for the open island: a row per slice with
-- an hour and a day column, then one footer line for rested and pace.
function experience.table()
	local report = experience.report()
	if not report or not report.ready then return nil end
	local hour, day = report.hour, report.day
	local rows = { { "Total", digits(hour.total), digits(day.total) } }
	local function slice(name, a, b)
		if a > 0 or b > 0 then rows[#rows + 1] = { name, digits(a), digits(b) } end
	end
	slice("Quests", hour.quest, day.quest)
	slice("Kills", hour.kill, day.kill)
	slice("Other", hour.other, day.other)
	slice("Unsorted", hour.unsorted, day.unsorted)
	slice("Levels", hour.levels, day.levels)
	local footer = report.footer
	if hour.gap or day.gap or hour.split or day.split then
		footer = (footer and footer .. "   " or "") .. "XP incomplete"
	end
	return { rows = rows, footer = footer }
end

function experience.lines()
	local report = experience.report()
	if not report then return {} end
	return report.lines
end

function experience.on_event(event, ...)
	if event == "QUEST_TURNED_IN" then
		local current_session = current()
		if not current_session then return end
		local _, xp = ...
		if secret(xp) then current_session.blind = true; return end
		local amount = whole(xp)
		if amount and amount >= 1 then note(current_session, "quest", amount) end
		return
	end
	if event == "CHAT_MSG_COMBAT_XP_GAIN" then
		local current_session = current()
		if not current_session then return end
		local text = ...
		if secret(text) then current_session.blind = true; return end
		local amount = kill_amount(text)
		if amount then note(current_session, "kill", amount) end
		return
	end
	if event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
		sample()
	end
end

-- The island reads report() and table() while this option is on, and passes
-- its events here.
Everlook.module.extend("smart_island", {
	id = "experience", addon = addon_name, order = 100,
	options = {
		feed_experience = { name = "Experience detail", default = false, description = "On the open Island, lists experience from the last hour and the last day, and names how much came from quest turn-ins, kills, and everything else. The closed capsule stays a level chip, nothing is listed until the experience bar has been read once, the first look is not counted, rested experience is shown when the client gives a whole amount and no rested bonus says Not rested, an estimate of time to this level appears only after a minute of gains and stays off when the bar is full or you are at the level cap, a missing reading or a skipped level is marked incomplete, a reading the client hides or the first gain after a reload lists any part that is not a turn-in or a kill as Unsorted and marks that line incomplete, and turning this off hides the lines while Smart island keeps counting.", presets = { Quiet = false, Standard = false, Informative = true } },
	},
	sections = { { name = "Activity", keys = { "feed_experience" }, before = "source_repair" } },
})
