local addon_name = ...
local Everlook = Everlook
local kit = Everlook.island_feed_kit
local plain_number, now, option, dismiss, notify = kit.plain_number, kit.now, kit.option, kit.dismiss, kit.notify
local quests = Everlook.island_quests
local state = {}

-- Quest turn-ins, quests ready to hand in, the suggested next quest, and
-- offers to pin a quest.
local function log_ready()
	return C_QuestLog and C_QuestLog.GetNumQuestLogEntries
end

local function ready()
	if not option("feed_quest_ready") then
		if dismiss(state.ready_handle) then
			state.ready_handle, state.ready, state.announced, state.ready_latest = nil, nil, nil, nil
		end
		return
	end
	local rows = quests.ready_list()
	if not state.ready then
		if not log_ready() then return end
		state.ready, state.announced = {}, {}
		for index = 1, #rows do state.ready[rows[index].id] = true end
		return
	end
	local seen, announced, changed = {}, state.announced or {}, false
	for index = 1, #rows do seen[rows[index].id] = rows[index] end
	for index = 1, #rows do
		local row = rows[index]
		if not state.ready[row.id] then
			announced[row.id], state.ready_latest, changed = true, row.id, true
		end
		state.ready[row.id] = true
	end
	for id in pairs(state.ready) do
		if not seen[id] then state.ready[id] = nil end
	end
	for id in pairs(announced) do
		if not seen[id] then announced[id], changed = nil, true end
	end
	state.announced = announced
	local count, latest, fallback = 0, nil, nil
	for id in pairs(announced) do
		local row = seen[id]
		if row then
			count, fallback = count + 1, row
			if id == state.ready_latest then latest = row end
		end
	end
	latest = latest or fallback
	if latest then state.ready_latest = latest.id end
	if count == 0 then
		if state.ready_handle and dismiss(state.ready_handle) then state.ready_handle = nil end
		return
	end
	if not changed or not latest then return end
	local quest_id = latest.id
	state.ready_handle = notify({
		source = "everlook.quests", key = "ready", kind = "quest", persist = true,
		text = count == 1 and latest.title or (count .. " quests ready"),
		detail = "Ready to turn in",
		actions = {
			{ id = "view", label = "View quest", type = "callback", on_click = function()
				if QuestMapFrame_OpenToQuestDetails then QuestMapFrame_OpenToQuestDetails(quest_id) end
			end },
			{ id = "pin", label = "Pin", type = "callback", on_click = function()
				if Everlook.smart_island and Everlook.smart_island.pin_quest then Everlook.smart_island.pin_quest(quest_id) end
			end },
		},
	}) or state.ready_handle
end

local function next_quest()
	if not option("feed_quest_next") then
		if dismiss(state.next_handle) then
			state.next_handle, state.next_id, state.next_seen, state.next_toast = nil, nil, nil, nil
		end
		return
	end
	local suggestion = quests.suggestion()
	local id = suggestion and suggestion.id or nil
	if not state.next_seen then
		if not log_ready() then return end
		state.next_seen = true
		state.next_id = id
		return
	end
	if not suggestion then
		if dismiss(state.next_handle) then
			state.next_handle = nil
			state.next_id = nil
		end
		return
	end
	if id == state.next_id then return end
	state.next_id = id
	local time = now()
	local announce = not state.next_toast or time - state.next_toast >= 30
	if announce then state.next_toast = time end
	local quest_id = suggestion.id
	state.next_handle = notify({
		source = "everlook.quests", key = "next-quest", kind = "quest", persist = true,
		text = suggestion.title, detail = "Suggested next",
		presentation = announce and "toast" or "inbox",
		actions = {
			{ id = "pin", label = "Pin", type = "callback", on_click = function()
				if Everlook.smart_island and Everlook.smart_island.pin_quest then Everlook.smart_island.pin_quest(quest_id) end
			end },
			{ id = "skip", label = "Skip", type = "callback", on_click = function()
				if quests.skip(quest_id) then quests.refresh(true) end
			end },
		},
	})
end

-- Offers to pin a quest when the player's activity points at one: a quest just
-- accepted, progress on a quest that is not pinned, or the pinned quest done.
-- One offer at a time, not more than one a minute, and the same quest not again
-- for ten minutes.
local PIN_OFFER_GAP, PIN_QUEST_GAP = 60, 600

local PIN_REASONS = {
	accepted = "New quest",
	progress = "You are making progress here",
	finished = "Your pinned quest is done. Next best",
}

