local root = arg and arg[0] and arg[0]:match("(.+)[/\\]tests[/\\]run%.lua$") or "."
if root == "" then
	root = "."
end

local source = dofile(root .. "/tests/suite.lua")(root)
local failed = 0

local function check(name, condition)
	if condition then
		return
	end
	failed = failed + 1
	print("FAIL " .. name)
end

-- The engine's CBOR is a handle to a snapshot, so a page that is read back is a new table.
local engine = { snapshots = {} }
function engine.copy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in pairs(value) do
		copy[key] = engine.copy(item)
	end
	return copy
end

engine.api = {
	SerializeCBOR = function(value)
		engine.snapshots[#engine.snapshots + 1] = engine.copy(value)
		return "cbor:" .. #engine.snapshots
	end,
	DeserializeCBOR = function(handle)
		local index = tonumber(tostring(handle):match("^cbor:(%d+)$"))
		return index and engine.copy(engine.snapshots[index]) or nil
	end,
	EncodeBase64 = function(value)
		return value
	end,
	DecodeBase64 = function(value)
		return value
	end,
}

local function load_addon()
	local Everlook = {}
	local env = setmetatable({
		EventUtil = {
			ContinueOnAddOnLoaded = function() end,
			ContinueOnPlayerLogin = function() end,
		},
		CreateFrame = function()
			return {
				RegisterEvent = function() end,
				SetScript = function() end,
				Show = function() end,
				Hide = function() end,
				IsShown = function()
					return false
				end,
			}
		end,
		time = function()
			return 50
		end,
	}, {
		-- A test that sets its own encoder wins. Otherwise the engine here keeps pages.
		__index = function(_, key)
			local value = _G[key]
			if value == nil and key == "C_EncodingUtil" then
				return engine.api
			end
			return value
		end,
	})
	local files = {
		"world.lua",
		"location.lua",
		"sightings.lua",
		"npcs.lua",
		"items.lua",
		"objects.lua",
		"quests.lua",
		"vendors.lua",
		"spells.lua",
		"talents.lua",
		"factions.lua",
		"recipes.lua",
		"taxi.lua",
		"fishing.lua",
		"drops.lua",
		"scan.lua",
		"hash.lua",
		"config.lua",
		"pages.lua",
		"segments.lua",
		"sign_template.lua",
		"links.lua",
		"collected.lua",
	}
	for i = 1, #files do
		local chunk = assert(loadfile(source(files[i])))
		setfenv(chunk, env)
		chunk("Everlook", Everlook)
	end
	return Everlook, env
end

local Everlook = load_addon()
Everlook.world.reset()
check("the namespace is the global Everlook, for module addons", rawget(_G, "Everlook") == Everlook)

check("secret numbers are dropped", Everlook.world.usable("ok") == true)
_G.issecretvalue = function(value)
	return value == "secret"
end
check("secret values are unusable", Everlook.world.usable("secret") == false)

Everlook.world.store("maps", { id = 37, name = "Elwynn Forest" })
Everlook.world.store("npcs", {
	id = 448,
	name = "Hogger",
	minLevel = 11,
	maxLevel = 11,
	locations = { { mapId = 37, x = 250, y = 600, zone = "Elwynn Forest", seen = 1 } },
	sources = { "target" },
})
Everlook.world.store("npcs", {
	id = 448,
	name = "Hogger",
	minLevel = 10,
	maxLevel = 12,
	locations = { { mapId = 37, x = 250, y = 600, zone = "Elwynn Forest", seen = 1 } },
	sources = { "mouseover" },
})

local document = Everlook.world.document()
local npc = document.npcs[1]
check("level widens downward", npc[4] == 10)
check("level widens upward", npc[5] == 12)
check("short fields stay positional", npc[1] == 448)
check("repeated zone is interned", document.s[1] == "Elwynn Forest")
check("zone uses the string index", npc[17][1][5] == 1)
check("second sighting adds seen", npc[17][1][4] == 2)

Everlook.world.reset()
Everlook.world.store("npcs", { id = 1, name = "Kobold" })
local short = Everlook.world.document().npcs[1]
check("tail is omitted", #short == 2)

check("creature id is the sixth field", Everlook.npcs.creature_id("Creature-0-1-0-2-448-abc") == 448)
check("creature id can end on the entry", Everlook.npcs.creature_id("Creature-0-1-0-2-448") == 448)
check("players are not creatures", Everlook.npcs.creature_id("Player-1-2") == nil)

do
	_G.GetTime = function()
		return 100
	end
	local window = Everlook.sightings.window(5)
	local other_window = Everlook.sightings.window(5)
	check("a guid is new before it is noted", window.same("Creature-0-1-0-2-448-abc", "mouseover") == false)
	window.note("Creature-0-1-0-2-448-abc", "mouseover")
	check("a noted guid repeats inside the window", window.same("Creature-0-1-0-2-448-abc", "mouseover") == true)
	check("another source starts its own window", window.same("Creature-0-1-0-2-448-abc", "target") == false)
	check("another collector keeps its own window", other_window.same("Creature-0-1-0-2-448-abc", "mouseover") == false)
	_G.GetTime = function()
		return 105
	end
	check("the window closes after five seconds", window.same("Creature-0-1-0-2-448-abc", "mouseover") == false)
	_G.GetTime = nil
	check("a window without a clock never repeats", window.same("Creature-0-1-0-2-448-abc", "mouseover") == false)
	check("a secret guid is never plain", Everlook.sightings.plain_guid("secret") == false)
	check("an empty mouseover is never plain", Everlook.sightings.plain_guid(false) == false)
	check("a real guid is plain", Everlook.sightings.plain_guid("Creature-0-1-0-2-448-abc") == true)
end

local _, env = load_addon()
env.IsFishingLoot = function()
	return false
end
env.GetNumLootItems = function()
	return 1
end
env.GetLootSlotType = function()
	return 1
end
env.GetLootSlotLink = function()
	return "|Hitem:80|h[Shoes]|h"
end
env.GetLootSlotInfo = function()
	return nil, "Shoes", 4
end
env.GetLootSourceInfo = function()
	return "Creature-0-1-0-2-448-abc", 4
end
env.C_Item = {}
local EverlookDrops = load_addon()
-- The second load replaced globals. Reapply stubs onto that environment by reloading after setting _G.
_G.IsFishingLoot = env.IsFishingLoot
_G.GetNumLootItems = env.GetNumLootItems
_G.GetLootSlotType = env.GetLootSlotType
_G.GetLootSlotLink = env.GetLootSlotLink
_G.GetLootSlotInfo = env.GetLootSlotInfo
_G.GetLootSourceInfo = env.GetLootSourceInfo
_G.C_Item = {}
EverlookDrops = load_addon()
EverlookDrops.drops.scan()
local loot = EverlookDrops.world.document()
check("loot records one drop", loot.drops[1][1] == 448 and loot.drops[1][2] == 80 and loot.drops[1][3] == 1 and loot.drops[1][4] == 4)
check("loot records the kill", loot.kills[1][1] == 448 and loot.kills[1][2] == 1)
local loot_object_parses = 0
local parse_loot_guid = EverlookDrops.world.guid_id
EverlookDrops.world.guid_id = function(guid, kind)
	if kind == "GameObject" then
		loot_object_parses = loot_object_parses + 1
	end
	return parse_loot_guid(guid, kind)
end
_G.GetNumLootItems = function()
	return 2
end
EverlookDrops.drops.scan()
check("creature loot does not parse an object guid", loot_object_parses == 0)
_G.GetNumLootItems = function()
	return 1
end
local repeat_loot = EverlookDrops.world.document()
local repeat_drops = repeat_loot.drops[1][3]
local repeat_kills = repeat_loot.kills[1][2]
local repeat_quantity = repeat_loot.drops[1][4]
local loot_stores = 0
local store_loot = EverlookDrops.world.store
EverlookDrops.world.store = function(bucket, row)
	if bucket == "drops" or bucket == "kills" then
		loot_stores = loot_stores + 1
	end
	return store_loot(bucket, row)
end
EverlookDrops.drops.scan()
local counted = EverlookDrops.world.document()
check("repeat loot counts without storing the rows", loot_stores == 0 and counted.drops[1][3] == repeat_drops + 1 and counted.kills[1][2] == repeat_kills + 1 and counted.drops[1][4] == repeat_quantity + 4)
EverlookDrops.world.store = store_loot
_G.GetNumLootItems = env.GetNumLootItems

_G.GetNumLootItems = function()
	return 1
end
_G.GetLootSlotLink = function()
	return "|Hitem:80|h[Fish]|h"
end
_G.GetLootSlotInfo = function()
	return nil, "Raw Fish", 1
end
_G.GetZoneText = function()
	return "Elwynn Forest"
end
_G.GetTime = function()
	return 1000
end
_G.C_Map = {
	GetBestMapForUnit = function()
		return 37
	end,
	GetPlayerMapPosition = function()
		return { x = 0.5, y = 0.25 }
	end,
}
local fish = load_addon()
fish.world.reset()
fish.fishing.scan()
local fish_stores = 0
local store_fish = fish.world.store
fish.world.store = function(bucket, row)
	if bucket == "fishingLoot" then
		fish_stores = fish_stores + 1
	end
	return store_fish(bucket, row)
end
fish.fishing.scan()
local catch = fish.world.document().fishingLoot
check("repeat catch counts without storing the row", fish_stores == 0 and catch and catch[1][1] == 37 and catch[1][3] == 80 and catch[1][4] == 2 and catch[1][5] == 2)
_G.GetNumLootItems = env.GetNumLootItems
_G.GetLootSlotLink = env.GetLootSlotLink
_G.GetLootSlotInfo = env.GetLootSlotInfo
_G.GetZoneText = nil
_G.GetTime = nil
_G.C_Map = nil

local quests = load_addon()
quests.world.reset()
quests.quests.record(176, "giver", {
	title = "Wanted: Hogger",
	description = "Hogger has been terrorizing Northshire.",
	giverId = 448,
	requires = { 54 },
	rewards = { money = 50, items = { { id = 80, quantity = 1 } } },
	objectives = { { type = "monster", id = 448, numRequired = 1, text = "Hogger slain" } },
	starters = { { type = "npc", id = 448, name = "Hogger" } },
})
local quest = quests.world.document().quests[1]
check("quest id and title pack", quest[1] == 176 and quest[2] == "Wanted: Hogger")
check("quest description packs", quest[7] == "Hogger has been terrorizing Northshire.")
check("quest reward money packs", quest[19][1] == 50)
check("quest reward item packs", quest[19][3][1][1] == 80)
check("quest requires packs", quest[22][1] == 54)

_G.UnitClass = function()
	return "Paladin", "PALADIN", 2
end
_G.UnitName = function()
	return "Hallas"
end
local spoken = load_addon()
spoken.world.reset()
spoken.quests.record(834, "giver", {
	title = "Call of Earth",
	description = "Please, paladin, find some sign of my wife.",
})
local spokenQuest = spoken.world.document().quests[1]
check("quest class address becomes $c", spokenQuest[7] == "Please, $c, find some sign of my wife.")
local speaker = "Hallas"
_G.UnitName = function()
	return speaker
end
spoken.quests.record(835, "giver", {
	title = "Call of Earth",
	description = "Hallas, the land is quiet.",
})
speaker = "Pip"
spoken.quests.record(836, "giver", {
	title = "Call of Earth",
	description = "Pip, bring water.",
})
local spoken_quests = spoken.world.document().quests
local hallas_line, pip_line
for i = 1, #spoken_quests do
	if spoken_quests[i][1] == 835 then
		hallas_line = spoken_quests[i][7]
	elseif spoken_quests[i][1] == 836 then
		pip_line = spoken_quests[i][7]
	end
end
check("quest name tokens follow a rename", hallas_line == "$n, the land is quiet." and pip_line == "$n, bring water.")
_G.UnitClass = nil
_G.UnitName = nil

_G.GetNumQuestLogRewardFactions = function()
	return 1
end
_G.GetQuestLogRewardFactionInfo = function(index)
	if index == 1 then
		return 72, 250
	end
end
_G.GetFactionInfoByID = function(id)
	if id == 72 then
		return "Stormwind"
	end
end
local rewarded = load_addon()
rewarded.world.reset()
rewarded.quests.record(176, "complete", {
	title = "Wanted: Hogger",
	rewards = rewarded.quests.rewards(),
})
local reward_world = rewarded.world.document()
local reward_quest = reward_world.quests[1]
check("quest reward reputation packs", reward_quest and reward_quest[19] and reward_quest[19][5] and reward_quest[19][5][1][1] == 72 and reward_quest[19][5][1][2] == 250 and reward_quest[19][5][2] == nil)
check("quest reward reputation names the faction", reward_world.factions and reward_world.factions[1][1] == 72 and reward_world.factions[1][2] == "Stormwind")
_G.GetNumQuestLogRewardFactions = nil
_G.GetQuestLogRewardFactionInfo = nil
_G.GetFactionInfoByID = nil

_G.Enum = { QuestFrequency = { Default = 0, Daily = 1, Weekly = 2 } }
_G.C_QuestLog = {
	GetNumQuestLogEntries = function()
		return 1
	end,
	GetInfo = function(index)
		if index == 1 then
			return { questID = 15, title = "The People's Militia", frequency = 1, isHeader = false }
		end
	end,
}
local logged = load_addon()
logged.world.reset()
logged.quests.scan()
local daily = logged.world.document().quests[1]
check("quest log packs a daily frequency", daily and daily[1] == 15 and daily[2] == "The People's Militia" and daily[6] == "daily")
_G.Enum = nil
_G.C_QuestLog = nil

_G.GetQuestFactionGroup = function(id)
	if id == 176 then
		return 1
	end
end
local sided = load_addon()
sided.world.reset()
sided.quests.record(176, "giver", { title = "Wanted: Hogger" })
local alliance = sided.world.document().quests[1]
check("quest packs an alliance faction", alliance and alliance[1] == 176 and alliance[12] == 1)
_G.GetQuestFactionGroup = nil

_G.C_QuestLog = {
	GetQuestUiMapID = function(id)
		if id == 176 then
			return 1429
		end
	end,
}
sided = load_addon()
sided.world.reset()
sided.quests.record(176, "giver", { title = "Wanted: Hogger" })
alliance = sided.world.document().quests[1]
check("quest packs a ui map when it has no pin", alliance and alliance[1] == 176 and alliance[13] == 1429)
_G.C_QuestLog = nil

_G.C_QuestLog = {
	GetQuestTagInfo = function(id)
		if id == 176 then
			return { tagID = 81 }
		end
	end,
}
local tagged = load_addon()
tagged.world.reset()
tagged.quests.record(176, "giver", { title = "Wanted: Hogger" })
local dungeon = tagged.world.document().quests[1]
check("quest packs a dungeon tag", dungeon and dungeon[1] == 176 and dungeon[11] == 81)
_G.C_QuestLog = nil

local level_reads = 0
_G.C_QuestLog = {
	GetQuestDifficultyLevel = function(id)
		level_reads = level_reads + 1
		if id == 176 then
			return 11
		end
	end,
	GetRequiredLevel = function()
		return 1
	end,
	GetSuggestedGroupSize = function()
		return 0
	end,
}
local stable = load_addon()
stable.world.reset()
stable.quests.record(176, "giver", { title = "Wanted: Hogger" })
local level_after = level_reads
stable.quests.record(176, "progress", { title = "Wanted: Hogger", progressText = "Hogger is still at large." })
local stable_quest = stable.world.document().quests[1]
check("stable quest fields are not reread", level_after == 1 and level_reads == 1 and stable_quest and stable_quest[3] == 11 and stable_quest[4] == 1 and stable_quest[5] == 0)
_G.C_QuestLog = nil

local pending_level = 0
local pending_reads = 0
_G.C_QuestLog = {
	GetQuestDifficultyLevel = function()
		pending_reads = pending_reads + 1
		return pending_level
	end,
}
local pending = load_addon()
pending.world.reset()
pending.quests.record(176, "giver", { title = "Wanted: Hogger" })
pending_level = 11
pending.quests.record(176, "progress", { title = "Wanted: Hogger" })
local pending_quest = pending.world.document().quests[1]
check("quest level is read again until it is known", pending_reads == 2 and pending_quest and pending_quest[3] == 11)
_G.C_QuestLog = nil

_G.GetQuestLogCompletionText = function(index)
	if index == 1 then
		return "Return to Marshal McBride."
	end
end
_G.C_QuestLog = {
	GetNumQuestLogEntries = function()
		return 1
	end,
	GetInfo = function(index)
		if index == 1 then
			return { questID = 783, title = "A Threat Within", isHeader = false }
		end
	end,
}
local completed = load_addon()
completed.world.reset()
completed.quests.scan()
local turnin = completed.world.document().quests[1]
check("quest log packs completion text", turnin and turnin[1] == 783 and turnin[10] == "Return to Marshal McBride.")
_G.GetQuestLogCompletionText = nil
_G.C_QuestLog = nil

local text_reads = 0
_G.GetQuestLogQuestText = function()
	text_reads = text_reads + 1
	return "Kill wolves.", "Wolves killed: 0/8"
end
_G.C_QuestLog = {
	GetNumQuestLogEntries = function()
		return 1
	end,
	GetInfo = function()
		return { questID = 15, title = "The People's Militia", isHeader = false, questLogIndex = 1 }
	end,
	GetQuestObjectives = function()
		return { { numFulfilled = 0, numRequired = 8, finished = false } }
	end,
	IsComplete = function()
		return false
	end,
}
local quiet = load_addon()
quiet.world.reset()
quiet.quests.scan()
local reads_after_first = text_reads
quiet.quests.scan()
check("unchanged quest log skips quest text", text_reads == reads_after_first)
_G.GetQuestLogQuestText = nil
_G.C_QuestLog = nil

local objective_reads = 0
_G.GetQuestLogQuestText = function()
	return "Kill wolves.", "Wolves killed: 0/8"
end
_G.C_QuestLog = {
	GetNumQuestLogEntries = function()
		return 1
	end,
	GetInfo = function()
		return { questID = 15, title = "The People's Militia", isHeader = false, questLogIndex = 1 }
	end,
	GetQuestObjectives = function()
		objective_reads = objective_reads + 1
		return { { type = "monster", objectID = 299, numFulfilled = 0, numRequired = 8, finished = false, text = "Wolves killed" } }
	end,
	IsComplete = function()
		return false
	end,
}
local once = load_addon()
once.world.reset()
once.quests.scan()
local objective = once.world.document().quests[1]
check("quest log reads objectives once", objective_reads == 1 and objective and objective[14] and objective[14][1][2] == 299 and objective[14][1][3] == 8 and objective[14][1][4] == "Wolves killed")
once.quests.scan()
check("unchanged quest log reads objectives once", objective_reads == 2)
_G.GetQuestLogQuestText = nil
_G.C_QuestLog = nil

local info_reads = 0
_G.GetQuestLogQuestText = function()
	return "Kill wolves.", "Wolves killed: 0/8"
end
_G.C_QuestLog = {
	GetNumQuestLogEntries = function()
		return 2
	end,
	GetQuestIDForLogIndex = function(index)
		if index == 2 then
			return 15
		end
	end,
	GetInfo = function(index)
		info_reads = info_reads + 1
		if index == 2 then
			return { questID = 15, title = "The People's Militia", isHeader = false, questLogIndex = 2 }
		end
		return { title = "Elwynn Forest", isHeader = true }
	end,
	GetQuestObjectives = function()
		return { { numFulfilled = 0, numRequired = 8, finished = false } }
	end,
	IsComplete = function()
		return false
	end,
}
local info_quiet = load_addon()
info_quiet.world.reset()
info_quiet.quests.scan()
local info_after_first = info_reads
check("quest log still reads info once to store the quest", info_after_first == 1 and info_quiet.world.document().quests[1][1] == 15)
info_quiet.quests.scan()
check("unchanged quest log skips quest info tables", info_reads == info_after_first)
_G.GetQuestLogQuestText = nil
_G.C_QuestLog = nil

local line_reads = 0
_G.GetQuestLogQuestText = function()
	return "Kill wolves.", "Wolves killed: 0/8"
end
_G.C_QuestLog = {
	GetNumQuestLogEntries = function()
		return 1
	end,
	GetInfo = function()
		return { questID = 15, title = "The People's Militia", isHeader = false, questLogIndex = 1 }
	end,
	GetQuestObjectives = function()
		return { { numFulfilled = 0, numRequired = 8, finished = false } }
	end,
	IsComplete = function()
		return false
	end,
}
_G.C_Map = {
	GetBestMapForUnit = function()
		return 37
	end,
}
_G.C_QuestLine = {
	RequestQuestLinesForMap = function()
	end,
	GetAvailableQuestLines = function()
		line_reads = line_reads + 1
		if line_reads == 1 then
			return {}
		end
		return { { questID = 16, questName = "Wolves", questLineID = 4, questLineName = "Elwynn Wolves" } }
	end,
	GetQuestLineInfo = function()
		return nil
	end,
}
local lined = load_addon()
lined.world.reset()
lined.quests.scan()
lined.quests.scan()
local wolves
local lined_quests = lined.world.document().quests
for i = 1, #lined_quests do
	if lined_quests[i][1] == 16 then
		wolves = lined_quests[i]
	end
end
check("quest lines load on the update after the map request", wolves and wolves[2] == "Wolves")
check("a quest from the map's quest lines keeps its line", wolves and wolves[24] == 4 and wolves[25] == "Elwynn Wolves")
_G.GetQuestLogQuestText = nil
_G.C_QuestLog = nil
_G.C_Map = nil
_G.C_QuestLine = nil

local line_info_reads = 0
_G.C_QuestLog = {
	GetTitleForQuestID = function(id)
		if id == 54 then
			return "Hogger's Trail"
		end
		if id == 176 then
			return "Wanted: Hogger"
		end
	end,
}
_G.C_QuestLine = {
	GetQuestLineInfo = function(id)
		line_info_reads = line_info_reads + 1
		if id == 176 then
			return { questLineID = 9, questLineName = "Hogger's End" }
		end
	end,
	GetQuestLineQuests = function()
		return { 54, 176 }
	end,
}
local chained = load_addon()
chained.world.reset()
chained.quests.record(176, "quest-log", { title = "Wanted: Hogger", description = "Bring the head." })
local line_reads_after_first = line_info_reads
chained.quests.record(176, "quest-log", { title = "Wanted: Hogger", objectiveText = "Head: 1/1" })
local chained_document = chained.world.document()
local chained_quests = chained_document.quests
local hogger, trail
for i = 1, #chained_quests do
	if chained_quests[i][1] == 176 then
		hogger = chained_quests[i]
	elseif chained_quests[i][1] == 54 then
		trail = chained_quests[i]
	end
end
check("repeat quest progress skips the quest line", line_info_reads == line_reads_after_first and line_reads_after_first == 1)
check("resolved quest line still links the previous quest", hogger and hogger[22] and hogger[22][1] == 54 and trail and trail[2] == "Hogger's Trail")
local line_name = chained_document.s and chained_document.s[hogger and hogger[25] or 0]
check("every quest on a resolved line keeps the line", line_name == "Hogger's End" and hogger[24] == 9 and trail and trail[24] == 9 and trail[25] == hogger[25])
_G.C_QuestLog = nil
_G.C_QuestLine = nil

local clock = { now = 1000 }
_G.GetTime = function()
	return clock.now
end
local handoff = load_addon()
handoff.world.reset()
handoff.quests.note_turned_in(422)
clock.now = 1005
handoff.quests.record(423, "giver", {
	title = "Arugal's Folly",
	requires = handoff.quests.followup_requires(423),
})
handoff.quests.note_turned_in(423)
clock.now = 1030
handoff.quests.record(424, "accepted", {
	title = "Arugal's Folly",
	requires = handoff.quests.followup_requires(424),
})
local folly
local handoff_quests = handoff.world.document().quests
for i = 1, #handoff_quests do
	if handoff_quests[i][1] == 423 then
		folly = handoff_quests[i]
	end
end
check("a quest offered after a turn-in records the previous quest", folly and folly[22] and folly[22][1] == 422)
local stale = false
for i = 1, #handoff_quests do
	if handoff_quests[i][1] == 424 then
		stale = handoff_quests[i][22] ~= nil
	end
end
check("a later quest does not keep a stale turn-in link", stale == false)
_G.GetTime = nil

_G.C_Map = {
	GetBestMapForUnit = function()
		return 1429
	end,
	GetMapInfo = function(id)
		if id == 1429 then
			return { parentMapID = 14 }
		end
	end,
}
_G.C_QuestLog = {
	GetNumQuestLogEntries = function()
		return 1
	end,
	GetQuestIDForLogIndex = function()
		return 423
	end,
	GetInfo = function()
		return { questID = 423, title = "Arugal's Folly", questLogIndex = 1 }
	end,
	GetTitleForQuestID = function(id)
		if id == 422 or id == 423 then
			return "Arugal's Folly"
		end
	end,
	GetAllCompletedQuestIDs = function()
		return { 422 }
	end,
}
_G.C_QuestLine = {
	RequestQuestLinesForMap = function()
	end,
	GetAvailableQuestLines = function()
		return {}
	end,
	GetQuestLineInfo = function(id, mapId)
		if id == 423 and mapId == 14 then
			return { questLineID = 3 }
		end
	end,
	GetQuestLineQuests = function()
		return { 422, 423 }
	end,
}
local eager_chain = load_addon()
eager_chain.world.reset()
_G.EverlookDB = {}
eager_chain.scan.now()
local folly_chain
local eager_quests = eager_chain.world.document().quests
for i = 1, #eager_quests do
	if eager_quests[i][1] == 423 then
		folly_chain = eager_quests[i]
	end
end
check("eager scan links a quest line found on a parent map", folly_chain and folly_chain[22] and folly_chain[22][1] == 422)
check("a line the game does not name keeps its id", folly_chain and folly_chain[24] == 3 and folly_chain[25] == nil)
_G.C_Map = nil
_G.C_QuestLog = nil
_G.C_QuestLine = nil

local objects = load_addon()
check("object id is the sixth field", objects.world.guid_id("GameObject-0-1-0-2-1731-abc", "GameObject") == 1731)
_G.C_TooltipInfo = {
	GetUnit = function()
		return {
			lines = {
				{ leftText = "Copper Vein" },
				{ leftText = "Requires Mining (1)" },
			},
		}
	end,
}
objects.world.reset()
objects.objects.record("GameObject-0-1-0-2-1731-abc", "mouseover", "Copper Vein")
local vein = objects.world.document().objects[1]
check("object scan packs mining type", vein and vein[1] == 1731 and vein[2] == "Copper Vein" and vein[3] == "mining")
_G.C_TooltipInfo = {
	GetUnit = function()
		return {
			lines = {
				{ leftText = "Aged Envelope" },
				{ leftText = "Locked" },
			},
		}
	end,
}
_G.UnitName = function()
	return nil
end
_G.LOCKED = "Locked"
objects = load_addon()
objects.world.reset()
objects.objects.record("GameObject-0-1-0-2-3239-abc", "mouseover")
vein = objects.world.document().objects[1]
check("object name comes from the tooltip when UnitName is empty", vein and vein[1] == 3239 and vein[2] == "Aged Envelope")
_G.UnitName = nil
_G.LOCKED = nil
_G.C_TooltipInfo = nil

local object_reads = 0
local full_object_tip = false
local object_clock = { now = 1000 }
_G.GetTime = function()
	return object_clock.now
end
_G.C_Map = {
	GetBestMapForUnit = function()
		return 37
	end,
	GetPlayerMapPosition = function()
		return { x = 0.5, y = 0.25 }
	end,
}
_G.C_TooltipInfo = {
	GetUnit = function()
		object_reads = object_reads + 1
		if not full_object_tip then
			return { lines = { { leftText = "Copper Vein" } } }
		end
		return { lines = { { leftText = "Copper Vein" }, { leftText = "Requires Mining (1)" } } }
	end,
}
local hovered = load_addon()
hovered.world.reset()
local object_guid = "GameObject-0-1-0-2-1731-abc"
hovered.objects.record(object_guid, "mouseover", "Copper Vein")
full_object_tip = true
hovered.objects.record(object_guid, "mouseover", "Copper Vein")
local hovered_vein = hovered.world.document().objects[1]
check("object type still arrives after the first tooltip", hovered_vein and hovered_vein[3] == "mining")
local reads_after_type = object_reads
hovered.objects.record(object_guid, "mouseover", "Copper Vein")
check("repeat object mouseover skips the tooltip", object_reads == reads_after_type)
object_clock.now = 1006
hovered.objects.record(object_guid, "mouseover", "Copper Vein")
local settled_vein = hovered.world.document().objects[1]
check("settled object mouseover skips the tooltip", object_reads == reads_after_type and settled_vein and settled_vein[3] == "mining" and settled_vein[4] and settled_vein[4][1][4] == 3)
_G.GetTime = nil
_G.C_Map = nil
_G.C_TooltipInfo = nil

local plain_reads = 0
local plain_full = false
_G.GetTime = function()
	return plain_full and 1012 or 1000
end
_G.C_Map = {
	GetBestMapForUnit = function()
		return 37
	end,
	GetPlayerMapPosition = function()
		return { x = 0.5, y = 0.25 }
	end,
}
_G.C_TooltipInfo = {
	GetUnit = function()
		plain_reads = plain_reads + 1
		if not plain_full then
			return { lines = { { leftText = "Copper Vein" } } }
		end
		return { lines = { { leftText = "Copper Vein" }, { leftText = "Requires Mining (1)" } } }
	end,
}
local plain = load_addon()
plain.world.reset()
plain.objects.record(object_guid, "mouseover", "Copper Vein")
plain.objects.record(object_guid, "mouseover", "Copper Vein")
plain_full = true
plain.objects.record(object_guid, "mouseover", "Copper Vein")
local plain_vein = plain.world.document().objects[1]
check("a node without a type is read again after the window", plain_reads == 3 and plain_vein and plain_vein[3] == "mining")
_G.GetTime = nil
_G.C_Map = nil
_G.C_TooltipInfo = nil

local vendors = load_addon()
vendors.world.reset()
_G.UnitGUID = function()
	return "Creature-0-1-0-2-197-abc"
end
_G.GetMerchantNumItems = function()
	return 1
end
_G.GetMerchantItemID = function()
	return 159
end
_G.GetMerchantItemInfo = function()
	return "Refreshing Spring Water", nil, 25, 5, -1, nil, nil, false
end
_G.C_Item = {}
vendors = load_addon()
vendors.vendors.scan()
local vendor = vendors.world.document().vendors[1]
check("vendor row packs", vendor[1] == 197 and vendor[2] == 159 and vendor[3] == 25)
check("vendor scan stores the buy price on the item", (function()
	local items = vendors.world.document().items or {}
	for i = 1, #items do
		if items[i][1] == 159 then
			return items[i][14] == 25
		end
	end
end)())
local vendor_stores = 0
local store_vendor = vendors.world.store
vendors.world.store = function(bucket, row)
	if bucket == "vendors" then
		vendor_stores = vendor_stores + 1
	end
	return store_vendor(bucket, row)
end
vendors.vendors.scan()
check("unchanged merchant scan does not store the offer again", vendor_stores == 0)
local cost_reads = 0
_G.GetMerchantItemCostInfo = function()
	cost_reads = cost_reads + 1
	return 0
end
_G.GetMerchantItemCostItem = function()
end
vendors.vendors.scan()
check("gold offer does not read currency costs", cost_reads == 0)
_G.GetMerchantItemID = function()
	return 26045
end
_G.GetMerchantItemInfo = function()
	return "Badge", nil, 0, 1, -1, nil, nil, true
end
_G.GetMerchantItemCostInfo = function()
	cost_reads = cost_reads + 1
	return 1
end
_G.GetMerchantItemCostItem = function()
	return nil, 10, nil, 1901
end
vendors.vendors.scan()
local cost_after = cost_reads
vendors.vendors.scan()
check("extended cost is read once", cost_after == 1 and cost_reads == cost_after)
_G.GetMerchantItemID = function()
	return 12345
end
local cost_link_ready = false
_G.GetMerchantItemCostInfo = function()
	cost_reads = cost_reads + 1
	return 1
end
_G.GetMerchantItemCostItem = function()
	if not cost_link_ready then
		return nil, 1, nil, nil
	end
	return nil, 1, "item:2589", nil
end
vendors.vendors.scan()
local reads_before_link = cost_reads
cost_link_ready = true
vendors.vendors.scan()
local linked_cost
local merchant_costs = vendors.world.document().merchantCosts or {}
for i = 1, #merchant_costs do
	if merchant_costs[i][2] == 12345 then
		linked_cost = merchant_costs[i]
	end
end
check("merchant item cost is read again until the item id arrives", cost_reads > reads_before_link and linked_cost and linked_cost[4] == 2589)
_G.GetMerchantItemCostInfo = nil
_G.GetMerchantItemCostItem = nil

local EverlookLocation, locationEnv = load_addon()
locationEnv.C_Map = {
	GetBestMapForUnit = function()
		return 37
	end,
	GetPlayerMapPosition = function()
		return { x = 1.5, y = 0.2 }
	end,
}
EverlookLocation = load_addon()
-- location.lua closed over its environment. Set C_Map before load.
local function load_with(extra)
	local Everlook = {}
	local env = setmetatable({
		EventUtil = { ContinueOnAddOnLoaded = function() end },
		CreateFrame = function()
			return { RegisterEvent = function() end, SetScript = function() end }
		end,
		time = function()
			return 50
		end,
	}, { __index = _G })
	env._G = env
	for key, value in pairs(extra) do
		env[key] = value
	end
	for _, file in ipairs({ "world.lua", "location.lua" }) do
		local chunk = assert(loadfile(source(file)))
		setfenv(chunk, env)
		chunk("Everlook", Everlook)
	end
	return Everlook
end

local located = load_with({
	C_Map = {
		GetBestMapForUnit = function()
			return 37
		end,
		GetPlayerMapPosition = function()
			return { x = 1.5, y = 0.2 }
		end,
	},
})
check("coordinates outside 0 to 1 are dropped", located.location.player() == nil)

local shared_spot = load_with({
	GetTime = function()
		return 10
	end,
	C_Map = {
		GetBestMapForUnit = function()
			return 37
		end,
		GetPlayerMapPosition = function()
			return { x = 0.5, y = 0.25 }
		end,
	},
})
local first = shared_spot.location.player(true)
local second = shared_spot.location.player(true)
check("nameplates share one player location", first and first == second and first.mapId == 37 and first.x == 500 and first.y == 250)
local owned = shared_spot.location.player()
owned.role = 4
check("pin copy does not change the shared location", owned ~= first and first.role == nil)

_G.EverlookDB = { eager = true }
local eager = load_addon()
local passes = 0
eager.spells.scan_book = function()
	passes = passes + 1
end
eager.scan.now()
eager.scan.now()
check("eager scan runs once per click and does not stay on", passes == 2 and EverlookDB.eager == nil);

(function()
	local said = {}
	_G.DEFAULT_CHAT_FRAME = {
		AddMessage = function(_, text)
			said[#said + 1] = text
		end,
	}
	local chat = load_addon()
	_G.EverlookDB = { eager = true }
	chat.scan.now()
	local started, finished, chains = false, false, false
	for i = 1, #said do
		if said[i] == "Everlook: Eager scan started." then
			started = true
		elseif said[i] == "Everlook: Eager scan finished." then
			finished = true
		elseif said[i] == "Everlook: Checking quest chains." then
			chains = true
		end
	end
	check("eager scan reports progress in chat", started and chains and finished)
	local talents = false
	for i = 1, #said do
		if said[i] == "Everlook: Scanning talents." then
			talents = true
		end
	end
	check("eager scan reports the talent pass", talents)
	_G.DEFAULT_CHAT_FRAME = nil
end)()

_G.C_Spell = {
	GetSpellInfo = function(id)
		if id == 133 then
			return { name = "Fireball", iconID = 135812, castTime = 1500, minRange = 8, maxRange = 35 }
		end
	end,
	GetSpellSubtext = function(id)
		if id == 133 then
			return "Rank 1"
		end
	end,
	GetSpellDescription = function(id)
		if id == 133 then
			return "Hurls a fiery ball that causes Fire damage."
		end
	end,
	GetSpellPowerCost = function(id)
		if id == 133 then
			return { { type = 0, cost = 30 } }
		end
	end,
}
_G.GetSpellSchool = function(id)
	if id == 133 then
		return 4
	end
end
_G.GetSpellBaseCooldown = function(id)
	if id == 133 then
		return 8000, 1500
	end
end
_G.C_SpellBook = {
	GetNumSpellBookSkillLines = function()
		return 1
	end,
	GetSpellBookSkillLineInfo = function()
		return { itemIndexOffset = 0, numSpellBookItems = 1 }
	end,
	GetSpellBookItemInfo = function(slot)
		if slot == 1 then
			return { spellID = 133, subName = "Rank 1" }
		end
	end,
}
_G.GetInventoryItemID = function(_, slot)
	if slot == 16 then
		return 25
	end
end
_G.C_Item = {
	GetItemInfo = function(id)
		if id == 25 then
			return "Worn Shortsword", nil, 1, 2, 1, "Weapon", "Sword", 1, "INVTYPE_WEAPON", 135274, 8, 2, 7, 1, nil, 181, true
		end
	end,
	GetItemStats = function(link)
		if link == "item:25" then
			return { ITEM_MOD_STAMINA_SHORT = 3, ITEM_MOD_AGILITY_SHORT = 1, ITEM_MOD_MANA_REGENERATION_SHORT = 1.5 }
		end
	end,
	GetItemSpell = function(id)
		if id == 25 then
			return "Poison", 132
		end
	end,
}
_G.ITEM_SPELL_TRIGGER_ONUSE = "Use: %s"
_G.ITEM_SPELL_TRIGGER_ONEQUIP = "Equip: %s"
_G.ITEM_SPELL_TRIGGER_ONPROC = "Chance on hit: %s"
_G.ITEM_SET_NAME = "%s (%d/%d)"
_G.ITEM_SET_BONUS_GRAY = "(%d) Set: %s"
_G.ITEM_CLASSES_ALLOWED = "Classes: %s"
_G.ITEM_RACES_ALLOWED = "Races: %s"
_G.ITEM_REQ_REPUTATION = "Requires %s - %s"
_G.ITEM_UNIQUE = "Unique"
_G.ITEM_UNIQUE_MULTIPLE = "Unique (%d)"
_G.ITEM_UNIQUE_EQUIPPABLE = "Unique-Equipped"
_G.ITEM_UNIQUE_EQUIPPABLE_MULTIPLE = "Unique-Equipped: %d"
_G.ITEM_MIN_SKILL = "Requires %s (%d)"
_G.ARMOR_TEMPLATE = "%d Armor"
_G.DAMAGE_TEMPLATE = "%d - %d Damage"
_G.DAMAGE_TEMPLATE_WITH_SCHOOL = "%d - %d %s Damage"
_G.SINGLE_DAMAGE_TEMPLATE = "%d Damage"
_G.SPEED_TEMPLATE = "Speed %s"
_G.SHIELD_BLOCK_TEMPLATE = "%d Block"
_G.DURABILITY_TEMPLATE = "Durability %d / %d"
_G.C_TradeSkillUI = {
	GetProfessionInfoBySkillLineID = function(id)
		if id == 164 then
			return { professionName = "Blacksmithing", professionID = 164 }
		end
	end,
}
_G.FACTION_STANDING_LABEL6 = "Honored"
_G.C_Reputation = {
	GetFactionDataByID = function(id)
		if id == 72 then
			return { name = "Stormwind", factionID = 72 }
		end
	end,
}
_G.C_CreatureInfo = {
	GetClassInfo = function(id)
		if id == 1 then
			return { className = "Warrior", classFile = "WARRIOR", classID = 1 }
		end
		if id == 2 then
			return { className = "Paladin", classFile = "PALADIN", classID = 2 }
		end
	end,
	GetRaceInfo = function(id)
		if id == 1 then
			return { raceName = "Human", clientFileString = "Human", raceID = 1 }
		end
		if id == 4 then
			return { raceName = "Night Elf", clientFileString = "NightElf", raceID = 4 }
		end
	end,
}
_G.C_TooltipInfo = {
	GetItemByID = function(id)
		if id == 25 then
			return {
				lines = {
					{ leftText = "Defias Leather (1/5)" },
					{ leftText = "(3) Set: +5 Agility" },
					{ leftText = "(2) Set: +10 Armor" },
					{ leftText = "Classes: Warrior, Paladin" },
					{ leftText = "Races: Human, Night Elf" },
					{ leftText = "Requires Stormwind - Honored" },
					{ leftText = "Requires Blacksmithing (100)" },
					{ leftText = "Unique-Equipped" },
					{ leftText = "47 Armor" },
					{ leftText = "8 - 15 Damage", rightText = "Speed 2.10" },
					{ leftText = "9 Block" },
					{ leftText = "Durability 18 / 20" },
					{ leftText = "Binds when equipped" },
					{ leftText = "Equip: Improves your chance to hit by 1%." },
					{ leftText = "Use: Restores 234 health." },
					{ leftText = "Chance on hit: Blasts the target." },
				},
			}
		end
	end,
}
local swept = load_addon()
swept.world.reset()
swept.spells.scan_book()
swept.items.scan_equipped()
local world = swept.world.document()
local spell = world.spells[1]
local item = world.items[1]
local function shown(value)
	if type(value) == "number" and type(world.s) == "table" then
		return world.s[value]
	end
	return value
end
check("spellbook scan packs the spell and its icon", spell and spell[1] == 133 and spell[2] == "Fireball" and spell[3] == 1500 and spell[4] == 35 and spell[5] == 135812 and spell[6] == "Rank 1" and spell[7] == "Hurls a fiery ball that causes Fire damage." and spell[8] == 8000 and spell[9] == 0 and spell[10] == 30 and spell[11] == 4 and spell[12] == 8)
local spell_reads = 0
local read_description = _G.C_Spell.GetSpellDescription
_G.C_Spell.GetSpellDescription = function(id)
	spell_reads = spell_reads + 1
	return read_description(id)
end
swept.spells.record("target", 133)
local reads_after_repeat = spell_reads
swept.spells.record("target", 133)
check("repeat cast skips spell text", spell_reads == reads_after_repeat)
local npc_casts = swept.world.document().npcSpells
check("repeat casts add npc spell counts", npc_casts and npc_casts[1][1] == 197 and npc_casts[1][2] == 133 and npc_casts[1][3] == 2)
local player_guids = 0
local previous_guid = _G.UnitGUID
_G.UnitGUID = function(unit)
	if unit == "player" then
		player_guids = player_guids + 1
	end
	return previous_guid(unit)
end
swept.spells.record("player", 133)
local player_casts = swept.world.document().npcSpells
check("player casts do not read a creature guid", player_guids == 0 and player_casts and player_casts[1][3] == 2)
local cast_stores = 0
local store_cast = swept.world.store
swept.world.store = function(bucket, row)
	if bucket == "npcSpells" then
		cast_stores = cast_stores + 1
	end
	return store_cast(bucket, row)
end
swept.spells.record("target", 133)
check("repeat npc cast counts without storing the row", cast_stores == 0 and swept.world.document().npcSpells[1][3] == 3)
swept.world.store = store_cast
_G.UnitGUID = previous_guid
_G.C_Spell.GetSpellDescription = function(id)
	if id == 133 then
		return "A hotter ball of fire."
	end
end
swept.spells.record(nil, 133)
spell = swept.world.document().spells[1]
check("spell text updates still refresh a recorded spell", spell and spell[7] == "A hotter ball of fire.")

_G.C_Spell = {
	GetSpellInfo = function(id)
		if id == 19740 then
			return { name = "Blessing of Might", iconID = 135906, castTime = 0, minRange = 0, maxRange = 30 }
		end
	end,
	GetSpellSubtext = function()
		return ""
	end,
	RequestLoadSpellData = function(id)
		_G.__requested = id
	end,
}
_G.C_SpellBook = {
	GetNumSpellBookSkillLines = function()
		return 1
	end,
	GetSpellBookSkillLineInfo = function()
		return { itemIndexOffset = 0, numSpellBookItems = 1 }
	end,
	GetSpellBookItemInfo = function(slot)
		if slot == 1 then
			return { spellID = 19740, subName = "Rank 1" }
		end
	end,
}
_G.GetSpellSchool = nil
_G.GetSpellBaseCooldown = nil
local blessing = load_addon()
blessing.world.reset()
blessing.spells.scan_book()
local might = blessing.world.document().spells[1]
check("spellbook subName is the rank", might and might[1] == 19740 and might[2] == "Blessing of Might" and might[6] == "Rank 1")
local delayed = load_addon()
delayed.world.reset()
_G.__requested = nil
_G.C_SpellBook.GetSpellBookItemInfo = function(slot)
	if slot == 1 then
		return { spellID = 19740, subName = "" }
	end
end
delayed.spells.scan_book()
check("empty rank requests spell text", _G.__requested == 19740)
_G.__requested = nil
_G.C_Spell = nil
_G.C_SpellBook = nil
check("equipped scan packs the worn item", item and item[1] == 25 and item[2] == "Worn Shortsword" and item[6] == 2 and item[7] == "Weapon" and item[8] == 7 and item[9] == "Sword" and item[10] == "INVTYPE_WEAPON" and item[15] == 135274 and item[16] == 181 and item[17] == "Defias Leather" and item[18] == true and item[38][1] == "equipped")
check("equipped scan packs whole item stats", item and item[21][1][1] == "Agility" and item[21][1][2] == 1 and item[21][2][1] == "Stamina" and item[21][2][2] == 3 and item[21][3] == nil)
check("equipped scan packs tooltip effect lines", item and item[22][1][1] == "Improves your chance to hit by 1%." and item[22][1][2] == 1 and item[22][2][1] == "Restores 234 health." and item[22][2][2] == 0 and item[22][2][3] == 132 and item[22][3][1] == "Blasts the target." and item[22][3][2] == 2)
check("equipped scan packs set bonuses", item and item[23] and shown(item[23][1][1]) == "+10 Armor" and item[23][1][2] == 2 and shown(item[23][1][3]) == "+10 Armor" and shown(item[23][2][1]) == "+5 Agility" and item[23][2][2] == 3 and item[23][3] == nil)
check("equipped scan packs class restrictions", item and item[24] and item[24][1][1] == 1 and shown(item[24][1][2]) == "Warrior" and item[24][2][1] == 2 and shown(item[24][2][2]) == "Paladin" and item[24][3] == nil)
check("equipped scan packs race restrictions", item and item[25] and item[25][1][1] == 1 and shown(item[25][1][2]) == "Human" and item[25][2][1] == 4 and shown(item[25][2][2]) == "Night Elf" and item[25][3] == nil)
check("equipped scan packs a reputation requirement", item and item[26] and item[26][1][1] == 72 and item[26][1][2] == 6 and item[26][2] == nil and world.factions and world.factions[1][1] == 72 and world.factions[1][2] == "Stormwind")
check("equipped scan packs unique-equipped", item and item[27] == 1 and item[28] == true)
check("equipped scan packs a skill requirement", item and item[29] == 164 and item[30] == 100 and world.skillLines and world.skillLines[1][1] == 164 and world.skillLines[1][2] == "Blacksmithing")
check("equipped scan packs armor", item and item[31] == 47)
check("equipped scan packs weapon damage", item and item[32] == 8 and item[33] == 15 and item[34] == 210)
check("equipped scan packs block", item and item[35] == 9)
check("equipped scan packs durability", item and item[36] == 20)
local tip_reads = 0
local full_tip = false
_G.C_Item = {
	GetItemInfo = function(id)
		if id == 25 then
			return "Worn Shortsword", "item:25", 1, 2, 1, "Weapon", "Sword", 1, "INVTYPE_WEAPON", 135274, 8, 2, 7, 1, nil, nil, false
		end
	end,
}
_G.C_TooltipInfo = {
	GetItemByID = function(id)
		if id ~= 25 then
			return nil
		end
		tip_reads = tip_reads + 1
		if not full_tip then
			return { lines = { { leftText = "Worn Shortsword" } } }
		end
		return { lines = { { leftText = "Worn Shortsword" }, { leftText = "47 Armor" } } }
	end,
}
local growing = load_addon()
growing.world.reset()
growing.items.record(25, "bag")
full_tip = true
growing.items.record(25, "bag")
local sword = growing.world.document().items[1]
check("later tooltip lines still fill an item", sword and sword[31] == 47)
local reads_after_fill = tip_reads
growing.items.record(25, "equipped")
growing.items.record(25, "bag")
check("stable item tooltip is skipped after two matching reads", tip_reads == reads_after_fill + 1)
_G.C_Spell = nil
_G.C_SpellBook = nil
_G.GetSpellBaseCooldown = nil
_G.GetSpellSchool = nil
_G.GetInventoryItemID = nil
_G.C_Item = nil
_G.C_TradeSkillUI = nil
_G.C_TooltipInfo = nil
_G.ITEM_MIN_SKILL = nil
_G.ARMOR_TEMPLATE = nil
_G.DAMAGE_TEMPLATE = nil
_G.DAMAGE_TEMPLATE_WITH_SCHOOL = nil
_G.SINGLE_DAMAGE_TEMPLATE = nil
_G.SPEED_TEMPLATE = nil
_G.SHIELD_BLOCK_TEMPLATE = nil
_G.DURABILITY_TEMPLATE = nil
_G.ITEM_SPELL_TRIGGER_ONUSE = nil
_G.ITEM_SPELL_TRIGGER_ONEQUIP = nil
_G.ITEM_SPELL_TRIGGER_ONPROC = nil
_G.ITEM_SET_NAME = nil
_G.ITEM_SET_BONUS_GRAY = nil
_G.ITEM_CLASSES_ALLOWED = nil
_G.ITEM_RACES_ALLOWED = nil
_G.ITEM_REQ_REPUTATION = nil
_G.FACTION_STANDING_LABEL6 = nil
_G.C_Reputation = nil
_G.C_CreatureInfo = nil
_G.EverlookDB = nil

local schematic_reads = 0
local full_schematic = false
_G.C_TradeSkillUI = {
	GetAllRecipeIDs = function()
		return { 2524 }
	end,
	GetBaseProfessionInfo = function()
		return { professionID = 164, professionName = "Blacksmithing" }
	end,
	GetRecipeInfo = function()
		return { name = "Copper Tube" }
	end,
	GetRecipeSchematic = function()
		schematic_reads = schematic_reads + 1
		if not full_schematic then
			return {}
		end
		return {
			outputItemID = 2840,
			quantityMin = 1,
			quantityMax = 1,
			reagentSlotSchematics = {
				{ quantityRequired = 1, reagents = { { itemID = 2840 } } },
			},
		}
	end,
}
local smith = load_addon()
smith.world.reset()
smith.recipes.scan()
full_schematic = true
smith.recipes.scan()
local tube = smith.world.document().recipes[1]
check("recipe reagents arrive after the schematic loads", tube and tube[1] == 2524 and tube[4] == 2840 and tube[11] and tube[11][1][1] == 2840 and tube[11][1][2] == 1)
local reads_after_recipe = schematic_reads
smith.recipes.scan()
check("loaded recipe schematic is not read again", schematic_reads == reads_after_recipe)
local skill_stores = 0
local store_world = smith.world.store
smith.world.store = function(bucket, row)
	if bucket == "skillLines" then
		skill_stores = skill_stores + 1
	end
	return store_world(bucket, row)
end
smith.recipes.scan()
check("unchanged profession is not stored again", skill_stores == 0)
_G.C_TradeSkillUI = {
	GetAllRecipeIDs = function()
		return { 4036 }
	end,
	GetBaseProfessionInfo = function()
		return {
			professionID = 2872,
			professionName = "Khaz Algar Engineering",
			parentProfessionID = 202,
			parentProfessionName = "Engineering",
		}
	end,
	GetRecipeInfo = function()
		return { name = "Rough Blasting Powder" }
	end,
	GetRecipeSchematic = function()
		return {
			outputItemID = 4357,
			quantityMin = 1,
			quantityMax = 1,
			reagentSlotSchematics = {
				{ quantityRequired = 1, reagents = { { itemID = 2836 } } },
			},
		}
	end,
}
smith = load_addon()
smith.world.reset()
smith.recipes.scan()
tube = smith.world.document().recipes[1]
check("recipe uses the parent profession skill line", tube and tube[1] == 4036 and tube[3] == 202)
tube = smith.world.document().skillLines[1]
check("parent profession is stored under its own name", tube and tube[1] == 202 and tube[2] == "Engineering" and tube[3] == true)
_G.C_TradeSkillUI = nil

_G.C_Reputation = {
	GetNumFactions = function()
		return 2
	end,
	GetFactionDataByIndex = function(index)
		if index == 1 then
			return { factionID = 72, name = "Stormwind", parentFactionID = 469, isHeader = false }
		end
		if index == 2 then
			return { isHeader = true, name = "Alliance" }
		end
	end,
}
local factions = load_addon()
factions.world.reset()
local faction_stores = 0
local store_faction = factions.world.store
factions.world.store = function(bucket, row)
	if bucket == "factions" then
		faction_stores = faction_stores + 1
	end
	return store_faction(bucket, row)
end
factions.factions.scan()
local faction_row = factions.world.document().factions[1]
check("faction scan packs the name and parent", faction_row and faction_row[1] == 72 and faction_row[2] == "Stormwind" and faction_row[3] == 469 and faction_stores == 1)
factions.factions.scan()
check("unchanged faction scan does not store again", faction_stores == 1)
local faction_reads = 0
local read_faction = _G.C_Reputation.GetFactionDataByIndex
_G.C_Reputation.GetFactionDataByIndex = function(index)
	faction_reads = faction_reads + 1
	return read_faction(index)
end
factions.factions.scan()
check("unchanged faction list is not reread", faction_reads == 0)
_G.C_Reputation = nil

_G.GetNumQuestItems = function()
	return 1
end
_G.GetQuestItemInfo = function(kind, index)
	if kind == "required" and index == 1 then
		return "Hogger's Head", nil, 1, nil, nil, 1934
	end
end
local needed = load_addon()
needed.world.reset()
needed.quests.record(176, "progress", { title = "Wanted: Hogger" })
local needed_world = needed.world.document()
local needed_quest = needed_world.quests[1]
local head
for i = 1, #(needed_world.items or {}) do
	if needed_world.items[i][1] == 1934 then
		head = needed_world.items[i]
	end
end
check("quest progress records the required item", needed_quest and needed_quest[23] and needed_quest[23][1][1] == 1934 and needed_quest[23][1][2] == 1 and head and head[2] == "Hogger's Head")
_G.GetNumQuestItems = nil
_G.GetQuestItemInfo = nil

_G.C_Container = {
	GetContainerNumSlots = function()
		return 1
	end,
	GetContainerItemID = function()
		return 769
	end,
	GetContainerItemQuestInfo = function()
		return { questID = 54, isActive = false, isQuestItem = false }
	end,
}
_G.C_QuestLog = {
	GetTitleForQuestID = function(id)
		if id == 54 then
			return "Hogger's Trail"
		end
	end,
}
local starter = load_addon()
starter.world.reset()
starter.items.scan_bags()
local starter_world = starter.world.document()
local letter
local trail
for i = 1, #(starter_world.items or {}) do
	if starter_world.items[i][1] == 769 then
		letter = starter_world.items[i]
	end
end
for i = 1, #(starter_world.quests or {}) do
	if starter_world.quests[i][1] == 54 then
		trail = starter_world.quests[i]
	end
end
local function starter_text(value)
	if type(value) == "number" and type(starter_world.s) == "table" then
		return starter_world.s[value]
	end
	return value
end
check("bag item that starts a quest records the quest", letter and letter[20] == 54 and trail and trail[17] and starter_text(trail[17][1][1]) == "item" and trail[17][1][2] == 769)
_G.C_Container = nil
_G.C_QuestLog = nil

local bag_quest_reads = 0
local bag_active = false
_G.Enum = { BagIndex = { Backpack = 0, Bag_4 = 0 } }
_G.C_Item = {
	GetItemInfo = function(id)
		if id == 117 or id == 769 then
			return "Bag Item", "item:" .. id, 1, 1, 1, "Miscellaneous", "Junk", 1, "", 134400, 0, 15, 0, 0
		end
	end,
}
_G.C_TooltipInfo = {
	GetItemByID = function()
		return { lines = { { leftText = "Bag Item" } } }
	end,
}
_G.C_Container = {
	GetContainerNumSlots = function()
		return 2
	end,
	GetContainerItemID = function(_, slot)
		if slot == 1 then
			return 117
		end
		return 769
	end,
	GetContainerItemQuestInfo = function(_, slot)
		bag_quest_reads = bag_quest_reads + 1
		if slot == 2 and not bag_active then
			return { questID = 54, isActive = false, isQuestItem = false }
		end
		if slot == 2 then
			return { questID = 54, isActive = true, isQuestItem = true }
		end
		return {}
	end,
}
_G.C_QuestLog = {
	GetTitleForQuestID = function(id)
		if id == 54 then
			return "Hogger's Trail"
		end
	end,
}
local quiet_bags = load_addon()
quiet_bags.world.reset()
local bag_records = 0
local record_bag_quest = quiet_bags.quests.record
quiet_bags.quests.record = function(id, source, extra)
	bag_records = bag_records + 1
	return record_bag_quest(id, source, extra)
end
quiet_bags.items.scan_bags()
local bag_records_after = bag_records
quiet_bags.items.scan_bags()
local bag_reads_settled = bag_quest_reads
check("unchanged bag does not record the quest again", bag_records == bag_records_after and bag_records_after > 0)
quiet_bags.items.scan_bags()
check("settled plain bag slot skips the quest lookup", bag_quest_reads == bag_reads_settled + 1 and bag_records == bag_records_after)
bag_active = true
quiet_bags.items.scan_bags()
check("accepted bag quest item is recorded again", bag_records > bag_records_after)
_G.Enum = nil
_G.C_Item = nil
_G.C_TooltipInfo = nil
_G.C_Container = nil
_G.C_QuestLog = nil

local hover_reads = 0
_G.GetTime = function()
	return 1000
end
_G.UnitGUID = function()
	hover_reads = hover_reads + 1
	return "GameObject-0-1-0-2-1731-abc"
end
_G.UnitIsPlayer = function()
	return false
end
local hover = load_addon()
hover.world.reset()
hover.npcs.on_mouseover()
local hover_node = hover.world.document().objects
local hover_after = hover_reads
check("mouseover reads the guid once", hover_reads == 1 and hover_node and hover_node[1][1] == 1731)
hover.npcs.on_mouseover()
check("repeat mouseover does not read the guid again for objects", hover_reads == hover_after + 1)
_G.GetTime = nil
_G.UnitGUID = nil
_G.UnitIsPlayer = nil

local mouse_parses = 0
_G.GetTime = function()
	return 1000
end
_G.UnitGUID = function()
	return "Player-1-2"
end
_G.UnitIsPlayer = function()
	return true
end
local players = load_addon()
players.world.reset()
local parse_mouse = players.world.guid_id
players.world.guid_id = function(guid, kind)
	mouse_parses = mouse_parses + 1
	return parse_mouse(guid, kind)
end
players.npcs.on_mouseover()
check("player mouseover does not parse an object guid", mouse_parses == 0 and players.world.document().objects == nil)
_G.GetTime = nil
_G.UnitGUID = nil
_G.UnitIsPlayer = nil

local player_checks = 0
local object_ids = 0
_G.GetTime = function()
	return 1000
end
_G.UnitIsPlayer = function(unit)
	player_checks = player_checks + 1
	return unit == "mouseover"
end
_G.UnitGUID = function(unit)
	if unit == "mouseover" then
		return "Player-1-2"
	end
	return "GameObject-0-1-0-2-1731-abc"
end
local skipped = load_addon()
skipped.world.reset()
skipped.npcs.record("mouseover", "mouseover")
skipped.npcs.record("mouseover", "mouseover")
check("repeat player mouseover skips the unit", player_checks == 1 and skipped.world.document().npcs == nil)
local creature_id = skipped.npcs.creature_id
skipped.npcs.creature_id = function(guid)
	object_ids = object_ids + 1
	return creature_id(guid)
end
skipped.npcs.record("target", "target")
local ids_after = object_ids
skipped.npcs.record("target", "target")
check("repeat non-creature target skips the guid", object_ids == ids_after and ids_after == 1)
_G.GetTime = nil
_G.UnitIsPlayer = nil
_G.UnitGUID = nil

local object_parses = 0
_G.GetTime = function()
	return 1000
end
local watched = load_addon()
watched.world.reset()
local parse_guid = watched.world.guid_id
watched.world.guid_id = function(guid, kind)
	object_parses = object_parses + 1
	return parse_guid(guid, kind)
end
watched.objects.watch("Creature-0-1-0-2-448-abc")
local parses_after = object_parses
watched.objects.watch("Creature-0-1-0-2-448-abc")
check("repeat creature mouseover skips the object guid", object_parses == parses_after and parses_after == 1 and watched.world.document().objects == nil)
_G.C_Map = {
	GetBestMapForUnit = function()
		return 37
	end,
	GetPlayerMapPosition = function()
		return { x = 0.5, y = 0.25 }
	end,
}
_G.C_TooltipInfo = {
	GetUnit = function()
		return { lines = { { leftText = "Copper Vein" }, { leftText = "Requires Mining (1)" } } }
	end,
}
watched.objects.watch("GameObject-0-1-0-2-1731-abc")
local watched_objects = watched.world.document().objects
check("object mouseover still records a node", watched_objects and watched_objects[1][1] == 1731 and watched_objects[1][3] == "mining")
_G.GetTime = nil
_G.C_Map = nil
_G.C_TooltipInfo = nil

;(function()
	local secret_clock = 0
	_G.GetTime = function()
		secret_clock = secret_clock + 1
		return 1000
	end
	_G.UnitGUID = function()
		return "secret"
	end
	_G.UnitIsPlayer = function()
		return false
	end
	local hidden = load_addon()
	hidden.world.reset()
	secret_clock = 0
	local nameplate_ok = pcall(hidden.npcs.record, "nameplate1", "nameplate")
	local mouse_ok = pcall(hidden.npcs.on_mouseover)
	local watch_ok = pcall(hidden.objects.watch, "secret")
	check("a secret unit guid does not throw or start a sighting", nameplate_ok and mouse_ok and watch_ok and secret_clock == 0 and hidden.world.document().npcs == nil and hidden.world.document().objects == nil)
	_G.UnitGUID = function()
		return "Creature-0-1-0-2-448-abc"
	end
	_G.UnitName = function()
		return "Hogger"
	end
	hidden.npcs.record("nameplate1", "nameplate")
	local revealed = hidden.world.document().npcs
	check("a plain creature guid still records after a secret one", revealed and revealed[1][1] == 448 and revealed[1][2] == "Hogger")
	_G.GetTime = nil
	_G.UnitGUID = nil
	_G.UnitIsPlayer = nil
	_G.UnitName = nil
end)()

local guid_parses = 0
local cached_ids = load_addon()
local read_guid = cached_ids.world.guid_id
cached_ids.world.guid_id = function(guid, kind)
	guid_parses = guid_parses + 1
	return read_guid(guid, kind)
end
local cached_creature = cached_ids.npcs.creature_id("Creature-0-1-0-2-448-abc")
local creature_parses = guid_parses
cached_ids.npcs.creature_id("Creature-0-1-0-2-448-abc")
check("repeat creature guid uses the cached id", cached_creature == 448 and guid_parses == creature_parses and creature_parses == 1)
cached_ids.npcs.creature_id("Player-1-2")
local player_parses = guid_parses
cached_ids.npcs.creature_id("Player-1-2")
check("repeat player guid is not parsed again", guid_parses == player_parses and cached_ids.npcs.creature_id("Player-1-2") == nil)

local class_reads = 0
local clock = { now = 1000 }
_G.GetTime = function()
	return clock.now
end
_G.UnitGUID = function()
	return "Creature-0-1-0-2-448-abc"
end
_G.UnitIsPlayer = function()
	return false
end
_G.UnitName = function()
	return "Hogger"
end
_G.UnitLevel = function()
	return 11
end
_G.UnitClassification = function()
	class_reads = class_reads + 1
	return "elite"
end
_G.UnitCreatureType = function()
	return "Humanoid"
end
_G.UnitHealthMax = function()
	return 400
end
_G.C_Map = {
	GetBestMapForUnit = function()
		return 37
	end,
	GetPlayerMapPosition = function()
		return { x = 0.5, y = 0.25 }
	end,
}
local settled_npc = load_addon()
settled_npc.world.reset()
settled_npc.npcs.record("target", "target")
local class_after = class_reads
clock.now = 1006
settled_npc.npcs.record("target", "target")
local settled_row = settled_npc.world.document().npcs[1]
check("settled npc sighting skips unit fields", class_reads == class_after and class_after == 1 and settled_row and settled_row[6] == "elite" and settled_row[17] and settled_row[17][1][4] == 2)
local reaction_value
_G.UnitReaction = function()
	return reaction_value
end
_G.UnitFactionGroup = function(unit)
	if unit == "player" then
		return "Alliance"
	end
end
local reaction_npc = load_addon()
reaction_npc.world.reset()
reaction_npc.npcs.record("target", "target")
clock.now = 1012
local reaction_reads = class_reads
reaction_npc.npcs.record("target", "target")
reaction_value = 4
clock.now = 1018
reaction_npc.npcs.record("target", "target")
local reaction_row = reaction_npc.world.document().npcs[1]
check("npc stays unsettled until its reaction is known", class_reads > reaction_reads and reaction_row and reaction_row[11] == 4)
_G.GetTime = nil
_G.UnitGUID = nil
_G.UnitIsPlayer = nil
_G.UnitName = nil
_G.UnitLevel = nil
_G.UnitClassification = nil
_G.UnitCreatureType = nil
_G.UnitHealthMax = nil
_G.UnitReaction = nil
_G.UnitFactionGroup = nil
_G.C_Map = nil

;(function()
	local talents = load_addon()
	talents.world.reset()
	_G.UnitClass = function()
		return "Paladin", "PALADIN", 2
	end
	_G.GetNumTalentTabs = function()
		return 1
	end
	_G.GetTalentTabInfo = function()
		return "Holy"
	end
	_G.GetNumTalents = function()
		return 1
	end
	_G.GetTalentInfo = function()
		return "Divine Strength", 135984, 1, 2, 0, 5
	end
	_G.GetTalentLink = function()
		return "|cff71d5ff|Hspell:20262|h[Divine Strength]|h|r"
	end
	_G.GetTalentPrereqs = function()
		return 1, 1
	end
	talents.talents.scan()
	local row = talents.world.document().talents[1]
	check("talent scan stores the tree, ranks, and spell", row and row[1] == 20262 and row[2] == "Divine Strength" and row[4] == 2 and row[6] == "Holy" and row[8] == 1 and row[9] == 2 and row[10] == 5 and row[12] == 20262 and row[13] == 1 and row[14] == 1)
	_G.UnitClass = nil
	_G.GetNumTalentTabs = nil
	_G.GetTalentTabInfo = nil
	_G.GetNumTalents = nil
	_G.GetTalentInfo = nil
	_G.GetTalentLink = nil
	_G.GetTalentPrereqs = nil
end)()

;(function()
	local signed = load_addon()
	_G.EverlookDB = { secret = "upload-secret" }
	_G.C_EncodingUtil = {
		SerializeCBOR = function()
			return "cbor"
		end,
		EncodeBase64 = function()
			return "QUJD"
		end,
	}
	signed.world.reset()
	signed.world.store("maps", { id = 1, name = "Elwynn" })
	signed.world.flush()
	local db = _G.EverlookDB
	check("upload secret signs the world file and stays out of it", type(db.signer) == "string" and #db.signer == 16 and type(db.signature) == "string" and db.world and not db.world:find("upload-secret", 1, true))
	_G.C_EncodingUtil = nil
	_G.Enum = nil
	_G.EverlookDB = nil
end)()

;(function()
	local signed = load_addon()
	_G.EverlookDB = {}
	signed.config.token = "from-sign-lua"
	_G.C_EncodingUtil = {
		SerializeCBOR = function()
			return "cbor"
		end,
		EncodeBase64 = function()
			return "QUJD"
		end,
	}
	signed.world.reset()
	signed.world.store("maps", { id = 1, name = "Elwynn" })
	signed.world.flush()
	local db = _G.EverlookDB
	check("sign.lua token signs the world file", type(db.signer) == "string" and #db.signer == 16 and type(db.signature) == "string")
	check("sign.lua token is stored as the account secret", db.secret == "from-sign-lua")
	_G.C_EncodingUtil = nil
	_G.Enum = nil
	_G.EverlookDB = nil
end)()

;(function()
	local function hashing()
		_G.C_EncodingUtil = {
			SerializeCBOR = function()
				return "cbor"
			end,
			EncodeBase64 = function()
				return "QUJD"
			end,
		}
	end
	local function save(addon)
		addon.world.reset()
		addon.world.store("maps", { id = 1, name = "Elwynn" })
		addon.world.flush()
	end

	local stale = load_addon()
	_G.EverlookDB = { secret = "stale-secret" }
	stale.config.token = "fresh-token"
	hashing()
	save(stale)
	check("sign.lua token beats a stale saved secret", _G.EverlookDB.secret == "fresh-token" and _G.EverlookDB.signer == "5e2040ab40dda85d")
	local fresh_signer = _G.EverlookDB.signer
	_G.EverlookDB = { secret = "fresh-token" }
	stale.config.token = nil
	save(stale)
	check("the token signs the same as the same secret typed by hand", _G.EverlookDB.signer == fresh_signer)

	local addon = load_addon()
	_G.EverlookDB = {}
	_G.C_EncodingUtil = nil
	_G.Enum = nil
	check("no token reports no_token", addon.config.status() == "no_token")
	addon.config.token = "abc12345-token"
	check("a token without client hashing reports pending", addon.config.status() == "pending")
	hashing()
	check("a token before the first save reports pending", addon.config.status() == "pending" and addon.config.fingerprint() == nil)
	local _, waiting = addon.config.describe()
	check("the pending line names the token and when saves are signed", waiting:find(addon.hash.sha256("abc12345-token"):sub(1, 8), 1, true) ~= nil and waiting:find("log out", 1, true) ~= nil)
	save(addon)
	check("a signed save reports signed", addon.config.status() == "signed")
	check("the fingerprint is the first 8 characters of the signer", addon.config.fingerprint() == _G.EverlookDB.signer:sub(1, 8) and #addon.config.fingerprint() == 8)
	local _, line = addon.config.describe()
	check("the status line names the fingerprint", line:find(addon.config.fingerprint(), 1, true) ~= nil)
	check("the secret stays out of the world file", not _G.EverlookDB.world:find("abc12345-token", 1, true))

	-- A save is signed only at logout, so the next session reads the signature it left behind.
	local saved_db = _G.EverlookDB
	local next_session = load_addon()
	_G.EverlookDB = { secret = saved_db.secret, signer = saved_db.signer, signature = saved_db.signature, world = saved_db.world }
	next_session.config.token = "abc12345-token"
	check("the last session's signed save reports signed", next_session.config.status() == "signed" and next_session.config.fingerprint() == saved_db.signer:sub(1, 8))
	next_session.config.token = "a-newer-token"
	check("a save signed with another token reports pending", next_session.config.status() == "pending" and next_session.config.fingerprint() == nil)
	_G.C_EncodingUtil = nil
	_G.Enum = nil
	_G.EverlookDB = nil
end)()

;(function()
	local function collected_bucket(collected, bucket)
		for i = 1, #collected do
			if collected[i].bucket == bucket then
				return collected[i]
			end
		end
	end

	local function collected_text(bucket)
		local lines = {}
		for i = 1, #bucket.records do
			lines[i] = bucket.records[i].text .. "|" .. bucket.records[i].id
		end
		return table.concat(lines, ";")
	end

	local listed = load_addon()
	listed.world.reset()
	local empty = listed.world.collected()
	check("collected list starts empty", type(empty) == "table" and #empty == 0)

	listed.world.store("maps", { id = 37 })
	listed.world.store("items", { id = 2589, name = "Linen Cloth" })
	listed.world.store("items", { id = 769 })
	local linen = type(listed.world.row) == "function" and listed.world.row("items", 2589)
	check("a stored item can be read back", linen and linen.name == "Linen Cloth")
	listed.world.store("items", { id = 2589, startsQuestId = 7, isCraftingReagent = false })
	linen = type(listed.world.row) == "function" and listed.world.row("items", 2589)
	check("item flags stay on the stored row", linen and linen.startsQuestId == 7 and linen.isCraftingReagent == false)
	listed.world.store("npcs", { id = 448, name = "Hogger" })
	listed.world.store("npcs", { id = 6, name = "" })
	listed.world.store("quests", { id = 62, title = "The Fargodeep Mine" })
	listed.world.store("drops", { npcId = 448, itemId = 2589, drops = 2 })
	listed.world.store("drops", { npcId = 6, itemId = 769, drops = 1 })
	listed.world.store("drops", { npcId = 448, itemId = 117, drops = 1 })
	listed.world.store("fishingLoot", { mapId = 37, areaId = 9, itemId = 2589, areaName = "Northshire" })

	local collected = listed.world.collected()
	local order = {}
	for i = 1, #collected do
		order[i] = collected[i].bucket
	end
	check("collected buckets follow the world order and skip empty ones", table.concat(order, ",") == "maps,items,npcs,quests,drops,fishingLoot")

	local maps = collected_bucket(collected, "maps")
	local items = collected_bucket(collected, "items")
	local npcs = collected_bucket(collected, "npcs")
	local quests = collected_bucket(collected, "quests")
	local drops = collected_bucket(collected, "drops")
	local fishing = collected_bucket(collected, "fishingLoot")
	check("a row with no name is listed by its id", maps and maps.label == "Maps" and maps.count == 1 and collected_text(maps) == "37|37")
	check("named rows sort by name and keep the id", items and items.label == "Items" and collected_text(items) == "769|769;Linen Cloth|2589")
	check("an empty name falls back to the id", npcs and npcs.label == "Creatures" and collected_text(npcs) == "6|6;Hogger|448")
	check("a quest is listed by its title", quests and quests.label == "Quests" and collected_text(quests) == "The Fargodeep Mine|62")
	check("drops use collected creature and item names", drops and drops.label == "Drops" and drops.count == 3 and collected_text(drops) == "6, 769|6:769;Hogger, 117|448:117;Hogger, Linen Cloth|448:2589")
	check("fishing keeps the area name and the item name", fishing and fishing.label == "Fishing" and collected_text(fishing) == "Northshire, Linen Cloth|37:9:2589")

	listed.world.reset()
	check("reset clears the collected list", #listed.world.collected() == 0)
end)()

;(function()
	local addon = load_addon()
	_G.EverlookDB = {}
	_G.Enum = nil
	_G.C_EncodingUtil = {
		SerializeCBOR = function() return "cbor" end,
		EncodeBase64 = function() return "QUJD" end,
	}
	addon.config.token = "regression-token"
	check("a token works with only the documented encoding API", addon.config.status() == "pending")
	addon.world.reset()
	addon.world.store("maps", { id = 1, name = "Elwynn" })
	addon.world.flush()
	check("documented client signs the saved payload", _G.EverlookDB.signature == "756e9ac82957e3fe258b3a8805840879b89feda6dbada27b38eb29bc9c51d9e7")
	check("documented client derives the server signer", _G.EverlookDB.signer == "143ffa154ba1e4ee")
	check("documented client reports signed", addon.config.status() == "signed")
	_G.C_EncodingUtil = nil
	_G.EverlookDB = nil
end)()

-- A later sighting enriches a stored record and never makes it poorer.
;(function()
Everlook.world.reset()
Everlook.world.store("quests", {
	id = 14,
	title = "Wolves",
	starters = { { type = "npc", id = 1, name = "Deputy" } },
	rewards = { items = { { id = 5, quantity = 1 }, { id = 6, quantity = 2 } }, money = 50 },
	objectives = { { text = "a" }, { text = "b" } },
})
Everlook.world.store("quests", {
	id = 14,
	title = "Wolves",
	starters = { { type = "object", id = 9, name = "Poster" }, { type = "npc", id = 1, name = "Deputy" } },
	rewards = { items = {}, spells = { { id = 77 } } },
	objectives = { { text = "a" } },
})
local quest = Everlook.world.row("quests", 14)
check("starters from another sighting are added", #quest.starters == 2 and quest.starters[2].id == 9)
check("a sparser reward list keeps the fuller one", #quest.rewards.items == 2 and quest.rewards.money == 50)
check("a reward the later sighting read is added", quest.rewards.spells and quest.rewards.spells[1].id == 77)
check("a shorter objectives list never replaces a longer one", #quest.objectives == 2)
Everlook.world.store("quests", { id = 14, objectives = { { text = "a" }, { text = "b" }, { text = "c" } } })
check("a longer objectives list replaces a shorter one", #Everlook.world.row("quests", 14).objectives == 3)
Everlook.world.store("items", { id = 1, name = "Hearthstone", effects = { { text = "Teleports", trigger = 0 } } })
Everlook.world.store("items", { id = 1, name = "Unknown item 1", effects = {} })
check("a placeholder name never replaces a real one", Everlook.world.row("items", 1).name == "Hearthstone")
check("an empty list never blanks a stored one", #Everlook.world.row("items", 1).effects == 1)
Everlook.world.store("npcs", { id = 3, name = "Unknown NPC 3" })
Everlook.world.store("npcs", { id = 3, name = "Deputy Willem" })
check("a real name replaces a placeholder", Everlook.world.row("npcs", 3).name == "Deputy Willem")
Everlook.world.store("vendors", { npcId = 10, itemId = 20, price = 5, quantity = 20 })
Everlook.world.store("vendors", { npcId = 10, itemId = 20, price = 6, quantity = 20 })
Everlook.world.store("npcs", { id = 9, name = "Hogger", classification = "elite" })
Everlook.world.store("npcs", { id = 9, classification = "rare" })
check("a rare vignette does not undo an elite", Everlook.world.row("npcs", 9).classification == "elite")
Everlook.world.store("npcs", { id = 10, name = "Wolf", classification = "normal" })
Everlook.world.store("npcs", { id = 10, classification = "rare" })
check("a creature can be read up to rare", Everlook.world.row("npcs", 10).classification == "rare")
local stack
Everlook.world.each("vendors", function(_, row)
	stack = row.quantity
end)
check("a vendor's stack size is not summed like a counter", stack == 20)
check("a vendor's price follows the later sighting", (function()
	local price
	Everlook.world.each("vendors", function(_, row)
		price = row.price
	end)
	return price == 6
end)())
Everlook.world.reset()
end)()

-- Play must never walk the world. These hold the costs that grew with the data.
;(function()
	local world = load_addon().world
	world.reset()
	check("a fresh world counts no rows", world.row_count() == 0)
	world.store("npcs", { id = 1, name = "Zebra" })
	world.store("npcs", { id = 2, name = "apple" })
	world.store("npcs", { id = 3, name = "Mango" })
	world.store("npcs", { id = 3, name = "Mango", minLevel = 4 })
	world.store("items", { id = 9, name = "Sword" })
	check("the row count follows stores, and a repeat adds none", world.row_count() == 4)
	local buckets = world.collected_buckets()
	check("bucket counts come from the running totals", #buckets == 2 and buckets[1].bucket == "items" and buckets[1].count == 1 and buckets[2].bucket == "npcs" and buckets[2].count == 3)
	local records = world.collected_records("npcs")
	check("a listing sorts without regard to case", records[1].text == "apple" and records[2].text == "Mango" and records[3].text == "Zebra")
	check("a listing carries its lowered sort key", records[1].key == "apple" and records[3].key == "zebra")
	check("a listing is reused until a row appears", world.collected_records("npcs") == records)
	world.store("npcs", { id = 3, name = "Mango", maxLevel = 9 })
	check("a store that changes no printed text keeps the listing", world.collected_records("npcs") == records)
	world.store("npcs", { id = 4, name = "Bear" })
	local grown = world.collected_records("npcs")
	check("a new row rebuilds the listing", grown ~= records and #grown == 4 and grown[2].text == "Bear")
	world.store("npcs", { id = 4, name = "Aardvark" })
	check("a rename rebuilds the listing", world.collected_records("npcs")[1].text == "Aardvark")
	check("collected still lists every bucket with its records", #world.collected() == 2 and world.collected()[2].count == 4)
end)()

;(function()
	local world = load_addon().world
	world.reset()
	local expected = {}
	for step = 1, 40 do
		local pin = { mapId = 37 + step % 3, x = 100 + step, y = 200 + step % 7, role = step % 2 == 0 and 4 or nil }
		world.store("npcs", { id = 1, name = "Boar", locations = { pin } })
		expected[#expected + 1] = pin
	end
	local row = world.row("npcs", 1)
	check("every distinct pin of a long list is kept", #row.locations == 40)
	world.store("npcs", { id = 1, locations = { { mapId = 38, x = 101, y = 201 } } })
	local before = 0
	for index = 1, #row.locations do
		before = before + (row.locations[index].seen or 1)
	end
	check("a repeat pin in a long list only adds to seen", #row.locations == 40 and before == 41)
	world.store("npcs", { id = 1, locations = { { mapId = 38, x = 101, y = 201, role = 4 } } })
	check("the same spot with another role is its own pin", #row.locations == 41)
	world.store("npcs", { id = 1, locations = { { mapId = 38, x = 101.5, y = 201 } } })
	world.store("npcs", { id = 1, locations = { { mapId = 38, x = 101.5, y = 201 } } })
	check("a fractional spot is told apart and matched again", #row.locations == 42 and row.locations[42].seen == 2)
	world.store("npcs", { id = 1, locations = { { mapId = 38, x = 0, y = 0 } } })
	world.store("npcs", { id = 1, locations = { { mapId = 38 } } })
	check("a pin without coordinates is not the origin", #row.locations == 44)
	local saved = load_addon()
	saved.world.reset()
	local env_db = { raw = { npcs = { [1] = row } } }
	local loaded, loaded_env = load_addon()
	loaded_env.EverlookDB = env_db
	loaded.world.load_saved()
	loaded.world.store("npcs", { id = 1, locations = { { mapId = 38, x = 101, y = 201 } } })
	check("a list loaded from saved rows matches its pins too", #loaded.world.row("npcs", 1).locations == 44)
end)()

;(function()
	local addon, env = load_addon()
	local world = addon.world
	world.reset()
	world.store("npcs", { id = 10, name = "Hogger" })
	world.store("npcs", { id = 11, name = "Marshal" })
	world.store("quests", { id = 176, title = "Wanted", giverId = 10 })
	check("a giver lists its quest", world.lookup("npc", 10)[1] == "Quest: Wanted")
	world.store("quests", { id = 176, giverId = 11 })
	check("a new giver takes the quest from the old one", #world.lookup("npc", 10) == 0 and world.lookup("npc", 11)[1] == "Quest: Wanted")
	world.store("quests", { id = 176, turnInId = 10 })
	check("a turn-in lists the quest too", world.lookup("npc", 10)[1] == "Quest: Wanted")
	env.EverlookDB = { raw = { npcs = { [10] = { id = 10, name = "Hogger" } }, items = { [20] = { id = 20, name = "Cloth" } }, vendors = { ["10:20"] = { npcId = 10, itemId = 20 } }, drops = { ["10:20"] = { npcId = 10, itemId = 20, drops = 7 } } } }
	world.reset()
	world.load_saved()
	check("a tooltip says nothing until the index is built", #world.lookup("item", 20) == 0 or world.lookup("item", 20)[1] ~= nil)
	while world.index_step(1000) do
	end
	check("saved rows are indexed at load", world.lookup("item", 20)[1] == "Vendor: Hogger" and world.lookup("item", 20)[2] == "Dropped by Hogger (7)" and world.lookup("npc", 10)[1] == "Sells Cloth")
	check("loading counts the rows", world.row_count() == 4)
end)()

;(function()
	local hash = load_addon().hash
	check("SHA-256 empty input", hash.sha256("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
	check("SHA-256 abc", hash.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
	check("SHA-256 multi-block NIST vector", hash.sha256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq") == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
	-- RFC 4231 test cases cover binary keys and hashing a key over 64 bytes.
	check("HMAC-SHA-256 RFC case 1", hash.hmac_sha256(string.rep("\11", 20), "Hi There") == "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7")
	check("HMAC-SHA-256 RFC case 2", hash.hmac_sha256("Jefe", "what do ya want for nothing?") == "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
	check("HMAC-SHA-256 RFC case 6", hash.hmac_sha256(string.rep("\170", 131), "Test Using Larger Than Block-Size Key - Hash Key First") == "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54")
end)()

-- A sighting where the player already stood asks the game nothing and stores nothing.
;(function()
	local addon = load_addon()
	addon.world.reset()
	local reads, stores = 0, 0
	_G.C_MapExplorationInfo = { GetExploredAreaIDsAtPosition = function() reads = reads + 1 return { 87 } end }
	_G.C_Map = { GetAreaInfo = function() return "Northshire Valley" end }
	local store = addon.world.store
	addon.world.store = function(bucket, row)
		stores = stores + 1
		return store(bucket, row)
	end
	addon.location.note_area(12, 100, 200, "Nowhere")
	addon.location.note_area(12, 100, 200, "Nowhere")
	check("the same spot is read once", reads == 1 and stores == 1)
	addon.location.note_area(12, 101, 200, "Nowhere")
	check("a known area is read again but not stored again", reads == 2 and stores == 1)
	addon.world.store = store
	addon.world.reset()
	_G.EverlookDB = nil
	local fresh, fresh_env = load_addon()
	fresh_env.EverlookDB = { raw = { maps = { [12] = { id = 12, areas = { { id = 87, name = "Northshire Valley" } } } } } }
	fresh.world.load_saved()
	local saved_stores = 0
	local fresh_store = fresh.world.store
	fresh.world.store = function(bucket, row)
		saved_stores = saved_stores + 1
		return fresh_store(bucket, row)
	end
	fresh.location.note_area(12, 100, 200, "Nowhere")
	check("an area saved last session is not stored again", saved_stores == 0)
	_G.C_MapExplorationInfo = nil
	_G.C_Map = nil
end)()

-- An empty name map is a miss that is not retried on every item.
;(function()
	_G.ITEM_REQ_REPUTATION = "Requires %s - %s"
	local calls = 0
	_G.C_Reputation = { GetFactionDataByID = function() calls = calls + 1 end }
	local now = 100
	_G.GetTime = function() return now end
	_G.C_Item = { GetItemInfo = function(id) return "Item " .. id end }
	_G.C_TooltipInfo = { GetItemByID = function() return { lines = { { leftText = "Requires Stormwind - Honored" } } } end }
	_G.FACTION_STANDING_LABEL6 = "Honored"
	local addon = load_addon()
	addon.world.reset()
	addon.items.record(1, "bag")
	local first = calls
	addon.items.record(2, "bag")
	check("an empty faction map is scanned once", first == 2500 and calls == first)
	now = 140
	addon.items.record(3, "bag")
	check("an empty faction map is scanned again after a wait", calls == first * 2)
	_G.ITEM_REQ_REPUTATION, _G.C_Reputation, _G.GetTime, _G.C_Item, _G.C_TooltipInfo, _G.FACTION_STANDING_LABEL6 = nil, nil, nil, nil, nil, nil
end)()

-- A loot window or a vendor hands over many unread items. They are read a few a frame.
;(function()
	local timers = {}
	_G.C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
	local ticks = 0
	_G.debugprofilestop = function() ticks = ticks + 0.6 return ticks end
	_G.C_Item = { GetItemInfo = function(id) return "Item " .. id end }
	local addon = load_addon()
	addon.world.reset()
	for id = 1, 5 do
		addon.items.record(id, "loot")
	end
	addon.items.record(1, "loot")
	check("unread items wait for their turn", addon.world.row("items", 1) == nil and #timers == 1)
	local before = addon.world.row_count()
	timers[1]()
	check("a frame reads only what fits the budget", addon.world.row_count() - before >= 1 and addon.world.row_count() - before < 5 and #timers == 2)
	while #timers > 0 do
		table.remove(timers, 1)()
	end
	check("every queued item is read once", addon.world.row_count() == 5 and addon.world.row("items", 5).name == "Item 5")
	addon.items.record(6, "loot")
	check("a later item starts the queue again", #timers == 1)
	_G.C_Timer, _G.debugprofilestop, _G.C_Item = nil, nil, nil
end)()

-- A slow logout can be read back from the saved file.
;(function()
	local addon, env = load_addon()
	local ticks = 0
	env.debugprofilestop = function()
		ticks = ticks + 2
		return ticks
	end
	env.EverlookDB = {}
	env.C_EncodingUtil = {
		SerializeCBOR = function() return "cbor" end,
		EncodeBase64 = function(value) return value end,
		CompressString = function() return "z" end,
	}
	addon.world.reset()
	addon.world.store("npcs", { id = 1, name = "A" })
	addon.world.flush(true)
	local stats = env.EverlookDB.flushStats
	check("a flush saves how long each step took", type(stats) == "table" and stats.document and stats.cbor and stats.base64 and stats.compress and stats.sign and stats.rows == 1 and stats.bytes == #env.EverlookDB.world)
	env.debugprofilestop = nil
	env.EverlookDB = {}
	addon.world.store("npcs", { id = 2, name = "B" })
	addon.world.flush(true)
	check("a client without the clock still flushes", env.EverlookDB.world ~= nil and env.EverlookDB.flushStats == nil)
end)()

-- The game has a bit library, and the hash takes a faster path when it does.
-- This one follows LuaBitOp: every result is a signed 32-bit number.
;(function()
	local range = 4294967296
	local function signed(value)
		value = value % range
		if value >= 2147483648 then
			value = value - range
		end
		return value
	end
	local function combine(left, right, keep)
		left, right = left % range, right % range
		local result, place = 0, 1
		for _ = 1, 32 do
			if keep(left % 2, right % 2) then
				result = result + place
			end
			left, right, place = (left - left % 2) / 2, (right - right % 2) / 2, place * 2
		end
		return signed(result)
	end
	local shim = {
		band = function(left, right) return combine(left, right, function(a, b) return a == 1 and b == 1 end) end,
		bor = function(left, right) return combine(left, right, function(a, b) return a == 1 or b == 1 end) end,
		bxor = function(left, right) return combine(left, right, function(a, b) return a ~= b end) end,
		bnot = function(value) return signed(-1 - value) end,
		lshift = function(value, count) return signed((value % range) * 2 ^ (count % 32)) end,
		rshift = function(value, count) return signed(math.floor((value % range) / 2 ^ (count % 32))) end,
	}
	_G.bit = shim
	local fast = load_addon().hash
	_G.bit = nil
	local slow = load_addon().hash
	check("the bit library carries the hash, and a missing one does not", fast.fast == true and slow.fast == false)
	check("SHA-256 abc with a bit library", fast.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
	check("SHA-256 empty with a bit library", fast.sha256("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
	check("SHA-256 multi-block with a bit library", fast.sha256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq") == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
	check("HMAC-SHA-256 RFC case 2 with a bit library", fast.hmac_sha256("Jefe", "what do ya want for nothing?") == "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
	check("HMAC-SHA-256 RFC case 6 with a bit library", fast.hmac_sha256(string.rep("\170", 131), "Test Using Larger Than Block-Size Key - Hash Key First") == "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54")
	-- Lengths around the block and padding edges, and a body of several blocks.
	local agree = true
	for _, length in ipairs({ 55, 56, 63, 64, 65, 119, 120, 128, 200 }) do
		local body = {}
		for index = 1, length do
			body[index] = string.char((index * 37 + length) % 256)
		end
		body = table.concat(body)
		if fast.sha256(body) ~= slow.sha256(body) or fast.hmac_sha256("key", body) ~= slow.hmac_sha256("key", body) then
			agree = false
		end
	end
	check("both hash paths agree at every padding edge", agree)
	-- A long message can be hashed a few blocks at a time.
	local streams = true
	for _, lib in ipairs({ fast, slow }) do
		for _, length in ipairs({ 0, 1, 55, 56, 63, 64, 65, 127, 128, 129, 400, 1000 }) do
			local body = string.rep("q", length)
			for _, blocks in ipairs({ 1, 2, 5, 1000 }) do
				local walker = lib.stream(body)
				local steps = 0
				while not walker:step(blocks) do
					steps = steps + 1
				end
				if walker:hex() ~= lib.sha256(body) or steps > length / 64 / blocks + 1 then
					streams = false
				end
				local signer = lib.hmac_stream(lib.hmac_key("secret"), body)
				while not signer:step(blocks) do end
				if signer:hex() ~= lib.hmac_sha256("secret", body) then
					streams = false
				end
			end
		end
	end
	check("a stepped hash equals the one-shot hash at every length and step size", streams)
	check("a stepped HMAC matches the RFC vector", (function()
		local signer = fast.hmac_stream(fast.hmac_key(string.rep("\170", 131)), "Test Using Larger Than Block-Size Key - Hash Key First")
		while not signer:step(1) do end
		return signer:hex() == "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54"
	end)())
	-- A bit library that does not behave must not reach the signature.
	_G.bit = { band = shim.band, bor = shim.bor, bxor = function(left, right) return shim.bxor(left, right) + 1 end, bnot = shim.bnot, lshift = shim.lshift, rshift = shim.rshift }
	local broken = load_addon().hash
	_G.bit = nil
	check("a misbehaving bit library falls back to the portable hash", broken.fast == false and broken.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" and broken.hmac_sha256("Jefe", "what do ya want for nothing?") == "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
	-- bit32 hands back unsigned numbers.
	_G.bit32 = { band = function(a, b) return shim.band(a, b) % range end, bor = function(a, b) return shim.bor(a, b) % range end, bxor = function(a, b) return shim.bxor(a, b) % range end, bnot = function(a) return shim.bnot(a) % range end, lshift = function(a, n) return shim.lshift(a, n) % range end, rshift = function(a, n) return shim.rshift(a, n) % range end }
	local unsigned = load_addon().hash
	_G.bit32 = nil
	check("an unsigned bit library hashes the same", unsigned.fast == true and unsigned.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" and unsigned.hmac_sha256(string.rep("\170", 131), "Test Using Larger Than Block-Size Key - Hash Key First") == "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54")
end)()

assert(loadfile(root .. "/tests/segments.lua"))()(root, check)
assert(loadfile(root .. "/tests/module.lua"))()(root, check)
assert(loadfile(root .. "/tests/qol.lua"))()(root, check)
assert(loadfile(root .. "/tests/waves.lua"))()(root, check)

if failed > 0 then
	print(failed .. " failed")
	os.exit(1)
end
print("ok")
