local _, Everlook = ...

Everlook.probe = {}

-- `/everlook probe` answers, in one go, the questions about this client that decide what Everlook may build:
-- which map and quest functions exist, what they return, and whether the death events fire and what they carry.
-- It only reads. The answers go to chat and to `EverlookDB.probe`, so they can be read back from the saved file.
local LISTEN_SECONDS = 120
local EVENTS = { "UNIT_DIED", "PARTY_KILL", "GOSSIP_SHOW", "QUEST_GREETING" }

local function has(path)
	local value = _G
	for part in path:gmatch("[^.]+") do
		if type(value) ~= "table" then return false end
		value = value[part]
	end
	return type(value) == "function"
end

local function secret(value)
	return type(issecretvalue) == "function" and issecretvalue(value) or false
end

-- Facts that need no waiting: which functions exist and what a harmless call returns.
function Everlook.probe.facts()
	local facts = {}
	for _, name in ipairs({
		"C_Map.GetMapRectOnMap", "C_Map.GetMapArtID", "C_Map.GetMapArtLayers", "C_MapExplorationInfo.GetExploredMapTextures",
		"GetQuestLogRewardXP", "CanLootUnit", "C_GossipInfo.GetAvailableQuests", "C_QuestLog.IsQuestFlaggedCompleted",
		"C_QuestLog.GetQuestDifficultyLevel", "UnitIsTapDenied",
	}) do
		facts[#facts + 1] = name .. ": " .. (has(name) and "present" or "missing")
	end
	if has("C_QuestLog.IsQuestFlaggedCompleted") then
		local ok, answer = pcall(C_QuestLog.IsQuestFlaggedCompleted, 1)
		facts[#facts + 1] = "IsQuestFlaggedCompleted(1): " .. (ok and type(answer) .. " " .. tostring(answer) or "error")
	end
	if has("GetQuestLogRewardXP") then
		local ok, total, base = pcall(GetQuestLogRewardXP, 1)
		facts[#facts + 1] = "GetQuestLogRewardXP(1): " .. (ok and (type(total) .. ", " .. type(base)) or "error")
	end
	return facts
end

-- What one death event carried: its name and the type of what came with it, never the value.
function Everlook.probe.describe(event, first)
	return event .. " " .. (secret(first) and "secret" or type(first))
end

-- What a giver's window offers, as types and numbers only: how many quests, and the highest level among them next to
-- the player's, which says whether the list holds quests above the player's level. No title and no id is kept.
function Everlook.probe.offers()
	if not (C_GossipInfo and type(C_GossipInfo.GetAvailableQuests) == "function") then return "offers: no list on this client" end
	local ok, list = pcall(C_GossipInfo.GetAvailableQuests)
	if not ok or type(list) ~= "table" then return "offers: the list could not be read" end
	local highest, completed = nil, 0
	for _, quest in ipairs(list) do
		local level = type(quest) == "table" and quest.questLevel
		if type(level) == "number" and not secret(level) and (not highest or level > highest) then highest = level end
		local quest_id = type(quest) == "table" and quest.questID
		if type(quest_id) == "number" and not secret(quest_id) and C_QuestLog and type(C_QuestLog.IsQuestFlaggedCompleted) == "function"
			and C_QuestLog.IsQuestFlaggedCompleted(quest_id) == true then
			completed = completed + 1
		end
	end
	local player = type(UnitLevel) == "function" and UnitLevel("player") or nil
	return ("offers: %d available, highest level %s, player level %s, %d of them flagged completed"):format(
		#list, tostring(highest), type(player) == "number" and not secret(player) and tostring(player) or "?", completed)
end

local function say(line)
	if Everlook.say then Everlook.say(line) end
end

-- The checks that are done by touching something, one answer each, run at once and kept like the rest.
-- `combat` is for use in combat: whether the panel can be closed and a frame's click pass-through set there.
-- `lines` is for the first minute after a cold start: whether a line limited to one line has any width.
-- `quests` is for a look at the quest log list: whether the game already puts a level in front of a title.
local SUBJECTS = {}

local function keep(subject, lines)
	EverlookDB = EverlookDB or {}
	EverlookDB.probe = EverlookDB.probe or {}
	EverlookDB.probe[subject] = { lines = lines, build = type(GetBuildInfo) == "function" and select(2, GetBuildInfo()) or nil }
	for index, line in ipairs(lines) do
		if index > 8 then break end
		if Everlook.say then Everlook.say(line) end
	end
	if #lines > 8 and Everlook.say then Everlook.say(("(%d more lines are in the saved file)"):format(#lines - 8)) end
	if Everlook.say then Everlook.say("Saved under EverlookDB.probe." .. subject .. ".") end
end

function SUBJECTS.combat()
	local lines = { "in combat: " .. tostring(type(InCombatLockdown) == "function" and InCombatLockdown() or "unknown") }
	if type(SettingsPanel) == "table" and type(SettingsPanel.IsShown) == "function" and SettingsPanel:IsShown() then
		local ok, why = pcall(HideUIPanel, SettingsPanel)
		lines[#lines + 1] = "close the settings panel: " .. (ok and "allowed" or ("refused, " .. tostring(why):sub(1, 120)))
	else
		lines[#lines + 1] = "close the settings panel: open it first (/everlook), then run this again"
	end
	if type(CreateFrame) == "function" then
		local ok, why = pcall(function()
			local frame = CreateFrame("Button")
			frame:SetPassThroughButtons("LeftButton")
			frame:SetPassThroughButtons()
		end)
		lines[#lines + 1] = "set a frame's click pass-through: " .. (ok and "allowed" or ("refused, " .. tostring(why):sub(1, 120)))
	end
	return lines
end

function SUBJECTS.lines()
	local holder = type(CreateFrame) == "function" and CreateFrame("Frame") or nil
	local text = holder and holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	if not text then return { "lines: no frames on this client" } end
	text:SetMaxLines(1)
	text:SetText("A line limited to one line")
	local limited = text:GetStringWidth()
	text:SetMaxLines(0)
	local free = text:GetStringWidth()
	return {
		("one-line text width right after setting it: %s (without the limit %s)"):format(tostring(limited), tostring(free)),
		(type(limited) == "number" and limited > 0) and "the limit left the text with a width" or "the limit left the text blank: this is what the bug looks like",
	}
end

-- The map functions the zone labels and the map pins use, and the fields they return, for the map the player is on.
-- Only field names and types are kept.
local function shape(value)
	if type(value) ~= "table" then return type(value) end
	local keys = {}
	for key, item in pairs(value) do
		if type(key) == "string" then keys[#keys + 1] = key .. ":" .. type(item) end
	end
	table.sort(keys)
	return "{" .. table.concat(keys, ", ") .. "}"
end

-- `areas` is the name the game gives each area id: the names of the pieces a zone's map is drawn from are these names run
-- together, so the pictures can be found in the game's own files.
function SUBJECTS.areas()
	if not (C_Map and C_Map.GetAreaInfo) then return { "areas: this client has no C_Map.GetAreaInfo" } end
	local lines = { "area names, one line each as id|name" }
	for id = 1, 30000 do
		local ok, name = pcall(C_Map.GetAreaInfo, id)
		if ok and type(name) == "string" and name ~= "" and not secret(name) then lines[#lines + 1] = id .. "|" .. name end
	end
	lines[1] = ("%d area names, one line each as id|name"):format(#lines - 1)
	return lines
end

function SUBJECTS.maps()
	local lines = {}
	local map_id = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	if type(map_id) ~= "number" then return { "maps: the client gave no map for the player; stand in a zone and run this again" } end
	lines[#lines + 1] = "map type of this map: " .. tostring(C_Map.GetMapInfo and (C_Map.GetMapInfo(map_id) or {}).mapType)
	local function try(label, fn, ...)
		if type(fn) ~= "function" then lines[#lines + 1] = label .. ": missing"; return nil end
		local ok, a, b = pcall(fn, ...)
		if not ok then lines[#lines + 1] = label .. ": errored, " .. tostring(a):sub(1, 100); return nil end
		lines[#lines + 1] = label .. ": " .. shape(a) .. (b ~= nil and (", " .. shape(b)) or "")
		return a
	end
	local art = try("GetMapArtID", C_Map and C_Map.GetMapArtID, map_id)
	local layers = try("GetMapArtLayers", C_Map and C_Map.GetMapArtLayers, map_id)
	if type(layers) == "table" and layers[1] then lines[#lines + 1] = "first art layer: " .. shape(layers[1]) end
	local textures = try("GetMapArtLayerTextures", C_Map and C_Map.GetMapArtLayerTextures, map_id, 1)
	if type(textures) == "table" then lines[#lines + 1] = "textures in layer 1: " .. #textures end
	local explored = try("GetExploredMapTextures", C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures, map_id)
	if type(explored) == "table" and explored[1] then lines[#lines + 1] = "first explored entry: " .. shape(explored[1]) end
	if type(explored) == "table" then lines[#lines + 1] = "explored entries: " .. #explored end
	lines[#lines + 1] = "GetMapRectOnMap on a child zone: " .. (function()
		local children = C_Map.GetMapChildrenInfo and C_Map.GetMapChildrenInfo(map_id, 3)
		local child = type(children) == "table" and children[1]
		if not child then return "this map has no zone children (try a continent map)" end
		local ok, left, right, top, bottom = pcall(C_Map.GetMapRectOnMap, child.mapID, map_id)
		return ok and type(left) == "number" and (("%.3f %.3f %.3f %.3f"):format(left, right, top, bottom)) or "no rectangle"
	end)()
	lines[#lines + 1] = "map art id: " .. tostring(type(art) == "number" and art or "none")
	return lines
end

function SUBJECTS.quests()
	local scroll = _G.QuestScrollFrame
	local pool = type(scroll) == "table" and scroll.titleFramePool
	-- What the game's data says, which needs no quest log open: whether it has a function that puts a level in front of
	-- a title, and whether the titles it hands out already start with one.
	local data = {}
	local prefix = type(_G.GetQuestTitlePrefix) == "function"
	data[#data + 1] = "GetQuestTitlePrefix: " .. (prefix and "present" or "missing")
	if C_QuestLog and type(C_QuestLog.GetNumQuestLogEntries) == "function" and type(C_QuestLog.GetInfo) == "function" then
		local entries, with_bracket = 0, 0
		for index = 1, C_QuestLog.GetNumQuestLogEntries() do
			local info = C_QuestLog.GetInfo(index)
			local title = type(info) == "table" and not info.isHeader and info.title
			if type(title) == "string" and not secret(title) then
				entries = entries + 1
				if title:find("^%[%d+%]") then with_bracket = with_bracket + 1 end
			end
		end
		data[#data + 1] = ("quests in the log by the data: %d, %d of their titles start with a bracketed number"):format(entries, with_bracket)
	end
	if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then
		data[#data + 1] = "quest log list: not drawn yet; open the quest log and run this again for what the list shows"
		return data
	end
	local total, bracketed = 0, 0
	for button in pool:EnumerateActive() do
		local text = type(button) == "table" and type(button.Text) == "table" and button.Text:GetText()
		if type(text) == "string" and not secret(text) then
			total = total + 1
			if text:find("^%[%d+%]") then bracketed = bracketed + 1 end
		end
	end
	local quest_levels = Everlook.module and Everlook.module.enabled and Everlook.module.enabled("quest_levels")
	data[#data + 1] = ("quest log list: %d titles, %d start with a bracketed number"):format(total, bracketed)
	data[#data + 1] = "Everlook's Quest levels is " .. (quest_levels and "ON, so those may be its own: turn it off and run this again to see the game's" or "off, so those are the game's own")
	data[#data + 1] = "colorblind mode: " .. tostring(type(GetCVar) == "function" and GetCVar("colorblindMode") or "unknown")
	return data
end

function Everlook.probe.run(subject)
	if type(subject) == "string" and subject ~= "" then
		local check = SUBJECTS[subject:lower()]
		if not check then
			if Everlook.say then Everlook.say("Probe what? combat, lines, quests, maps, areas, or nothing for the death, giver and function check.") end
			return
		end
		keep(subject:lower(), check())
		return
	end
	local report = Everlook.probe.facts()
	local seen = {}
	local frame = CreateFrame("Frame")
	for _, event in ipairs(EVENTS) do
		local ok = pcall(frame.RegisterEvent, frame, event)
		report[#report + 1] = "Register " .. event .. ": " .. (ok and "accepted" or "refused")
	end
	-- A death: was it the player's target, and a second later does the game say the corpse can be looted?
	-- Only booleans are kept, never the id, so two runs can be compared without a creature in them.
	local function watch_death(guid)
		if type(guid) ~= "string" or secret(guid) then return end
		local targeted = type(UnitGUID) == "function" and UnitGUID("target") == guid
		if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" or type(CanLootUnit) ~= "function" then return end
		C_Timer.After(1, function()
			local ok, has, can = pcall(CanLootUnit, guid)
			local line = ("death: target at death %s, CanLootUnit %s (hasLoot %s, canLoot %s)"):format(
				tostring(targeted), ok and "answered" or "errored", ok and tostring(has) or "?", ok and tostring(can) or "?")
			seen[line] = (seen[line] or 0) + 1
		end)
	end
	-- Whose GUID PARTY_KILL carries: the creature that died, or the one who killed it. Only the kind of GUID, never the
	-- GUID, is kept, and whether it was also a UNIT_DIED GUID in the same run.
	local died_guids, party_guids, kinds = {}, {}, {}
	frame:SetScript("OnEvent", function(_, event, first)
		if type(first) == "string" and not secret(first) then
			if event == "UNIT_DIED" then died_guids[first] = true end
			if event == "PARTY_KILL" then
				party_guids[first] = true
				local kind = first:match("^(%a+)%-") or "other"
				kinds[kind] = (kinds[kind] or 0) + 1
			end
		end
		if event == "UNIT_DIED" then watch_death(first) end
		local line = (event == "GOSSIP_SHOW" or event == "QUEST_GREETING") and Everlook.probe.offers() or Everlook.probe.describe(event, first)
		seen[line] = (seen[line] or 0) + 1
	end)
	for _, line in ipairs(report) do say(line) end
	say("Listening " .. LISTEN_SECONDS .. " seconds. Kill something, alone and in a group, and open a quest giver's window.")
	local function finish()
		frame:UnregisterAllEvents()
		local lines = {}
		for line, count in pairs(seen) do lines[#lines + 1] = line .. " x" .. count end
		table.sort(lines)
		if #lines == 0 then lines[1] = "No death event was seen." end
		local party_total, matched = 0, 0
		for guid in pairs(party_guids) do
			party_total = party_total + 1
			if died_guids[guid] then matched = matched + 1 end
		end
		if party_total > 0 then
			local names = {}
			for kind, count in pairs(kinds) do names[#names + 1] = kind .. " x" .. count end
			table.sort(names)
			lines[#lines + 1] = ("PARTY_KILL guid is a creature that also died in UNIT_DIED: %d of %d (kinds: %s)"):format(matched, party_total, table.concat(names, ", "))
		end
		EverlookDB = EverlookDB or {}
		EverlookDB.probe = { facts = report, events = lines, build = select(2, GetBuildInfo()) }
		for _, line in ipairs(lines) do say(line) end
		say("Saved under EverlookDB.probe.")
	end
	if type(C_Timer) == "table" and type(C_Timer.After) == "function" then C_Timer.After(LISTEN_SECONDS, finish) else finish() end
end