local function pin_suggestions()
	if not quests.take_activity then return end
	local items = quests.take_activity()
	if not option("feed_pin_suggest") or not option("quest_context") then
		if dismiss(state.pin_handle) then state.pin_handle = nil end
		return
	end
	local time = now()
	state.pin_seen = state.pin_seen or {}
	if state.pin_at and time - state.pin_at < PIN_OFFER_GAP then return end
	local priority = { finished = 3, accepted = 2, progress = 1 }
	local chosen
	for _, item in ipairs(items) do
		if not chosen or priority[item.kind] > priority[chosen.kind] then chosen = item end
	end
	if not chosen then return end
	local record
	local function fresh(candidate)
		return candidate and candidate.id ~= quests.pinned_id()
			and not (state.pin_seen[candidate.id] and time - state.pin_seen[candidate.id] < PIN_QUEST_GAP)
	end
	if chosen.kind == "finished" then
		-- The island's best guess comes first, then the route after it, and the
		-- first one not offered lately takes the pinned quest's place.
		local view = quests.view()
		local candidates = { view and view.current }
		for _, next_record in ipairs(quests.route(view)) do candidates[#candidates + 1] = next_record end
		for _, candidate in ipairs(candidates) do
			if fresh(candidate) then record = candidate; break end
		end
	else
		record = quests.record(chosen.id)
	end
	if not record or record.id == quests.pinned_id() then return end
	if state.pin_seen[record.id] and time - state.pin_seen[record.id] < PIN_QUEST_GAP then return end
	state.pin_seen[record.id], state.pin_at = time, time
	local quest_id = record.id
	state.pin_handle = notify({
		source = "everlook.quests", key = "pin-suggest", kind = "quest", duration = 12,
		text = "Pin " .. record.title .. "?", detail = PIN_REASONS[chosen.kind] .. ", " .. quests.where(record),
		actions = {
			{ id = "pin", label = "Pin", type = "callback", on_click = function(handle)
				if Everlook.smart_island and Everlook.smart_island.pin_quest then Everlook.smart_island.pin_quest(quest_id) end
				if Everlook.island and Everlook.island.dismiss then Everlook.island.dismiss(handle) end
			end },
			{ id = "later", label = "Not now", type = "callback", on_click = function(handle)
				if Everlook.island and Everlook.island.dismiss then Everlook.island.dismiss(handle) end
			end },
		},
	}) or state.pin_handle
end

local function turned_in(quest_id, _, money)
	quest_id = plain_number(quest_id)
	if not quest_id or quest_id < 1 or quest_id % 1 ~= 0 or not option("source_quest_completion") then return end
	local title = quests and quests.title and quests.title(quest_id)
	state.turnins = (state.turnins or 0) + 1
	local reward = plain_number(money)
	notify({
		text = "Quest completed", detail = title or ("Quest #" .. quest_id), kind = "quest", severity = "success",
		source = "everlook.quests", key = "turnin:" .. state.turnins, stack = "turnin",
		money = reward and reward > 0 and reward % 1 == 0 and reward or nil,
	})
end

local function after_quests()
	ready()
	next_quest()
	pin_suggestions()
end

Everlook.module.extend("smart_island", {
	id = "quest_notices", addon = addon_name, order = 10,
	options = {
		source_quest_completion = { name = "Show completed quests", default = false, description = "Shows a notice when you turn in a quest, with the quest name from your log and any copper reward. If the log no longer has the quest, the notice uses its number. A hidden quest id stays quiet.", presets = { Quiet = false, Standard = true, Informative = true } },
		feed_quest_ready = { name = "Quest ready", default = false, description = "Tells you when a quest in your log newly becomes ready to turn in, and those quests share one notice. Quests already ready when you turn this on stay quiet, the notice names the quest while only one quest that became ready after that first look is still ready and the count when more than one of those is still ready, it goes away when none of those are still ready, an older ready quest can remain, turning this off clears it, and the quest capsule can stay off.", presets = { Quiet = false, Standard = true, Informative = true } },
		feed_quest_next = { name = "Next quest", default = false, description = "Tells you when the suggested quest changes, and keeps one notice on it. The quest already suggested when you turn this on stays quiet. Another change within 30 seconds goes to the inbox without a toast. The notice goes away when nothing is suggested or you turn this off.", presets = { Quiet = false, Standard = false, Informative = true } },
		feed_pin_suggest = { name = "Suggest pinning quests", default = true, description = "Offers to pin a quest when you accept one, make progress on one that is not pinned, or finish the one you pinned. It offers the next best quest in that case. Not more than one offer a minute. Needs Show active quest.", presets = { Quiet = false, Standard = true, Informative = true } },
	},
	sections = { { name = "Notices", keys = { "source_quest_completion", "feed_quest_ready", "feed_quest_next", "feed_pin_suggest" } } },
	events = { "QUEST_ACCEPTED", "QUEST_TURNED_IN" },
	on_event = function(event, ...)
		if event == "QUEST_ACCEPTED" then
			if quests.note_accepted then quests.note_accepted(...) end
		else
			turned_in(...)
		end
	end,
	apply = function(enabled)
		if not enabled then state = {} end
	end,
	refresh = after_quests,
})
