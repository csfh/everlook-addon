local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local plates = Everlook.nameplates
local plain = plates.plain
local id = "quest_nameplates"
local SOURCE = "everlook_quests"

-- The game's own quest mark floats above a unit and an addon can neither move nor restyle it, so this offers the
-- nameplate view a small mark of its own, and the game's stays where it is. The game says whether a unit is part
-- of a quest you are on, and that is all this marks: who offers a quest you have not taken is not something the
-- game tells an addon about a unit.
local ATLAS = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Quest"
local FALLBACK = "Interface\\TargetingFrame\\PortraitQuestBadge"

-- The kinds of line a unit's tooltip has for a quest of yours: its title, and an objective such as "Defias Bandit
-- slain: 3/8". The game puts them there for a unit that is something to kill, loot, use or talk to for a quest.
local function quest_line_types()
	local kinds = Enum and Enum.TooltipDataLineType
	return (kinds and kinds.QuestTitle) or 17, (kinds and kinds.QuestObjective) or 8
end

-- Whether an objective line still has something to do. The game says so on the line when it can; failing that the
-- progress is in the text, as "3/8" or "40%", in every language. A line that says neither is taken as open.
local function objective_open(line)
	if line.completed == true then return false end
	local text = line.leftText
	if plain(text) and type(text) == "string" then
		local done, needed = text:match("(%d+)%s*/%s*(%d+)")
		if done and needed then return tonumber(done) < tonumber(needed) end
		local percent = text:match("(%d+)%s*%%")
		if percent then return tonumber(percent) < 100 end
	end
	return true
end

-- What a unit's tooltip says of your quests: "open" when it lists an objective with something left to do, "none"
-- when it lists none or only finished ones, and nil when there is no tooltip to read.
local function tooltip_state(unit)
	if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return nil end
	local data = C_TooltipInfo.GetUnit(unit)
	if not plain(data) or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
	local _, objective = quest_line_types()
	for _, line in ipairs(data.lines) do
		if plain(line) and type(line) == "table" then
			local kind = line.type
			if plain(kind) and kind == objective and objective_open(line) then return "open" end
		end
	end
	return "none"
end

-- A unit that belongs to a quest in your log with something still to do: a creature to kill or loot, an object or
-- item to use, someone to talk to or hand in to, or a quest boss. Its tooltip lists the objectives that are still
-- open, so that decides, and a creature stops being marked when its objective is done. For someone you cannot
-- attack, the game's own answer also counts, because it is true of a quest giver or a hand-in, which a tooltip does
-- not list. A player never is.
local function on_a_quest(unit)
	if not (UnitExists and UnitExists(unit)) then return false end
	local player = UnitIsPlayer and UnitIsPlayer(unit)
	if not plain(player) or player then return false end
	local ok, state = pcall(tooltip_state, unit)
	if ok and state == "open" then return true end
	local attackable = UnitCanAttack and UnitCanAttack("player", unit)
	-- An attackable unit whose tooltip answered is as done as the tooltip says. Without a tooltip, the game's answer.
	if plain(attackable) and attackable and ok and state ~= nil then return false end
	local related = C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest and C_QuestLog.UnitIsRelatedToActiveQuest(unit)
	if plain(related) and related then return true end
	local boss = UnitIsQuestBoss and UnitIsQuestBoss(unit)
	return plain(boss) and boss and true or false
end

local function lead(unit)
	if on_a_quest(unit) then return { atlas = ATLAS, file = FALLBACK } end
end

local function apply(enabled)
	if enabled then
		plates.provide({ source = SOURCE, order = 10, lead = lead })
	else
		plates.remove(SOURCE)
	end
end

module.register({
	addon = addon_name, page = "nameplates", order = 45,
	id = id,
	name = "Quest marks on nameplates",
	description = "Puts a quest mark beside the nameplate of a unit that is part of a quest you are on and still has something to do: a creature to kill or loot, an object or item to use, someone to talk to or hand in to, or a quest boss. A creature loses its mark when its objective is done. The game's own quest mark above the unit stays, because an addon cannot move or hide it. Who offers a quest you have not taken is not something the game tells an addon about a unit, so those get no mark. Where the mark goes and how wide it is are set under Nameplates, which does the placing and needs to be on for a mark to show.",
	options = {},
	apply = apply,
	events = { "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" },
	on_event = function() plates.refresh() end,
})
