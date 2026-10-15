local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "quest_automation"

Everlook.quest_automation = {}

-- What to do at a quest window, from the facts alone: no call into the game, so every branch can be tested and
-- every "no" has its reason. `facts` holds the event, whether Shift or combat holds automation back, the three
-- options, and what the window shows. Returns an action, its argument, and a reason when the action is nothing.
-- Actions: select_active_gossip, select_available_gossip (quest id), select_active_greeting (index),
-- select_available_greeting (1), acknowledge, accept, complete, reward (choice index, 0 for none).
function Everlook.quest_automation.decide(facts)
	if facts.paused then return nil, nil, "paused" end
	if facts.in_combat then return nil, nil, "combat" end
	local event, options = facts.event, facts.options
	if event == "GOSSIP_SHOW" then
		if not facts.gossip then return nil, nil, "no gossip list" end
		if options.turn_in then
			for _, quest in ipairs(facts.gossip.active) do
				if quest.isComplete and (not quest.repeatable or options.repeatable) then return "select_active_gossip", quest.questID end
			end
		end
		if options.accept then
			for _, quest in ipairs(facts.gossip.available) do
				if not quest.isIgnored and (not quest.repeatable or options.repeatable) then return "select_available_gossip", quest.questID end
			end
		end
		return nil, nil, "nothing to pick"
	elseif event == "QUEST_GREETING" then
		if options.turn_in and facts.greeting and facts.greeting.active then
			for index, complete in ipairs(facts.greeting.active) do
				if complete then return "select_active_greeting", index end
			end
		end
		if options.accept and facts.greeting and (facts.greeting.available or 0) > 0 then return "select_available_greeting", 1 end
		return nil, nil, "nothing to pick"
	end
	if facts.repeatable_blocked then return nil, nil, "repeatable" end
	if event == "QUEST_DETAIL" then
		if not options.accept or not facts.can_accept then return nil, nil, "accepting is off" end
		if facts.pvp then return nil, nil, "pvp" end
		if facts.auto_accept then
			if facts.can_acknowledge then return "acknowledge" end
			return nil, nil, "auto-accepted"
		end
		return "accept"
	elseif event == "QUEST_PROGRESS" then
		if not options.turn_in or facts.costs_money then return nil, nil, "turning in is off or costs money" end
		if facts.completable then return "complete" end
		return nil, nil, "not complete"
	elseif event == "QUEST_COMPLETE" then
		if not options.turn_in or facts.costs_money or facts.choices == nil then return nil, nil, "turning in is off, costs money or has no count" end
		if facts.choices > 1 then return nil, nil, "choice of rewards" end
		return "reward", facts.choices == 1 and 1 or 0
	end
	return nil, nil, "not a quest window"
end

-- Without a repeatable check, leave the quest alone unless repeatable quests
-- are included. A missing gold cost is treated as paid.
local function repeatable()
	if not (C_QuestLog and C_QuestLog.IsRepeatableQuest and GetQuestID) then return not module.get(id, "repeatable") end
	return C_QuestLog.IsRepeatableQuest(GetQuestID()) and not module.get(id, "repeatable")
end

-- Whether the turn-in costs money. A cost the client does not report is treated as one.
local function costs_money()
	if not GetQuestMoneyToGet then return true end
	return GetQuestMoneyToGet() > 0
end

-- Reads what the open window shows, and only what the event needs.
local function read_facts(event)
	local facts = {
		event = event,
		paused = module.paused(),
		in_combat = InCombatLockdown and InCombatLockdown() or false,
		options = { accept = module.get(id, "accept"), turn_in = module.get(id, "turn_in"), repeatable = module.get(id, "repeatable") },
	}
	if facts.paused or facts.in_combat then return facts end
	if event == "GOSSIP_SHOW" then
		if C_GossipInfo then facts.gossip = { active = C_GossipInfo.GetActiveQuests(), available = C_GossipInfo.GetAvailableQuests() } end
	elseif event == "QUEST_GREETING" then
		local active = {}
		if GetNumActiveQuests then
			for index = 1, GetNumActiveQuests() do
				local _, complete = GetActiveTitle(index)
				active[index] = complete == true or complete == 1
			end
		end
		facts.greeting = { active = active, available = GetNumAvailableQuests and GetNumAvailableQuests() or 0 }
	else
		facts.repeatable_blocked = repeatable()
		facts.can_accept = AcceptQuest ~= nil
		facts.pvp = QuestFlagsPVP ~= nil and QuestFlagsPVP() or false
		facts.auto_accept = QuestGetAutoAccept ~= nil and QuestGetAutoAccept() or false
		facts.can_acknowledge = AcknowledgeAutoAcceptQuest ~= nil
		facts.costs_money = costs_money()
		facts.completable = IsQuestCompletable ~= nil and IsQuestCompletable() or false
		facts.choices = GetNumQuestChoices and GetNumQuestChoices() or nil
	end
	return facts
end

local ACTIONS = {
	select_active_gossip = function(quest_id) C_GossipInfo.SelectActiveQuest(quest_id) end,
	select_available_gossip = function(quest_id) C_GossipInfo.SelectAvailableQuest(quest_id) end,
	select_active_greeting = function(index) SelectActiveQuest(index) end,
	select_available_greeting = function(index) SelectAvailableQuest(index) end,
	acknowledge = function() AcknowledgeAutoAcceptQuest() end,
	accept = function() AcceptQuest() end,
	complete = function() CompleteQuest() end,
	reward = function(choice) GetQuestReward(choice) end,
}

local function automate(event)
	local action, argument = Everlook.quest_automation.decide(read_facts(event))
	if action then ACTIONS[action](argument) end
end

module.register({
	addon = addon_name, page = "quests", order = 40,
	id = id, name = "Quest automation",
	description = "When a gossip window, a greeting, the quest detail, or the turn-in window opens, this accepts or turns in the quest if the matching choice below is on. This stays quiet in combat or while you hold Shift, a gossip quest the client marks repeatable stays for you while Include repeatable quests is off, a greeting only opens its quest, a repeatable quest or one the game cannot classify stays for you on the detail and the turn-in window while that choice is off, a choice between rewards or a turn-in that costs money stays for you, a window already open waits for the next one, and turning this off leaves every quest window for you.",
	options = {
		accept = { name = "Accept quests", default = true, description = "Opens an available quest on a gossip window or a greeting, and accepts it on the quest detail. An ignored quest stays on the gossip window, a repeatable quest stays there while Include repeatable quests is off, a repeatable quest or one the game cannot classify stays on the detail while that choice is off, this stays quiet in combat or while you hold Shift, nothing happens when the client cannot accept it, turning a quest in stays on its own option, and turning this off leaves the next one." },
		turn_in = { name = "Turn in completed quests", default = true, description = "Opens a completed quest on a gossip window or a greeting, and turns it in on the turn-in window. A choice between rewards, a turn-in that costs money, or a cost the client cannot read stays for you, a repeatable quest stays on the gossip window while Include repeatable quests is off, a repeatable quest or one the game cannot classify stays on the turn-in window while that choice is off, accepting a quest stays on its own option, this stays quiet in combat or while you hold Shift, and turning this off leaves the next one." },
		repeatable = { name = "Include repeatable quests", default = false, description = "While this is on, a gossip quest the client marks repeatable is accepted or turned in when Accept quests or Turn in completed quests is on, and while this is off that quest stays for you. A greeting opens its quest without looking at this choice, the quest detail and the turn-in window follow this choice when the client can classify the quest, and when it has no repeatable check those windows stay for you while this is off." },
	},
	events = { "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE" },
	on_event = automate,
})
