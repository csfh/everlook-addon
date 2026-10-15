local _, Everlook = ...

Everlook.offers = {}

-- Whether a giver's window holds a quest it could have held, for players of each class, race and level band. The
-- shared catalog says which quests a creature gives. For each one the window could hold for this player (the level
-- is reached, the quest is not done or in the log, and what must come first is done), one more `opens` is counted,
-- and one more `offered` when the window held it. Nothing is said about why a quest is missing: the site only
-- reads the counters, and only where players of other classes were offered the quest in the same band
-- (docs/adr/0005-absence-is-counted-not-claimed.md). A client that cannot say whether a quest is done counts nothing.
local BAND = 5
local REPEAT_SECONDS = 60

local seen = {}
local row = { opens = 1, offered = 0 }

local function public(value)
	if Everlook.world.usable(value) then return value end
end

local function done(quest_id)
	local flagged = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
	if type(flagged) ~= "function" then return nil end
	local ok, answer = pcall(flagged, quest_id)
	if ok and Everlook.world.usable(answer) and type(answer) == "boolean" then return answer end
end

local function trait(read)
	if type(read) ~= "function" then return nil end
	local id = select(3, read("player"))
	id = public(id)
	return type(id) == "number" and id or nil
end

function Everlook.offers.window()
	if type(UnitGUID) ~= "function" or not (C_GossipInfo and C_GossipInfo.GetAvailableQuests) or not Everlook.data_pack then return end
	local guid = public(UnitGUID("npc"))
	local npc_id = guid and Everlook.npcs.creature_id(guid)
	local now = type(GetTime) == "function" and public(GetTime()) or nil
	if not npc_id or not now then return end
	if seen[guid] and now - seen[guid] < REPEAT_SECONDS then return end
	local data = Everlook.data_pack("quest offers")
	local givers = data and data.givers and data.givers(npc_id)
	if not givers then return end
	local class, race = trait(UnitClass), trait(UnitRace)
	local level = type(UnitLevel) == "function" and public(UnitLevel("player")) or nil
	if not (class and race and type(level) == "number") then return end
	seen[guid] = now
	local available = {}
	for _, quest in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
		local quest_id = type(quest) == "table" and public(quest.questID)
		if type(quest_id) == "number" then available[quest_id] = true end
	end
	for _, giver in ipairs(givers) do
		local eligible = giver.level <= level and done(giver.quest) == false
			and not (C_QuestLog.IsOnQuest and public(C_QuestLog.IsOnQuest(giver.quest)) == true)
		for _, before in ipairs(eligible and giver.before or {}) do
			if done(before) ~= true then eligible = false end
		end
		if eligible then
			row.questId, row.classId, row.raceId, row.band = giver.quest, class, race, math.floor(level / BAND)
			row.offered = available[giver.quest] and 1 or 0
			Everlook.world.count("offers", row)
		end
	end
end
