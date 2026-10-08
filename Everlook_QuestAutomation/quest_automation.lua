local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "quest_automation"

-- Without a repeatable check, leave the quest alone unless repeatable quests
-- are included. A missing gold cost is treated as paid.
local function repeatable()
	if not (C_QuestLog and C_QuestLog.IsRepeatableQuest and GetQuestID) then return not module.get(id, "repeatable") end
	return C_QuestLog.IsRepeatableQuest(GetQuestID()) and not module.get(id, "repeatable")
end

local function paid()
	if not GetQuestMoneyToGet then return true end
	return GetQuestMoneyToGet() > 0
end

local function gossip()
	if not C_GossipInfo then return end
	if module.get(id, "turn_in") then
		for _, quest in ipairs(C_GossipInfo.GetActiveQuests()) do
			if quest.isComplete and (not quest.repeatable or module.get(id, "repeatable")) then
				C_GossipInfo.SelectActiveQuest(quest.questID)
				return
			end
		end
	end
	if module.get(id, "accept") then
		for _, quest in ipairs(C_GossipInfo.GetAvailableQuests()) do
			if not quest.isIgnored and (not quest.repeatable or module.get(id, "repeatable")) then
				C_GossipInfo.SelectAvailableQuest(quest.questID)
				return
			end
		end
	end
end

local function automate(event)
	if module.paused() or (InCombatLockdown and InCombatLockdown()) then return end
	if event == "GOSSIP_SHOW" then
		gossip()
	elseif event == "QUEST_GREETING" then
		if module.get(id, "turn_in") and GetNumActiveQuests then
			for index = 1, GetNumActiveQuests() do
				local _, complete = GetActiveTitle(index)
				if complete == true or complete == 1 then SelectActiveQuest(index); return end
			end
		end
		if module.get(id, "accept") and GetNumAvailableQuests and GetNumAvailableQuests() > 0 then SelectAvailableQuest(1) end
	elseif repeatable() then
		return
	elseif event == "QUEST_DETAIL" and module.get(id, "accept") and AcceptQuest then
		if QuestGetAutoAccept and QuestGetAutoAccept() then
			if AcknowledgeAutoAcceptQuest then AcknowledgeAutoAcceptQuest() end
		else AcceptQuest() end
	elseif event == "QUEST_PROGRESS" and module.get(id, "turn_in") and not paid() and IsQuestCompletable and IsQuestCompletable() then
		CompleteQuest()
	elseif event == "QUEST_COMPLETE" and module.get(id, "turn_in") and not paid() and GetNumQuestChoices then
		local choices = GetNumQuestChoices()
		if choices <= 1 then GetQuestReward(choices == 1 and 1 or 0) end
	end
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
