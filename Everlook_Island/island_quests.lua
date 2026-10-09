local Everlook = Everlook

-- Private quest context for Smart island. This observes the native log; it
-- never changes tracking, accepts quests or drives navigation.
local quests = {}
Everlook.island_quests = quests

-- Plain call counters for development: /dump Everlook.island_stats shows how
-- often the Island repainted, scanned the quest log, polled feeds and aimed.
local stats = { paint = 0, quest_scan = 0, feed_tick = 0, aim = 0 }
Everlook.island_stats = stats
local records, order, baseline = {}, {}, {}
local selected, suggested, pinned, recent, recent_at, scanned
local suggested_ready
local scan_generation = 0
local skipped = {}
local ui
local options = {}
local distances = {}
local pin_cache = {}
local seen_level
-- What the player did that might be worth pinning: { kind, id, at }. The pin
-- suggestion feed takes these.
local activity = {}
-- Pin suggestions take this list, and their addon may not be loaded, so it
-- keeps only the latest few.
local ACTIVITY_MAX = 32
local function note_activity(item)
	activity[#activity + 1] = item
	if #activity > ACTIVITY_MAX then table.remove(activity, 1) end
end

local function public(value)
	return not (issecretvalue and issecretvalue(value))
end

local function number(value)
	return public(value) and type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function quest_id(value)
	return number(value) and value >= 1 and value <= 9007199254740991 and value % 1 == 0
end

local function text(value, fallback)
	if public(value) and type(value) == "string" and value ~= "" then return value:sub(1, 1024) end
	return fallback
end

local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, entry in pairs(value) do result[key] = copy(entry) end
	return result
end

local function now()
	local value = GetTime and GetTime()
	return number(value) and value or 0
end

local function distance(id, force)
	local time = now()
	local cached = distances[id]
	if not force and cached and time - cached.time < 1 then return cached.value end
	distances[id] = { time = time }
	if not C_QuestLog or not C_QuestLog.GetDistanceSqToQuest then return end
	local squared, local_quest = C_QuestLog.GetDistanceSqToQuest(id)
	if public(local_quest) and local_quest == true and number(squared) and squared >= 0 then
		distances[id].value = math.sqrt(squared)
		return distances[id].value
	end
end

local function objectives(id, watched, time)
	local rows = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(id)
	local result, previous, current = {}, baseline[id], {}
	if not public(rows) or type(rows) ~= "table" then return result end
	for index, row in ipairs(rows) do
		if public(row) and type(row) == "table" then
			local fulfilled, required, finished = row.numFulfilled, row.numRequired, row.finished
			fulfilled = number(fulfilled) and fulfilled >= 0 and fulfilled or nil
			required = number(required) and required > 0 and required or nil
			if not public(finished) or type(finished) ~= "boolean" then finished = nil end
			local fraction = fulfilled and required and math.min(1, fulfilled / required) or nil
			if finished == true then fraction = 1 end
			current[index] = { count = fulfilled, finished = finished }
			local before = previous and previous[index]
			if watched and before and ((fulfilled and before.count and fulfilled > before.count) or (finished == true and before.finished == false)) then
				recent, recent_at = id, time
				if id ~= pinned then note_activity({ kind = "progress", id = id, at = time }) end
			end
			result[#result + 1] = { text = text(row.text, "Objective unavailable"), fulfilled = fulfilled, required = required, finished = finished, progress = fraction }
		end
	end
	baseline[id] = current
	return result
end

local function weight(key, default, low, high)
	local value = options[key]
	if not number(value) then return default end
	return math.max(low, math.min(high, value))
end

local function rank(record, player_level)
	local cost = record.distance and record.distance / 100 * weight("distance_weight", 1, 0.25, 4) or 0
	if not record.ready and record.level and player_level then
		local difference = record.level - player_level
		cost = cost + weight("level_weight", 2, 0, 4) * math.abs(difference) + 8 * math.max(difference - 2, 0)
	end
	record.score = cost
	record.known_level = record.ready or (record.level ~= nil and player_level ~= nil)
end

local function better(a, b)
	if (a.distance ~= nil) ~= (b.distance ~= nil) then return a.distance ~= nil end
	if a.known_level ~= b.known_level then return a.known_level end
	if a.score ~= b.score then return a.score < b.score end
	return a.id < b.id
end

function quests.reset()
	options, distances, skipped, pin_cache = {}, {}, {}, {}
	if ui then ui.page = 1 end
	records, order, baseline = {}, {}, {}
	selected, suggested, pinned, recent, recent_at, scanned, suggested_ready = nil, nil, nil, nil, nil, nil, nil
	activity = {}
	scan_generation = 0
end

local function next_candidate()
	for index = 1, #order do
		local record = order[index]
		if not skipped[record.id] then return record end
	end
end

local function island_options()
	local ready = Everlook.module.get("smart_island", "feed_quest_ready")
	local next_quest = Everlook.module.get("smart_island", "feed_quest_next")
	local completion = Everlook.module.get("smart_island", "source_quest_completion")
	return {
		enabled = Everlook.module.get("smart_island", "quest_context"),
		observe = ready or next_quest or completion,
		planning = Everlook.module.get("smart_island", "quest_plan"),
		feed_planning = next_quest,
		recent = Everlook.module.get("smart_island", "quest_recent"),
		nearby = Everlook.module.get("smart_island", "quest_nearby"),
		distance_weight = Everlook.module.get("smart_island", "quest_distance_weight"),
		level_weight = Everlook.module.get("smart_island", "quest_level_weight"),
	}
end

local function scan(force)
	local settings = island_options()
	options = settings
	if not settings.enabled and not settings.observe then quests.reset(); return end
	local time = now()
	if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
		local id = C_SuperTrack.GetSuperTrackedQuestID()
		selected = quest_id(id) and id or nil
	end
	if not force and scanned and time - scanned < 3 then return end
	scanned = time
	stats.quest_scan = stats.quest_scan + 1
	local watched = {}
	if C_QuestLog and C_QuestLog.GetNumQuestWatches and C_QuestLog.GetQuestIDForQuestWatchIndex then
		local count = C_QuestLog.GetNumQuestWatches()
		if number(count) and count >= 0 and count <= 1000 then
			for index = 1, count do
				local id = C_QuestLog.GetQuestIDForQuestWatchIndex(index)
				if quest_id(id) then watched[id] = true end
			end
		end
	end
	local player_level = UnitLevel and UnitLevel("player")
	player_level = number(player_level) and player_level >= 1 and player_level or nil
	seen_level = player_level
	local next_records, next_order = {}, {}
	if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
		local count = C_QuestLog.GetNumQuestLogEntries()
		if number(count) and count >= 0 and count <= 1000 then
			local zone
			for index = 1, count do
				local info = C_QuestLog.GetInfo(index)
				-- The log groups quests under a zone heading, so the heading names where they are.
				if public(info) and type(info) == "table" and public(info.isHeader) and info.isHeader then zone = text(info.title, nil) end
				if public(info) and type(info) == "table" and quest_id(info.questID) and public(info.isHeader) and not info.isHeader then
					local id, level = info.questID, info.level
					local ready = C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(id)
					local record = { id = id, title = text(info.title, "Quest #" .. id), watched = watched[id] == true,
						level = number(level) and level >= 1 and level or nil,
						ready = public(ready) and ready == true, distance = distance(id, true), objectives = objectives(id, watched[id], time), zone = zone }
					rank(record, player_level)
					if not next_records[id] then next_records[id], next_order[#next_order + 1] = record, record end
				end
			end
		end
	end
	records, order = next_records, next_order
	for id in pairs(baseline) do if not records[id] then baseline[id], distances[id] = nil, nil end end
	for id in pairs(skipped) do if not records[id] then skipped[id] = nil end end
	if pinned and not records[pinned] then
		note_activity({ kind = "finished", id = pinned, at = time })
		pinned = nil
	end
	if recent and not records[recent] then recent, recent_at = nil, nil end
	table.sort(order, better)
	local planning = settings.planning or settings.feed_planning
	local best = next_candidate()
	local current = suggested and records[suggested]
	if not current or skipped[current.id] then current = nil end
	if not planning or not best then
		suggested, suggested_ready = nil, nil
	elseif not current or current.ready ~= suggested_ready or (best.id ~= current.id and better(best, current) and
		((best.distance ~= nil and current.distance == nil) or (best.known_level and not current.known_level) or best.score <= current.score * 0.8)) then
		suggested, suggested_ready = best.id, best.ready
	end
	scan_generation = scan_generation + 1
end

function quests.skip(id)
	if not quest_id(id) or not records[id] then return false end
	skipped[id] = true
	return true
end

function quests.release_skip(id)
	if not quest_id(id) or not skipped[id] then return false end
	skipped[id] = nil
	return true
end

function quests.suggestion()
	if not (options.planning or options.feed_planning) then return end
	local record = suggested and records[suggested]
	if not record or skipped[record.id] then return end
	return copy(record)
end

function quests.ready_list()
	local list = {}
	for index = 1, #order do
		if order[index].ready then list[#list + 1] = copy(order[index]) end
	end
	return list
end

local function context()
	if pinned and records[pinned] then return records[pinned], "Pinned" end
	if options.planning and suggested and records[suggested] then return records[suggested], "Suggested" end
	if options.recent and recent and recent_at and now() - recent_at < 15 and records[recent] then return records[recent], "Progressing" end
	if options.nearby then
		local nearest
		for _, record in pairs(records) do
			if record.watched and record.distance and (not nearest or record.distance < nearest.distance or (record.distance == nearest.distance and record.id < nearest.id)) then nearest = record end
		end
		if nearest then return nearest, "Nearby" end
	end
	return selected and records[selected], "Selected"
end

-- World x increases north and world y increases west
-- (C_Map.GetWorldPosFromMapPos, Elwynn uiMap 37). Facing and SetRotation
-- are radians counterclockwise from north, so the arrow turns by their
-- difference. A separation under a yard has no direction.
local function xy(position)
	if not public(position) or type(position) ~= "table" then return end
	local x, y
	if type(position.GetXY) == "function" then x, y = position:GetXY() else x, y = position.x, position.y end
	if number(x) and number(y) then return x, y end
end

local function world_of(map_id, position)
	if not C_Map or not C_Map.GetWorldPosFromMapPos or not number(map_id) then return end
	local x, y = xy(position)
	if not x then return end
	local point = position
	if not (number(position.x) and number(position.y)) then point = { x = x, y = y } end
	local continent, world = C_Map.GetWorldPosFromMapPos(map_id, point)
	local wx, wy = xy(world)
	if not number(continent) or not wx then return end
	return continent, wx, wy
end

function quests.bearing(player_x, player_y, target_x, target_y, facing)
	if not number(player_x) or not number(player_y) or not number(target_x) or not number(target_y) or not number(facing) then return end
	local north, west = target_x - player_x, target_y - player_y
	if west * west + north * north < 1 then return end
	local turn = math.pi * 2
	return (math.atan2(west, north) - facing + math.pi) % turn - math.pi
end

local function map_yards(map_id)
	if C_Map and C_Map.GetMapWorldSize then
		local width, height = C_Map.GetMapWorldSize(map_id)
		if number(width) and number(height) and width > 1 and height > 1 then return width, height end
	end
	return 4000, 4000
end

local function same_map_bearing(map_id, player_x, player_y, target_x, target_y, facing)
	if not number(player_x) or not number(player_y) or not number(target_x) or not number(target_y) then return end
	local width, height = map_yards(map_id)
	-- Map x grows east and map y grows south, so the north axis is -map y and the west axis is -map x.
	return quests.bearing(-player_y * height, -player_x * width, -target_y * height, -target_x * width, facing)
end

local function pin_on(quest_id, map_id)
	if not C_QuestLog or not C_QuestLog.GetQuestsOnMap or not number(map_id) then return end
	local pins = C_QuestLog.GetQuestsOnMap(map_id)
	if not public(pins) or type(pins) ~= "table" then return end
	for index = 1, #pins do
		local pin = pins[index]
		local id = public(pin) and type(pin) == "table" and pin.questID
		if number(id) and id == quest_id and number(pin.x) and number(pin.y) then
			return number(pin.mapID) and pin.mapID or map_id, pin.x, pin.y
		end
	end
end

local function parent_map(map_id)
	if not C_Map or not C_Map.GetMapInfo or not number(map_id) then return end
	local info = C_Map.GetMapInfo(map_id)
	if not public(info) or type(info) ~= "table" then return end
	local parent = info.parentMapID
	if number(parent) and parent > 0 and parent ~= map_id then return parent end
end

local function quest_point(quest_id, player_map)
	if C_QuestLog and C_QuestLog.GetNextWaypoint then
		local map_id, x, y = C_QuestLog.GetNextWaypoint(quest_id)
		if number(map_id) and number(x) and number(y) then return map_id, x, y end
	end
	local cached = pin_cache[quest_id]
	local time = now()
	if cached and time - cached.time < 1 then
		if cached.map then return cached.map, cached.x, cached.y end
		return
	end
	local map_id, guard = player_map, 0
	local found, x, y
	while map_id and guard < 6 do
		found, x, y = pin_on(quest_id, map_id)
		if found then break end
		map_id = parent_map(map_id)
		guard = guard + 1
	end
	pin_cache[quest_id] = { time = time, map = found, x = x, y = y }
	if found then return found, x, y end
end

function quests.direction(id)
	if not quest_id(id) or not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetPlayerMapPosition then return end
	local facing = GetPlayerFacing and GetPlayerFacing()
	if not number(facing) then return end
	local player_map = C_Map.GetBestMapForUnit("player")
	if not number(player_map) then return end
	local player_pos = C_Map.GetPlayerMapPosition(player_map, "player")
	local player_x, player_y = xy(player_pos)
	if not player_x then return end
	local map_id, x, y = quest_point(id, player_map)
	if not map_id then return end
	local player_continent, world_x, world_y = world_of(player_map, player_pos)
	local target_continent, target_x, target_y = world_of(map_id, { x = x, y = y })
	if number(player_continent) and player_continent == target_continent and world_x and target_x then
		return quests.bearing(world_x, world_y, target_x, target_y, facing)
	end
	if map_id == player_map then return same_map_bearing(map_id, player_x, player_y, x, y, facing) end
end

function quests.pin(id)
	if id == nil then pinned = nil; return true end
	if not quest_id(id) or not records[id] then return false end
	pinned = id
	return true
end

function quests.title(id)
	local record = quest_id(id) and records[id]
	return record and record.title or nil
end

function quests.present(request)
	local view = quests.view()
	local status = request and request.status
	local closed = request and request.closed
	local wide = Everlook.module.get("smart_island", "quest_title")
	local quest = not status and view and view.current
	local capsule_w, capsule_h = quests.capsule(view, closed and not status, wide == true, request and request.available, request and request.badge, request and request.reserve)
	local tooltip
	if status then
		tooltip = status.text .. (status.detail and "\n" .. status.detail or "")
	elseif quest then
		tooltip = quest.title .. "\n" .. quests.distance_text(quest)
	end
	local inspection_height = 0
	if request and request.visual_open then
		inspection_height = quests.inspection(view, true, request.content_width) or 0
	end
	quests.show_inspection(request and request.visual_open)
	return {
		quest = quest,
		capsule_w = capsule_w,
		capsule_h = capsule_h,
		tooltip = tooltip,
		status_closed = status and closed and true or false,
		inspection_height = inspection_height,
	}
end

-- A short mark for the once-a-second island tick. The closed chip cares about
-- the quest it is showing. The open list also cares that a full scan ran.
function quests.pulse(full)
	if not options.enabled then return nil end
	local current, why = context()
	local yards = -1
	if current then
		local value = distance(current.id)
		yards = number(value) and math.floor(value + 0.5) or -1
	end
	local progress = ""
	local objectives = current and current.objectives
	if type(objectives) == "table" then
		for index = 1, #objectives do
			local row = objectives[index]
			progress = progress .. ":" .. tostring(row.fulfilled or 0) .. (row.finished and "f" or "")
		end
	end
	local mark = (why or "") .. "\0" .. tostring(current and current.id or 0) .. "\0" .. yards
		.. "\0" .. (current and current.title or "") .. progress
	if full then mark = mark .. "\0" .. scan_generation end
	return mark
end

-- The painter reads the live records and never writes them. The distance sits on
-- a shallow copy so the ordered plan keeps the figure it was ranked with.
-- Pass copy_all for a view that outside readers may keep.
function quests.view(copy_all)
	if not options.enabled then return end
	local current, reason = context()
	local result = { current = current and { }, reason = reason, suggested = suggested, pinned = pinned, order = options.planning and order or {} }
	if current then
		for key, value in pairs(current) do result.current[key] = value end
		result.current.distance = distance(current.id)
	end
	if copy_all then
		result.current = copy(result.current)
		result.order = copy(result.order)
	end
	return result
end

-- Native presentation stays private too. The Island supplies its existing
-- font, surface, hover and control helpers so quest rows share the inbox.
local function call(object, method, ...)
	local fn = object and object[method]
	if type(fn) == "function" then return fn(object, ...) end
end

local function show_arrow(texture, angle)
	if angle then
		call(texture, "SetRotation", angle)
		call(texture, "Show")
	else
		call(texture, "Hide")
	end
end

function quests.aim()
	if not ui then return end
	stats.aim = stats.aim + 1
	local current = options.enabled and context()
	local angle = current and quests.direction(current.id)
	show_arrow(ui.arrow, angle)
	show_arrow(ui.heading_arrow, angle)
	call(ui.icon, angle and "Hide" or "Show")
end

-- Ten updates a second turn the arrow smoothly enough and halve the map calls.
local AIM_INTERVAL = 0.1

local function follow(frame)
	local wait = 0
	call(frame, "SetScript", "OnUpdate", function(_, elapsed)
		if not number(elapsed) then return end
		wait = wait + elapsed
		if wait < AIM_INTERVAL then return end
		wait = 0
		quests.aim()
	end)
end

function quests.distance_text(record)
	if record and record.distance then return "~" .. math.floor(record.distance + 0.5) .. " yd" end
	return "Distance unavailable"
end

local function reason(record)
	return (record.ready and "ready to turn in" or (record.level and "level " .. record.level or "level unavailable")) .. ", " .. quests.distance_text(record)
end

-- Where a quest is: its zone from the log, and how far it is.
function quests.where(record)
	local far = quests.distance_text(record)
	return record.zone and (record.zone .. ", " .. far) or far
end

-- Why the route puts a quest where it does, in the same terms the ranking
-- uses: ready to turn in, how close it is, how its level sits against yours.
function quests.why(record)
	local parts = {}
	if record.ready then parts[#parts + 1] = "ready to turn in" end
	if record.from_pin then
		parts[#parts + 1] = "about " .. math.floor(record.from_pin + 0.5) .. " yd from your pinned quest"
	elseif record.distance then
		local nearest = true
		for _, other in ipairs(order) do
			if other.id ~= record.id and not skipped[other.id] and other.distance and other.distance < record.distance then nearest = false; break end
		end
		if nearest then parts[#parts + 1] = "closest to you"
		elseif record.distance < 300 then parts[#parts + 1] = "close by" end
	else
		parts[#parts + 1] = "no distance known"
	end
	if not record.ready and record.level and seen_level then
		local difference = record.level - seen_level
		if math.abs(difference) <= 2 then parts[#parts + 1] = "level " .. record.level .. ", close to yours"
		elseif difference > 2 then parts[#parts + 1] = "level " .. record.level .. ", " .. difference .. " above you"
		else parts[#parts + 1] = "level " .. record.level .. ", " .. -difference .. " below you" end
	end
	if #parts == 0 then return "next on the list" end
	return table.concat(parts, "; ")
end

-- The island's feed addons hear every refresh. Only an unforced one, the
-- island's one-second beat, counts as a feed tick.
function quests.refresh(force)
	scan(force)
	if not force then stats.feed_tick = stats.feed_tick + 1 end
	for _, extension in ipairs(Everlook.module.extensions("smart_island")) do
		if extension.refresh then extension.refresh(force) end
	end
end

function quests.note_accepted(id)
	if quest_id(id) then note_activity({ kind = "accepted", id = id, at = now() }) end
end

function quests.record(id)
	local record = quest_id(id) and records[id]
	return record and copy(record) or nil
end

function quests.pinned_id()
	return pinned
end

-- Activity ready to act on. A quest just accepted is not in the scan until the
-- log updates, so it waits up to half a minute for its record.
function quests.take_activity()
	local ready, waiting = {}, {}
	local time = now()
	for _, item in ipairs(activity) do
		if item.kind == "finished" or records[item.id] then ready[#ready + 1] = item
		elseif time - item.at < 30 then waiting[#waiting + 1] = item end
	end
	activity = waiting
	return ready
end

-- Where a quest is on its continent, in world yards, or nil when the client
-- gives no waypoint or pin for it.
local function world_position(id)
	local player_map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	if not number(player_map) then return end
	local map_id, x, y = quest_point(id, player_map)
	if not map_id then return end
	local continent, world_x, world_y = world_of(map_id, { x = x, y = y })
	if continent then return continent, world_x, world_y end
end

local function level_cost(record)
	if record.ready or not record.level or not seen_level then return 0 end
	local difference = record.level - seen_level
	return weight("level_weight", 2, 0, 4) * math.abs(difference) + 8 * math.max(difference - 2, 0)
end

-- The next three quests after the current one. With a pin they are the quests
-- nearest to the pinned quest, so the route builds out from it; without one
-- they are the nearest to the player, already ranked by the scan. The second
-- value says which. Each record gets from_pin, its yards from the pinned quest.
function quests.route(view)
	local list = {}
	if not view then return list, false end
	local base = pinned and records[pinned]
	local built_from_pin = false
	local candidates = {}
	for _, record in ipairs(view.order) do
		record.from_pin = nil
		if not (view.current and view.current.id == record.id) and not skipped[record.id] and not (base and record.id == base.id) then
			candidates[#candidates + 1] = record
		end
	end
	if base then
		local continent, base_x, base_y = world_position(base.id)
		if continent then
			built_from_pin = true
			for _, record in ipairs(candidates) do
				local other, x, y = world_position(record.id)
				if other == continent then record.from_pin = math.sqrt((x - base_x) ^ 2 + (y - base_y) ^ 2) end
			end
			local function score(record)
				return record.from_pin / 100 * weight("distance_weight", 1, 0.25, 4) + level_cost(record)
			end
			table.sort(candidates, function(a, b)
				if (a.from_pin ~= nil) ~= (b.from_pin ~= nil) then return a.from_pin ~= nil end
				if a.from_pin and score(a) ~= score(b) then return score(a) < score(b) end
				return better(a, b)
			end)
		end
	end
	for index = 1, math.min(3, #candidates) do list[index] = candidates[index] end
	return list, built_from_pin
end

function quests.ensure_ui(adapter)
	if ui then return end
	ui = { adapter = adapter, page = 1, objectives = {}, meters = {}, plan = {}, segments = {} }
	ui.capsule = CreateFrame("Frame", "EverlookIslandQuestCapsule", adapter.root)
	call(ui.capsule, "EnableMouse", false)
	call(ui.capsule, "SetPoint", "TOPLEFT", adapter.root, "TOPLEFT", 0, 0)
	ui.icon = call(ui.capsule, "CreateTexture", nil, "OVERLAY")
	call(ui.icon, "SetAtlas", "questlog-questtypeicon-quest")
	call(ui.icon, "SetSize", 16, 16)
	call(ui.icon, "SetPoint", "TOPLEFT", ui.capsule, "TOPLEFT", 8, -8)
	ui.title = adapter.label(ui.capsule, "LEFT")
	call(ui.title, "SetPoint", "TOPLEFT", ui.capsule, "TOPLEFT", 30, -9)
	call(ui.title, "SetMaxLines", 1)
	ui.badge = adapter.label(ui.capsule, "RIGHT", true)
	call(ui.badge, "SetPoint", "TOPRIGHT", ui.capsule, "TOPRIGHT", -14, -9)
	call(ui.badge, "SetTextColor", 0.68, 0.46, 0.94, 1)
	call(ui.badge, "Hide")
	ui.distance = adapter.label(ui.capsule, "RIGHT", true)
	call(ui.distance, "SetPoint", "TOPRIGHT", ui.capsule, "TOPRIGHT", -18, -9)
	local function make_arrow(parent)
		local texture = call(parent, "CreateTexture", nil, "OVERLAY")
		call(texture, "SetTexture", "Interface\\AddOns\\Everlook_Island\\assets\\island_arrow.tga")
		call(texture, "SetVertexColor", 1, 0.86, 0.35)
		call(texture, "SetSize", 16, 16)
		call(texture, "SetSnapToPixelGrid", false)
		call(texture, "SetTexelSnappingBias", 0)
		call(texture, "Hide")
		return texture
	end
	ui.arrow = make_arrow(ui.capsule)
	call(ui.arrow, "SetPoint", "TOPLEFT", ui.capsule, "TOPLEFT", 8, -8)
	for index = 1, 10 do
		local segment = CreateFrame("StatusBar", nil, ui.capsule)
		call(segment, "EnableMouse", false)
		call(segment, "SetStatusBarTexture", "Interface\\AddOns\\Everlook_Island\\assets\\island_white.tga")
		call(segment, "SetStatusBarColor", 0.5, 0.9, 0.65, 1)
		call(segment, "SetMinMaxValues", 0, 1)
		local background = call(segment, "CreateTexture", nil, "BACKGROUND")
		call(background, "SetAllPoints", segment)
		call(background, "SetColorTexture", 1, 1, 1, 0.15)
		ui.segments[index] = segment
	end
	ui.panel = CreateFrame("Frame", "EverlookIslandQuestInspection", adapter.content)
	call(ui.panel, "EnableMouse", false)
	call(ui.panel, "SetPoint", "TOPLEFT", adapter.content, "TOPLEFT", 0, 0)
	ui.visual = adapter.visual(ui.panel, true)
	ui.heading_arrow = make_arrow(ui.visual)
	call(ui.heading_arrow, "SetPoint", "TOPRIGHT", ui.visual, "TOPRIGHT", -8, -12)
	ui.heading = adapter.label(ui.visual, "LEFT")
	ui.explanation = adapter.label(ui.visual, "LEFT", true)
	for index = 1, 20 do ui.objectives[index] = adapter.label(ui.visual, "LEFT", "text") end
	for index = 1, 20 do
		local track = call(ui.visual, "CreateTexture", nil, "BACKGROUND")
		call(track, "SetColorTexture", 1, 1, 1, 0.12)
		call(track, "Hide")
		local bar = CreateFrame("StatusBar", nil, ui.visual)
		call(bar, "EnableMouse", false)
		call(bar, "SetStatusBarTexture", "Interface\\AddOns\\Everlook_Island\\assets\\island_white.tga")
		call(bar, "SetMinMaxValues", 0, 1)
		call(bar, "Hide")
		ui.meters[index] = { track = track, bar = bar }
	end
	-- The two actions sit in the quests heading row, outside the card, so the card scrolls without them.
	ui.pin = adapter.link(adapter.head, "EverlookIslandPinQuest", "Pin quest", function()
		local view = quests.view()
		if view and view.current then adapter.pin(view.current.id) end
	end)
	ui.release = adapter.link(adapter.head, "EverlookIslandReleaseQuest", "Release pin", function() adapter.pin(nil) end)
	for _, link in ipairs({ ui.pin, ui.release }) do adapter.size_link(link, link.label.text) end
	ui.plan_heading = adapter.label(ui.visual, "LEFT", "heading")
	ui.plan_reason = adapter.label(ui.visual, "LEFT", "caption")
	for index = 1, 3 do
		local target = CreateFrame("Button", nil, ui.panel)
		call(target, "RegisterForClicks", "LeftButtonUp")
		local visual = adapter.visual(target, true)
		local node = { frame = target, visual = visual, title = adapter.label(visual, "LEFT", "text"), detail = adapter.label(visual, "LEFT", "caption") }
		call(target, "SetScript", "OnClick", function() if node.record then adapter.pin(node.record.id) end end)
		adapter.hover(target, node)
		adapter.controls[#adapter.controls + 1] = target
		ui.plan[index] = node
	end
	follow(ui.capsule)
	follow(ui.panel)
end

function quests.capsule(view, visible, wide, available, badge, reserve)
	if not ui then return end
	local current = view and view.current
	call(ui.capsule, visible and current and "Show" or "Hide")
	if not current then quests.aim(); return end
	local distance_text = current.distance and quests.distance_text(current) or ""
	call(ui.distance, "SetText", distance_text)
	local distance_width = call(ui.distance, "GetStringWidth") or 60
	-- Level and experience stay on the capsule as a badge at the right end.
	call(ui.badge, "SetText", badge or "")
	-- reserve is the room the unread count takes at the capsule's right end.
	reserve = reserve or 0
	call(ui.badge, "ClearAllPoints")
	call(ui.badge, "SetPoint", "TOPRIGHT", ui.capsule, "TOPRIGHT", -14 - reserve, -9)
	local badge_width = badge and badge ~= "" and ((call(ui.badge, "GetStringWidth") or 40) + 10) or 0
	call(ui.badge, badge_width > 0 and "Show" or "Hide")
	call(ui.distance, "ClearAllPoints")
	call(ui.distance, "SetPoint", "TOPRIGHT", ui.capsule, "TOPRIGHT", -18 - badge_width - reserve, -9)
	local width = math.min(available, wide and 300 + badge_width + reserve or math.max(64, distance_width + 50 + badge_width + reserve))
	call(ui.capsule, "SetSize", width, wide and 36 or 28)
	call(ui.title, "SetText", current.title)
	call(ui.title, "SetWidth", math.max(12, width - distance_width - badge_width - reserve - 56))
	call(ui.title, wide and "Show" or "Hide")
	local count = math.min(10, #current.objectives)
	for index, segment in ipairs(ui.segments) do
		local objective = current.objectives[index]
		local show = wide and index <= count and objective and objective.progress ~= nil
		call(segment, show and "Show" or "Hide")
		if show then
			local step = (width - 32) / count
			call(segment, "SetSize", math.max(1, step - 3), 4)
			call(segment, "ClearAllPoints")
			call(segment, "SetPoint", "TOPLEFT", ui.capsule, "TOPLEFT", 16 + (index - 1) * step, -27)
			call(segment, "SetValue", objective.progress)
		end
	end
	quests.aim()
	return width, wide and 36 or 28
end

local OBJECTIVES_SHOWN = 4

-- The game's own objective text usually carries its count ("0/1 Rifle"). Add
-- ours only when the text does not.
local function objective_text(objective)
	local text = objective.text
	if objective.fulfilled and objective.required and not text:find("%d+%s*/%s*%d+") then
		return text .. string.format("  %g/%g", objective.fulfilled, objective.required)
	end
	return text
end

-- Puts a label at `top` and returns where it ends. The caller adds the gap.
local function line(label, value, width, top)
	local edge = ui.adapter.space.edge
	call(label, "Show")
	call(label, "SetText", value)
	call(label, "SetWidth", width - 2 * edge)
	call(label, "ClearAllPoints")
	call(label, "SetPoint", "TOPLEFT", ui.visual, "TOPLEFT", edge, -top)
	return top + (call(label, "GetStringHeight") or 14)
end

-- The two pin actions, so the island can place the one that shows.
function quests.actions()
	return ui and { ui.pin, ui.release } or {}
end

function quests.inspection(view, visible, width)
	if not ui then return 0 end
	local adapter = ui.adapter
	local space, tones = adapter.space, adapter.tones
	local edge = space.edge
	call(ui.panel, visible and view and "Show" or "Hide")
	if not view then quests.aim(); return 0 end
	for _, label in ipairs(ui.objectives) do call(label, "Hide") end
	for _, meter in ipairs(ui.meters) do
		call(meter.track, "Hide")
		call(meter.bar, "Hide")
	end
	for _, node in ipairs(ui.plan) do call(node.frame, "Hide"); node.record = nil end
	for _, control in ipairs({ ui.pin, ui.release, ui.plan_heading, ui.plan_reason }) do call(control, "Hide") end
	local top, current = edge, view.current
	if current then
		-- The title leaves room for the arrow beside it.
		top = line(ui.heading, current.title, width - 22, top) + space.within
		top = line(ui.explanation, view.reason .. ", " .. reason(current), width, top) + space.near
		-- Four objectives fit in the card. Any more fold into one line.
		local shown = math.min(#current.objectives, #ui.objectives, OBJECTIVES_SHOWN)
		for index = 1, shown do
			local objective = current.objectives[index]
			-- A finished objective steps back, and only one still to do draws a fill.
			call(ui.objectives[index], "SetTextColor", unpack(objective.finished and tones.muted or tones.primary))
			top = line(ui.objectives[index], objective_text(objective), width, top)
			local meter = ui.meters[index]
			if objective.progress ~= nil and not objective.finished then
				top = top + space.within
				for _, part in ipairs({ meter.track, meter.bar }) do
					call(part, "ClearAllPoints")
					call(part, "SetPoint", "TOPLEFT", ui.visual, "TOPLEFT", edge, -top)
					call(part, "SetSize", width - 2 * edge, space.rail)
				end
				call(meter.track, "Show")
				call(meter.bar, "SetValue", objective.progress)
				call(meter.bar, "SetStatusBarColor", 0.68, 0.46, 0.94, 1)
				call(meter.bar, "Show")
				top = top + space.rail
			end
			top = top + space.near
		end
		local hidden = #current.objectives - shown
		if hidden > 0 then
			call(ui.objectives[shown + 1], "SetTextColor", unpack(tones.muted))
			top = line(ui.objectives[shown + 1], "+" .. hidden .. (hidden == 1 and " more objective" or " more objectives"), width, top) + space.near
		end
		call(view.pinned and ui.release or ui.pin, "Show")
	else
		top = line(ui.heading, "Select a quest in the tracker", width, top) + space.near
		call(ui.explanation, "Hide")
	end
	local route, from_pin = quests.route(view)
	if #route > 0 then
		-- A section gap from whatever is above, less the gap that line already left.
		top = top - space.near + space.section
		adapter.heading(ui.plan_heading, "Next up")
		call(ui.plan_heading, "Show")
		call(ui.plan_heading, "SetWidth", width - 2 * edge)
		call(ui.plan_heading, "ClearAllPoints")
		call(ui.plan_heading, "SetPoint", "TOPLEFT", ui.visual, "TOPLEFT", edge, -top)
		top = top + (call(ui.plan_heading, "GetStringHeight") or 12) + space.within
		top = line(ui.plan_reason, from_pin and "Nearest your pinned quest" or "Closest to you and matched to your level", width, top) + space.near
		for index, node in ipairs(ui.plan) do
			local record = route[index]
			if record then
				local where, why = quests.where(record), quests.why(record)
				node.record, node.tooltip = record, "Pin quest: " .. record.title .. "\n" .. where .. "\nWhy: " .. why
				call(node.title, "SetText", index .. ". " .. record.title)
				call(node.title, "SetWidth", width - 2 * edge)
				call(node.title, "SetMaxLines", 2)
				call(node.title, "SetPoint", "TOPLEFT", node.visual, "TOPLEFT", 0, 0)
				local title_height = call(node.title, "GetStringHeight") or 14
				call(node.detail, "SetText", record.ready and where .. ", ready to turn in" or where)
				call(node.detail, "SetWidth", width - 2 * edge)
				call(node.detail, "SetPoint", "TOPLEFT", node.visual, "TOPLEFT", 0, -title_height - space.within)
				local detail_height = call(node.detail, "GetStringHeight") or 12
				local height = title_height + space.within + detail_height
				call(node.frame, "SetSize", width - 2 * edge, height)
				call(node.frame, "ClearAllPoints")
				call(node.frame, "SetPoint", "TOPLEFT", ui.panel, "TOPLEFT", edge, -top)
				call(node.frame, "Show")
				top = top + height + space.near
			end
		end
	end
	top = top - space.near + edge
	call(ui.panel, "SetSize", width, top)
	quests.aim()
	return top
end

function quests.show_inspection(visible)
	if ui then call(ui.panel, visible and options.enabled and "Show" or "Hide") end
end
