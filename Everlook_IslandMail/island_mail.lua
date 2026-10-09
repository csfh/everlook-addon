local addon_name = ...
local Everlook = Everlook
local kit = Everlook.island_feed_kit
local plain_number, now, option, dismiss, notify = kit.plain_number, kit.now, kit.option, kit.dismiss, kit.notify
local state = {}

-- One notice while new mail is waiting, with what is in the box once it is open.
local function mail()
	if not option("feed_mail") then
		if dismiss(state.mail_handle) then state.mail_handle, state.mail_seen, state.mail, state.mail_snooze, state.mail_summary = nil, nil, nil, nil, nil end
		return
	end
	if type(HasNewMail) ~= "function" then return end
	local pending = HasNewMail()
	if pending ~= nil and issecretvalue and issecretvalue(pending) then return end
	pending = pending == true
	if not state.mail_seen then
		state.mail_seen, state.mail = true, pending
		return
	end
	if state.mail_snooze and now() < state.mail_snooze then
		state.mail = pending
		return
	end
	if state.mail_snooze and now() >= state.mail_snooze then
		state.mail_snooze = nil
		if pending and not state.mail_handle then state.mail = false end
	end
	if pending and not state.mail then
		state.mail_summary = nil
		state.mail_handle = notify({
			source = "everlook.mail", key = "mail:new", kind = "mail", persist = true, text = "New mail", detail = "Unread mail is waiting",
			actions = { { id = "remind", label = "Remind in five minutes", type = "callback", on_click = function()
				state.mail_snooze = now() + 300
				if dismiss(state.mail_handle) then state.mail_handle = nil end
			end } },
		})
	elseif not pending and state.mail_handle then
		if dismiss(state.mail_handle) then state.mail_handle = nil end
		state.mail_snooze = nil
	end
	state.mail = pending
end

-- The inbox size is only readable while a mailbox is open. When the player opens
-- one with the new-mail notice up, the notice says what is waiting.
local function inbox_summary()
	if type(GetInboxNumItems) ~= "function" or type(GetInboxHeaderInfo) ~= "function" then return nil end
	local count = plain_number(GetInboxNumItems())
	if not count or count < 1 or count > 200 or count % 1 ~= 0 then return nil end
	local messages, with_items, copper = 0, 0, 0
	for index = 1, count do
		local _, _, _, _, money, _, _, has_item = GetInboxHeaderInfo(index)
		local gold = plain_number(money)
		messages = messages + 1
		if has_item and has_item ~= 0 and not (issecretvalue and issecretvalue(has_item)) then with_items = with_items + 1 end
		if gold and gold > 0 then copper = copper + gold end
	end
	local parts = { messages .. (messages == 1 and " message" or " messages") }
	if with_items > 0 then parts[#parts + 1] = with_items .. " with attachments" end
	if copper > 0 then parts[#parts + 1] = Everlook.island_vitals.money(copper) end
	return table.concat(parts, ", ")
end

local function mail_contents()
	if not option("feed_mail") or not state.mail_handle then return end
	local summary = inbox_summary()
	if not summary or summary == state.mail_summary then return end
	state.mail_summary = summary
	-- The notice keeps its buttons; only its text and where it shows change.
	local handle = Everlook.island.update(state.mail_handle, { detail = summary, presentation = "inbox" })
	if handle then state.mail_handle = handle end
end

-- A snoozed reminder checks every refresh, so it comes back on time.
local function poll()
	if not state.mail_snooze and not kit.due(state.slow_at) then return end
	state.slow_at = now()
	mail()
end

Everlook.module.extend("smart_island", {
	id = "mail", addon = addon_name, order = 60,
	options = {
		feed_mail = { name = "New mail", default = false, description = "Tells you when new mail arrives, and keeps one notice while that mail is still waiting, unless you choose Remind in five minutes, which hides it and brings it back if the mail is still there. Mail already waiting when you turn this on stays quiet, and so does a mail flag the client hides or a client that cannot check mail, the notice goes away once the mail is gone, and turning this off clears it.", presets = { Quiet = false, Standard = true, Informative = true } },
	},
	sections = { { name = "Notices", keys = { "feed_mail" } } },
	events = { "UPDATE_PENDING_MAIL", "MAIL_INBOX_UPDATE", "PLAYER_ENTERING_WORLD" },
	on_event = function(event)
		if event == "MAIL_INBOX_UPDATE" then mail_contents()
		elseif event == "PLAYER_ENTERING_WORLD" then poll()
		else mail() end
	end,
	apply = function(enabled)
		if not enabled then state = {}; return end
		state.slow_at = nil
		poll()
	end,
	refresh = function(force)
		if not force then poll() end
	end,
})
