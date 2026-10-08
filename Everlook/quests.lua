local _, Everlook = ...

Everlook.quests = {}

local ROLE_GIVER = 1
local ROLE_ENDER = 2
local ROLE_ACCEPTED = 3
local ROLE_POI = 4

local function public(value)
	if Everlook.world.usable(value) then
		return value
	end
end

local function escape_word(word)
	return (word:gsub("(%W)", "%%%1"))
end

local function ci_pattern(word)
	local parts = {}
	for i = 1, #word do
		local c = word:sub(i, i)
		local lower, upper = c:lower(), c:upper()
		if lower ~= upper then
			parts[#parts + 1] = "[" .. upper .. lower .. "]"
		else
			parts[#parts + 1] = escape_word(c)
		end
	end
	return table.concat(parts)
end

-- The player name and class are compiled into a pattern on every quest text.
-- Those two words do not change, so the pattern is kept.
local word_patterns = {}

local function replace_word(text, word, token)
	if type(text) ~= "string" or type(word) ~= "string" or word == "" then
		return text
	end
	local pattern = word_patterns[word]
	if not pattern then
		pattern = "%f[%a]" .. ci_pattern(word) .. "%f[%A]"
		word_patterns[word] = pattern
	end
	return (text:gsub(pattern, token))
end

local function templatize(text)
	text = public(text)
	if type(text) ~= "string" or text == "" then
		return text
	end
	local name = public(UnitName and UnitName("player"))
	local class
	if UnitClass then
		class = public(UnitClass("player"))
	end
	text = replace_word(text, name, "$n")
	text = replace_word(text, class, "$c")
	return text
end

local function here(role)
	local location = Everlook.location.player()
	if not location then
		return nil
	end
	location.role = role
	location.seen = 1
	return location
end

local function npc_here()
	local guid = UnitGUID and UnitGUID("npc")
	local id = Everlook.npcs.creature_id(guid)
	if not id then
		return nil
	end
	return {
		type = "npc",
		id = id,
		name = public(UnitName and UnitName("npc")),
	}
end

local function object_here()
	local guid = UnitGUID and UnitGUID("npc")
	local id = Everlook.world.guid_id(guid, "GameObject")
	if not id then
		return nil
	end
	return {
		type = "object",
		id = id,
		name = public(UnitName and UnitName("npc")),
	}
end

local function starter()
	return npc_here() or object_here()
end

local function reward_items(kind)
	local count_fn = kind == "choice" and GetNumQuestChoices or GetNumQuestRewards
	if not count_fn or not GetQuestItemInfo then
		return nil
	end
	local count = public(count_fn())
	if type(count) ~= "number" or count < 1 then
		return nil
	end
	local items = {}
	for index = 1, count do
		local name, _, quantity, _, _, itemId = GetQuestItemInfo(kind, index)
		itemId = public(itemId)
		if not itemId and GetQuestItemLink then
			itemId = Everlook.items.id_from_link(GetQuestItemLink(kind, index))
		end
		if itemId then
			items[#items + 1] = {
				id = itemId,
				quantity = public(quantity),
				name = public(name),
			}
			Everlook.items.record(itemId, "quest", public(name))
		end
	end
	if #items == 0 then
		return nil
	end
	return items
end

local function required_items()
	if type(GetNumQuestItems) ~= "function" or type(GetQuestItemInfo) ~= "function" then
		return nil
	end
	local count = public(GetNumQuestItems())
	if type(count) ~= "number" or count < 1 then
		return nil
	end
	local items = {}
	for index = 1, count do
		local name, _, quantity, _, _, itemId = GetQuestItemInfo("required", index)
		itemId = public(itemId)
		if not itemId and GetQuestItemLink then
			itemId = Everlook.items.id_from_link(GetQuestItemLink("required", index))
		end
		if type(itemId) == "number" and itemId > 0 then
			name = public(name)
			items[#items + 1] = {
				id = itemId,
				quantity = public(quantity),
				name = name,
			}
			Everlook.items.record(itemId, "quest", name)
		end
	end
	if #items == 0 then
		return nil
	end
	return items
end

local function faction_name(id)
	local reader = C_Reputation and C_Reputation.GetFactionDataByID or GetFactionInfoByID
	if type(reader) ~= "function" then
		return nil
	end
	local ok, info = pcall(reader, id)
	if not ok then
		return nil
	end
	local name = type(info) == "table" and info.name or info
	name = public(name)
	if type(name) == "string" and name ~= "" then
		return name
	end
end

local function reward_reputations()
	if type(GetNumQuestLogRewardFactions) ~= "function" or type(GetQuestLogRewardFactionInfo) ~= "function" then
		return nil
	end
	local ok, count = pcall(GetNumQuestLogRewardFactions)
	count = ok and public(count) or nil
	if type(count) ~= "number" or count <= 0 or count ~= math.floor(count) then
		return nil
	end
	local list = {}
	local seen = {}
	for index = 1, count do
		local read_ok, first, second, third = pcall(GetQuestLogRewardFactionInfo, index)
		if read_ok then
			local faction_id, amount
			if type(first) == "number" and type(second) == "number" then
				faction_id, amount = first, second
			elseif type(second) == "number" and type(third) == "number" then
				amount, faction_id = second, third
			end
			faction_id = public(faction_id)
			amount = public(amount)
			if type(faction_id) == "number" and faction_id > 0 and faction_id == math.floor(faction_id) and type(amount) == "number" and amount ~= 0 and amount == math.floor(amount) and not seen[faction_id] then
				seen[faction_id] = true
				list[#list + 1] = { factionId = faction_id, amount = amount }
				local name = type(first) == "string" and public(first) or faction_name(faction_id)
				if type(name) == "string" and name ~= "" then
					Everlook.world.store("factions", { id = faction_id, name = name })
				end
			end
		end
	end
	if #list == 0 then
		return nil
	end
	return list
end

function Everlook.quests.rewards()
	local packed = {}
	if GetRewardMoney then
		packed.money = public(GetRewardMoney())
	end
	if GetRewardXP then
		packed.experience = public(GetRewardXP())
	end
	packed.items = reward_items("reward")
	packed.choices = reward_items("choice")
	packed.reputations = reward_reputations()
	if not packed.money and not packed.experience and not packed.items and not packed.choices and not packed.reputations then
		return nil
	end
	return packed
end

local function objectives_from(list)
	if type(list) ~= "table" then
		return nil
	end
	local objectives = {}
	for i = 1, #list do
		local objective = list[i]
		if type(objective) == "table" then
			local kind = public(objective.type)
			local objectId = public(objective.objectID or objective.id)
			if kind == "item" and type(objectId) == "number" and objectId > 0 then
				Everlook.items.record(objectId, "quest")
			end
			objectives[#objectives + 1] = {
				type = kind,
				id = objectId,
				numRequired = public(objective.numRequired),
				text = public(objective.text),
			}
		end
	end
	if #objectives == 0 then
		return nil
	end
	return objectives
end

local function objectives_for(id)
	if not C_QuestLog or not C_QuestLog.GetQuestObjectives then
		return nil
	end
	return objectives_from(C_QuestLog.GetQuestObjectives(id))
end

-- Level, required level, suggested group size, side, tag, and ui map do not change
-- once the client has them. A miss stays uncached so a later load can still fill the row.
local known_tag = {}
local known_side = {}
local known_level = {}
local known_required = {}
local known_group = {}
local known_map = {}

local function quest_type(id)
	local cached = known_tag[id]
	if cached ~= nil then
		return cached
	end
	local reader = C_QuestLog and C_QuestLog.GetQuestTagInfo or GetQuestTagInfo
	if type(reader) ~= "function" then
		return nil
	end
	local ok, info = pcall(reader, id)
	if not ok then
		return nil
	end
	local tag = info
	if type(info) == "table" then
		tag = public(info.tagID or info.tagId)
	else
		tag = public(info)
	end
	if type(tag) ~= "number" or tag <= 0 or tag ~= math.floor(tag) then
		return nil
	end
	known_tag[id] = tag
	return tag
end

local function quest_side(id)
	local cached = known_side[id]
	if cached ~= nil then
		return cached
	end
	if type(GetQuestFactionGroup) ~= "function" then
		return nil
	end
	local ok, side = pcall(GetQuestFactionGroup, id)
	if not ok then
		return nil
	end
	side = public(side)
	if side == 1 or side == 2 then
		known_side[id] = side
		return side
	end
	return nil
end

local function cached_query(cache, id, reader, minimum)
	local cached = cache[id]
	if cached ~= nil then
		return cached
	end
	if type(reader) ~= "function" then
		return nil
	end
	local value = public(reader(id))
	if type(value) ~= "number" or value < minimum or value ~= math.floor(value) then
		return nil
	end
	cache[id] = value
	return value
end

local function quest_frequency(value)
	value = public(value)
	if type(value) ~= "number" then
		return nil
	end
	local frequency = Enum and Enum.QuestFrequency
	if type(frequency) == "table" then
		if value == frequency.Daily then
			return "daily"
		end
		if value == frequency.Weekly then
			return "weekly"
		end
		return nil
	end
	if value == 1 then
		return "daily"
	end
	if value == 2 then
		return "weekly"
	end
	return nil
end

local function title_for(id, title)
	title = public(title)
	if type(title) == "string" and title ~= "" then
		return title
	end
	if C_QuestLog and C_QuestLog.GetTitleForQuestID then
		title = public(C_QuestLog.GetTitleForQuestID(id))
		if type(title) == "string" and title ~= "" then
			return title
		end
	end
end

-- The row store templatizes these strings. Doing it here scans the text twice.
local function log_line(value)
	value = public(value)
	if type(value) == "string" and value ~= "" then
		return value
	end
end

local function log_text(index)
	index = public(index)
	if type(index) ~= "number" then
		return nil, nil, nil
	end
	local description, objectives
	if GetQuestLogQuestText then
		local ok, first, second = pcall(GetQuestLogQuestText, index)
		if ok then
			description = log_line(first)
			objectives = log_line(second)
		end
	end
	local completion
	if type(GetQuestLogCompletionText) == "function" then
		local ok, text = pcall(GetQuestLogCompletionText, index)
		if ok then
			completion = log_line(text)
		end
	end
	return description, objectives, completion
end

local requested_maps = {}
local waiting = {}

local function line_info(id, maps)
	local info = C_QuestLine.GetQuestLineInfo(id)
	if type(info) == "table" then
		return info
	end
	if type(maps) == "table" then
		for i = 1, #maps do
			info = C_QuestLine.GetQuestLineInfo(id, maps[i])
			if type(info) == "table" then
				return info
			end
		end
	elseif C_Map and C_Map.GetBestMapForUnit then
		local mapId = public(C_Map.GetBestMapForUnit("player"))
		if type(mapId) == "number" then
			info = C_QuestLine.GetQuestLineInfo(id, mapId)
		end
	end
	return info
end

-- The line's id and name, as a quest row stores them. The name can be missing.
local function line_of(info)
	local lineId = public(info.questLineID)
	if type(lineId) ~= "number" or lineId <= 0 then
		return nil
	end
	local name = public(info.questLineName)
	if type(name) ~= "string" or name == "" then
		name = nil
	end
	return { id = lineId, name = name }
end

local function line_ids(id, maps)
	if not C_QuestLine or not C_QuestLine.GetQuestLineInfo or not C_QuestLine.GetQuestLineQuests then
		return nil
	end
	local info = line_info(id, maps)
	if type(info) ~= "table" then
		return nil
	end
	local line = line_of(info)
	if not line then
		return nil
	end
	local lineId = line.id
	local ids = C_QuestLine.GetQuestLineQuests(lineId)
	if type(ids) ~= "table" then
		return nil
	end
	local list = {}
	for i = 1, #ids do
		local questId = public(ids[i])
		if type(questId) == "number" and questId > 0 then
			list[#list + 1] = questId
		end
	end
	if #list == 0 then
		return nil
	end
	return list, line
end

-- The next quest offered right after a turn-in continues the chain. Classic
-- does not return quest lines from C_QuestLine, so the handoff is the link.
local handoff_id
local handoff_at
local HANDOFF_WINDOW = 20

function Everlook.quests.note_turned_in(id)
	id = public(id)
	if type(id) ~= "number" or id <= 0 then
		return
	end
	handoff_id = id
	if type(GetTime) == "function" then
		handoff_at = public(GetTime())
	else
		handoff_at = 0
	end
end

function Everlook.quests.followup_requires(id)
	id = public(id)
	local previous = handoff_id
	if type(previous) ~= "number" or type(id) ~= "number" or previous == id then
		return nil
	end
	local now = handoff_at
	if type(GetTime) == "function" then
		now = public(GetTime()) or now
	end
	if type(handoff_at) == "number" and type(now) == "number" and (now - handoff_at) > HANDOFF_WINDOW then
		handoff_id = nil
		return nil
	end
	handoff_id = nil
	return { previous }
end

local loading_announced = false

local function waiting_left()
	local count = 0
	for _ in pairs(waiting) do
		count = count + 1
	end
	return count
end

local function announce_loading()
	if loading_announced or not Everlook.say then
		return
	end
	loading_announced = true
	Everlook.say("Loading quest data.")
end

local function announce_loaded()
	if not loading_announced or waiting_left() > 0 or not Everlook.say then
		return
	end
	loading_announced = false
	Everlook.say("Quest data loaded.")
end

-- A quest queued from a line keeps that line until its title loads.
local waiting_lines = {}

local function queue_quest(id, requires, line)
	if waiting[id] ~= nil then
		return
	end
	waiting[id] = requires or true
	waiting_lines[id] = line
	announce_loading()
	if C_QuestLog and C_QuestLog.RequestLoadQuestByID then
		C_QuestLog.RequestLoadQuestByID(id)
	end
end

-- A line's ids stay put once every quest on it has a title. Later progress
-- updates must not walk it again or rerecord the earlier quests.
local line_known = {}

local function remember_line(id, maps)
	local cached = line_known[id]
	if cached ~= nil then
		if cached == false then
			return nil
		end
		return cached
	end
	local ids, line = line_ids(id, maps)
	if not ids then
		return nil
	end
	local requires
	local pending = false
	local found = false
	local resolved = {}
	for i = 1, #ids do
		local questId = ids[i]
		local previous
		if i > 1 then
			previous = { ids[i - 1] }
		end
		resolved[i] = previous or false
		if questId == id then
			found = true
			requires = previous
		else
			local title = title_for(questId)
			if title then
				Everlook.quests.record(questId, "chain", {
					title = title,
					requires = previous,
					questLine = line,
					skipLine = true,
				})
			else
				queue_quest(questId, previous, line)
				pending = true
			end
		end
	end
	if found and not pending then
		for i = 1, #ids do
			if line_known[ids[i]] == nil then
				line_known[ids[i]] = resolved[i]
			end
		end
	end
	return requires, line
end

local pending_starters = {}
local pending_required = {}

local function remember_entry(bucket, questId, entry)
	if type(questId) ~= "number" or type(entry) ~= "table" or type(entry.id) ~= "number" then
		return
	end
	local list = bucket[questId]
	if not list then
		list = {}
		bucket[questId] = list
	end
	for i = 1, #list do
		if list[i].id == entry.id then
			if type(entry.quantity) == "number" then
				list[i].quantity = entry.quantity
			end
			if type(entry.name) == "string" and entry.name ~= "" then
				list[i].name = entry.name
			end
			return
		end
	end
	list[#list + 1] = entry
end

local function append_starters(first, second)
	local merged = {}
	local seen = {}
	local function add(list)
		if type(list) ~= "table" then
			return
		end
		for i = 1, #list do
			local endpoint = list[i]
			if type(endpoint) == "table" and type(endpoint.id) == "number" then
				local key = tostring(endpoint.type or "") .. ":" .. endpoint.id
				if not seen[key] then
					seen[key] = true
					merged[#merged + 1] = endpoint
				end
			end
		end
	end
	add(first)
	add(second)
	if #merged == 0 then
		return nil
	end
	return merged
end

function Everlook.quests.note_item_starter(questId, itemId)
	questId = public(questId)
	itemId = public(itemId)
	if type(questId) ~= "number" or type(itemId) ~= "number" or itemId <= 0 then
		return
	end
	remember_entry(pending_starters, questId, { type = "item", id = itemId })
	Everlook.quests.record(questId, "item", { skipLine = true })
end

function Everlook.quests.note_required_item(questId, itemId, quantity, name)
	questId = public(questId)
	itemId = public(itemId)
	if type(questId) ~= "number" or type(itemId) ~= "number" or itemId <= 0 then
		return
	end
	remember_entry(pending_required, questId, {
		id = itemId,
		quantity = public(quantity),
		name = public(name),
	})
	Everlook.items.record(itemId, "quest", public(name))
	Everlook.quests.record(questId, "item", { skipLine = true })
end

function Everlook.quests.record(id, source, extra)
	id = public(id)
	if type(id) ~= "number" then
		return
	end
	extra = extra or {}
	if extra.requiredItems == nil and (source == "giver" or source == "progress" or source == "complete") then
		extra.requiredItems = required_items()
	end
	if type(extra.requiredItems) == "table" then
		for i = 1, #extra.requiredItems do
			remember_entry(pending_required, id, extra.requiredItems[i])
		end
	end
	local title = title_for(id, extra.title)
	if not title then
		queue_quest(id)
		return
	end
	local objectives = extra.keepObjectives and extra.objectives or objectives_for(id)
	local row = {
		id = id,
		title = title,
		sources = { source },
		objectives = objectives,
	}
	if C_QuestLog then
		row.level = cached_query(known_level, id, C_QuestLog.GetQuestDifficultyLevel, 1)
		row.requiredLevel = cached_query(known_required, id, C_QuestLog.GetRequiredLevel, 0)
		row.suggestedGroup = cached_query(known_group, id, C_QuestLog.GetSuggestedGroupSize, 0)
	end
	local side = quest_side(id)
	if side then
		row.factionSide = side
	end
	local tag = quest_type(id)
	if tag then
		row.questType = tag
	end
	if type(extra.frequency) == "string" and extra.frequency ~= "" then
		row.frequency = extra.frequency
	end
	if extra.description then
		row.description = templatize(extra.description)
	end
	if extra.objectiveText then
		row.objectiveText = templatize(extra.objectiveText)
	end
	if extra.progressText then
		row.progressText = templatize(extra.progressText)
	end
	if extra.completionText then
		row.completionText = templatize(extra.completionText)
	end
	if extra.rewards then
		row.rewards = extra.rewards
	end
	if extra.giverId then
		row.giverId = extra.giverId
	end
	if extra.turnInId then
		row.turnInId = extra.turnInId
	end
	local starters = append_starters(extra.starters, pending_starters[id])
	if starters then
		row.starters = starters
	end
	if type(pending_required[id]) == "table" and #pending_required[id] > 0 then
		row.requiredItems = pending_required[id]
	end
	if extra.enders then
		row.enders = extra.enders
	end
	if extra.location then
		row.locations = { extra.location }
		row.mapId = extra.location.mapId
	elseif C_QuestLog then
		row.mapId = cached_query(known_map, id, C_QuestLog.GetQuestUiMapID, 1)
	end
	local line = extra.questLine
	if type(extra.requires) == "table" and #extra.requires > 0 then
		row.requires = extra.requires
	elseif not extra.skipLine then
		local requires, walked = remember_line(id)
		if type(requires) == "table" and #requires > 0 then
			row.requires = requires
		end
		line = line or walked
	end
	if type(line) == "table" then
		row.questLineId = line.id
		row.questLineName = line.name
	end
	Everlook.world.store("quests", row)
end

local function scan_map(mapId)
	if type(mapId) ~= "number" or not C_QuestLine or not C_QuestLine.GetAvailableQuestLines then
		return false
	end
	local requested = false
	if C_QuestLine.RequestQuestLinesForMap and not requested_maps[mapId] then
		requested_maps[mapId] = true
		requested = true
		C_QuestLine.RequestQuestLinesForMap(mapId)
	end
	local lines = C_QuestLine.GetAvailableQuestLines(mapId)
	if type(lines) ~= "table" then
		return requested
	end
	for i = 1, #lines do
		local line = lines[i]
		local questId = type(line) == "table" and public(line.questID) or nil
		if type(questId) == "number" and questId > 0 then
			Everlook.quests.record(questId, "chain", {
				title = public(line.questName),
				questLine = line_of(line),
			})
		end
	end
	return requested
end

local function scan_completed()
	if not C_QuestLog or not C_QuestLog.GetAllCompletedQuestIDs then
		return
	end
	local ids = C_QuestLog.GetAllCompletedQuestIDs()
	if type(ids) ~= "table" then
		return
	end
	for i = 1, #ids do
		local questId = public(ids[i])
		if type(questId) == "number" and questId > 0 then
			Everlook.quests.record(questId, "completed")
		end
	end
end

-- Quest log events repeat while the log is unchanged. Once a quest's text is
-- in hand, the steady scan skips it while its objectives and completion still
-- match. A quest-line request for this map, or a snapshot that could not be
-- read, forces another pass.
-- false means the cached counts still match, so the steady scan allocates nothing.
local seen_progress = {}
local seen_map
local lines_pending = {}
local progress_scratch = {}

local function progress_snapshot(questId)
	if type(questId) ~= "number" or not C_QuestLog or type(C_QuestLog.GetQuestObjectives) ~= "function" then
		return nil
	end
	local list = C_QuestLog.GetQuestObjectives(questId)
	if type(list) ~= "table" then
		return nil
	end
	local n = 0
	for i = 1, #list do
		local objective = list[i]
		if type(objective) == "table" then
			if (objective.numFulfilled ~= nil and public(objective.numFulfilled) == nil)
				or (objective.numRequired ~= nil and public(objective.numRequired) == nil)
				or (objective.finished ~= nil and public(objective.finished) == nil) then
				return nil
			end
			local have = public(objective.numFulfilled)
			local need = public(objective.numRequired)
			local base = n * 3
			progress_scratch[base + 1] = have ~= nil and have or false
			progress_scratch[base + 2] = need ~= nil and need or false
			progress_scratch[base + 3] = objective.finished and true or false
			n = n + 1
		end
	end
	local complete = false
	if type(C_QuestLog.IsComplete) == "function" then
		local ok, value = pcall(C_QuestLog.IsComplete, questId)
		if ok and value == true then
			complete = true
		end
	end
	local prev = seen_progress[questId]
	local same = type(prev) == "table" and prev.n == n and prev.complete == complete
	if same then
		for i = 1, n * 3 do
			if prev[i] ~= progress_scratch[i] then
				same = false
				break
			end
		end
	end
	if same then
		return false
	end
	local snap = { n = n, complete = complete }
	for i = 1, n * 3 do
		snap[i] = progress_scratch[i]
	end
	-- The log is about to store this quest. Hand it the list already read
	-- so the record does not call GetQuestObjectives again.
	return snap, objectives_from(list)
end

local function text_seen(value)
	return type(value) == "string" and value ~= ""
end

local function scan_log()
	if not C_QuestLog or not C_QuestLog.GetNumQuestLogEntries or not C_QuestLog.GetInfo then
		return
	end
	local count = public(C_QuestLog.GetNumQuestLogEntries())
	if type(count) ~= "number" then
		return
	end
	local mapId
	if C_Map and C_Map.GetBestMapForUnit then
		mapId = public(C_Map.GetBestMapForUnit("player"))
	end
	local changed = false
	local refresh_lines = type(mapId) == "number" and lines_pending[mapId] or false
	-- GetInfo builds a full quest record, headers included. The id is enough
	-- while the cached progress still matches. A change, a snapshot that could
	-- not be read, or a quest-line request for this map reads the record again.
	local read_id = C_QuestLog.GetQuestIDForLogIndex
	local id_only = type(read_id) == "function"
	for index = 1, count do
		local questId, info
		if id_only then
			questId = public(read_id(index))
			if type(questId) ~= "number" or questId <= 0 or questId ~= math.floor(questId) then
				questId = nil
			end
		else
			info = C_QuestLog.GetInfo(index)
			if type(info) == "table" and not info.isHeader then
				questId = public(info.questID)
				if type(questId) ~= "number" then
					questId = nil
				end
			else
				info = nil
			end
		end
		if questId then
			local progress, objectives = progress_snapshot(questId)
			if refresh_lines or progress ~= false then
				if not info then
					info = C_QuestLog.GetInfo(index)
				end
				if type(info) == "table" and not info.isHeader then
					local recordedId = public(info.questID)
					if type(recordedId) ~= "number" then
						recordedId = questId
					end
					local description, objectiveText, completionText = log_text(public(info.questLogIndex) or index)
					local extra = {
						title = info.title,
						description = description,
						objectiveText = objectiveText,
						completionText = completionText,
						frequency = quest_frequency(info.frequency),
					}
					if type(progress) == "table" then
						extra.objectives = objectives
						extra.keepObjectives = true
					end
					Everlook.quests.record(recordedId, "quest-log", extra)
					if type(progress) == "table" and (text_seen(description) or text_seen(objectiveText) or text_seen(completionText)) then
						seen_progress[recordedId] = progress
					end
					changed = true
				end
			end
		end
	end
	if not changed and seen_map == mapId and not refresh_lines then
		return
	end
	seen_map = mapId
	local requested = scan_map(mapId)
	if type(mapId) == "number" then
		lines_pending[mapId] = requested or nil
	end
	if C_QuestLog.GetQuestsOnMap and type(mapId) == "number" then
		local pins = C_QuestLog.GetQuestsOnMap(mapId)
		if type(pins) == "table" then
			for i = 1, #pins do
				local pin = pins[i]
				if type(pin) == "table" and pin.questID then
					local location = Everlook.location.player()
					if location and pin.x and pin.y then
						location.x = math.floor(pin.x * 1000 + 0.5)
						location.y = math.floor(pin.y * 1000 + 0.5)
						location.role = ROLE_POI
					end
					Everlook.quests.record(pin.questID, "poi", { location = location })
				end
			end
		end
	end
end

function Everlook.quests.scan()
	scan_log()
end

-- Log updates keep firing after the log has settled. The first burst scans on
-- the next tick; later bursts share one scan per second. Without a timer or a
-- usable clock, each update scans immediately.
local SCAN_WINDOW = 1
local scanned_at = 0
local log_waiting = false

local function run_scan()
	log_waiting = false
	if type(GetTime) == "function" then
		local now = GetTime()
		if type(now) == "number" then
			scanned_at = now
		end
	end
	scan_log()
end

local function queue_log()
	if log_waiting then
		return
	end
	if type(GetTime) ~= "function" or not C_Timer or type(C_Timer.After) ~= "function" then
		scan_log()
		return
	end
	local now = GetTime()
	if type(now) ~= "number" then
		scan_log()
		return
	end
	local delay = 0
	if scanned_at ~= 0 and (now - scanned_at) < SCAN_WINDOW then
		delay = SCAN_WINDOW - (now - scanned_at)
		if delay < 0.05 then
			delay = 0.05
		end
	end
	log_waiting = true
	C_Timer.After(delay, run_scan)
end

local function player_maps()
	local maps = {}
	local seen = {}
	local mapId
	if C_Map and C_Map.GetBestMapForUnit then
		mapId = public(C_Map.GetBestMapForUnit("player"))
	end
	while type(mapId) == "number" and mapId > 0 and not seen[mapId] do
		seen[mapId] = true
		maps[#maps + 1] = mapId
		local parent
		if C_Map and C_Map.GetMapInfo then
			local info = C_Map.GetMapInfo(mapId)
			parent = type(info) == "table" and public(info.parentMapID) or nil
		end
		if type(parent) ~= "number" or parent <= 0 then
			break
		end
		mapId = parent
	end
	return maps
end

local function append_quest_id(list, seen, id)
	id = public(id)
	if type(id) ~= "number" or id <= 0 or id ~= math.floor(id) or seen[id] then
		return
	end
	seen[id] = true
	list[#list + 1] = id
end

local function logged_quest_ids()
	local list = {}
	local seen = {}
	if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
		local count = public(C_QuestLog.GetNumQuestLogEntries())
		local read_id = C_QuestLog and C_QuestLog.GetQuestIDForLogIndex
		if type(count) == "number" then
			for index = 1, count do
				local questId
				if type(read_id) == "function" then
					questId = read_id(index)
				elseif C_QuestLog.GetInfo then
					local info = C_QuestLog.GetInfo(index)
					if type(info) == "table" and not info.isHeader then
						questId = info.questID
					end
				end
				append_quest_id(list, seen, questId)
			end
		end
	end
	if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
		local ids = C_QuestLog.GetAllCompletedQuestIDs()
		if type(ids) == "table" then
			for i = 1, #ids do
				append_quest_id(list, seen, ids[i])
			end
		end
	end
	return list
end

-- The eager scan asks for quest lines, then reads them. The map reply is
-- not ready in the same call, so one follow-up runs half a second later.
-- Without a timer that follow-up does not run.
local chain_queued = false

local function queue_chain_scan()
	if chain_queued or not C_Timer or type(C_Timer.After) ~= "function" then
		return
	end
	chain_queued = true
	if Everlook.say then
		Everlook.say("Quest lines requested. Checking again shortly.")
	end
	C_Timer.After(0.5, function()
		chain_queued = false
		if Everlook.say then
			Everlook.say("Checking quest chains again.")
		end
		Everlook.quests.scan_chains()
		if Everlook.say then
			Everlook.say("Quest chain check finished.")
		end
	end)
end

function Everlook.quests.scan_chains()
	local maps = player_maps()
	local requested = false
	for i = 1, #maps do
		if scan_map(maps[i]) then
			requested = true
		end
	end
	local ids = logged_quest_ids()
	for i = 1, #ids do
		local questId = ids[i]
		local requires, line = remember_line(questId, maps)
		if (type(requires) == "table" and #requires > 0) or line then
			Everlook.quests.record(questId, "chain", {
				requires = requires,
				questLine = line,
				skipLine = true,
			})
		end
	end
	return requested
end

function Everlook.quests.scan_wide()
	scan_log()
	scan_completed()
	if Everlook.quests.scan_chains() then
		queue_chain_scan()
	end
end

local function detail_extra(role, text_key, text)
	local who = starter()
	local extra = {
		title = public(GetTitleText and GetTitleText()),
		rewards = Everlook.quests.rewards(),
		location = here(role),
	}
	extra[text_key] = public(text)
	if who then
		-- The giver and turn-in ids carry no type, so only a creature may use them. An object says what it is in
		-- starters and enders, and an id here would read as an NPC with the same number.
		local is_creature = who.type ~= "object"
		if role == ROLE_GIVER then
			extra.giverId = is_creature and who.id or nil
			extra.starters = { who }
		else
			extra.turnInId = is_creature and who.id or nil
			extra.enders = { who }
		end
		if who.type == "object" then
			Everlook.objects.record(UnitGUID("npc"), "quest", who.name)
		else
			Everlook.npcs.record("npc", "quest")
		end
	end
	return extra
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("QUEST_DETAIL")
frame:RegisterEvent("QUEST_PROGRESS")
frame:RegisterEvent("QUEST_COMPLETE")
frame:RegisterEvent("QUEST_TURNED_IN")
frame:RegisterEvent("QUEST_ACCEPTED")
frame:RegisterEvent("QUEST_LOG_UPDATE")
frame:RegisterEvent("QUEST_DATA_LOAD_RESULT")
frame:SetScript("OnEvent", function(_, event, first, second)
	if event == "QUEST_DATA_LOAD_RESULT" then
		local questId = public(first)
		local loaded = public(second)
		local requires = questId and waiting[questId] or nil
		if questId and loaded == true and requires ~= nil and title_for(questId) then
			waiting[questId] = nil
			local extra = { skipLine = true, questLine = waiting_lines[questId] }
			waiting_lines[questId] = nil
			if type(requires) == "table" then
				extra.requires = requires
			end
			Everlook.quests.record(questId, "chain", extra)
			announce_loaded()
		end
		return
	end
	if event == "QUEST_LOG_UPDATE" then
		queue_log()
		return
	end
	local id = public(GetQuestID and GetQuestID())
	if event == "QUEST_TURNED_IN" then
		Everlook.quests.note_turned_in(first)
		return
	end
	if event == "QUEST_ACCEPTED" then
		id = public(first) or id
		local extra = {
			location = here(ROLE_ACCEPTED),
			giverId = npc_here() and npc_here().id or nil,
		}
		extra.requires = Everlook.quests.followup_requires(id)
		Everlook.quests.record(id, "accepted", extra)
		return
	end
	if not id then
		return
	end
	if event == "QUEST_DETAIL" then
		local extra = detail_extra(ROLE_GIVER, "description", GetQuestText and GetQuestText())
		extra.requires = Everlook.quests.followup_requires(id)
		Everlook.quests.record(id, "giver", extra)
		if GetObjectiveText then
			Everlook.quests.record(id, "giver", { objectiveText = GetObjectiveText() })
		end
	elseif event == "QUEST_PROGRESS" then
		Everlook.quests.record(id, "progress", detail_extra(ROLE_ENDER, "progressText", GetProgressText and GetProgressText()))
	elseif event == "QUEST_COMPLETE" then
		Everlook.quests.record(id, "complete", detail_extra(ROLE_ENDER, "completionText", GetRewardText and GetRewardText()))
		Everlook.quests.note_turned_in(id)
	end
end)
