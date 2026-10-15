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

function Everlook.probe.run()
	local report = Everlook.probe.facts()
	local seen = {}
	local frame = CreateFrame("Frame")
	for _, event in ipairs(EVENTS) do
		local ok = pcall(frame.RegisterEvent, frame, event)
		report[#report + 1] = "Register " .. event .. ": " .. (ok and "accepted" or "refused")
	end
	frame:SetScript("OnEvent", function(_, event, first)
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
		EverlookDB = EverlookDB or {}
		EverlookDB.probe = { facts = report, events = lines, build = select(2, GetBuildInfo()) }
		for _, line in ipairs(lines) do say(line) end
		say("Saved under EverlookDB.probe.")
	end
	if type(C_Timer) == "table" and type(C_Timer.After) == "function" then C_Timer.After(LISTEN_SECONDS, finish) else finish() end
end
