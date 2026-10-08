local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "mail"
local ticker
local open = false

local function header(mail_index)
	if type(GetInboxHeaderInfo) ~= "function" then
		return nil
	end
	local _, _, _, _, money, cod, _, has_item = GetInboxHeaderInfo(mail_index)
	money = type(money) == "number" and money or nil
	cod = type(cod) == "number" and cod or nil
	has_item = type(has_item) == "number" and has_item or nil
	if money == nil and cod == nil and has_item == nil then
		return nil
	end
	return {
		money = money or 0,
		cod = cod or 0,
		hasItem = has_item or 0,
	}
end

local function stop()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
end

-- OpenAllMailMixin sends one TakeInboxMoney or TakeInboxItem, then waits
-- until that command is finished. Another take in the same tick is rejected,
-- and the attachment that was in the next slot slides into the one just taken.
local function command_pending()
	if type(C_Mail) ~= "table" or type(C_Mail.IsCommandPending) ~= "function" then
		return false
	end
	local pending = C_Mail.IsCommandPending()
	if issecretvalue and issecretvalue(pending) then
		return true
	end
	return pending == true
end

local function first_item_slot(mail_index, item_count)
	local limit = ATTACHMENTS_MAX_RECEIVE or ATTACHMENTS_MAX
	if type(limit) ~= "number" or limit < 1 then
		limit = item_count
	end
	if type(HasInboxItem) == "function" then
		for slot = 1, limit do
			local occupied = HasInboxItem(mail_index, slot)
			if issecretvalue and issecretvalue(occupied) then
				return nil
			end
			if occupied then
				return slot
			end
		end
		return nil
	end
	if item_count > 0 then
		return 1
	end
end

local function tick()
	if not open or not module.enabled(id) or module.paused() then
		stop()
		return
	end
	if command_pending() then
		return
	end
	local count = GetInboxNumItems and GetInboxNumItems() or 0
	if type(count) ~= "number" or count < 1 then
		stop()
		return
	end
	-- Read from the top each tick. Taking a message compacts the inbox, so a
	-- stored index would skip the mail that slid into the opened slot.
	for mail_index = 1, count do
		local info = header(mail_index)
		if info and info.cod <= 0 and (info.money > 0 or info.hasItem > 0) then
			if info.money > 0 and type(TakeInboxMoney) == "function" then
				TakeInboxMoney(mail_index)
				return
			end
			if info.hasItem > 0 and type(TakeInboxItem) == "function" then
				local slot = first_item_slot(mail_index, info.hasItem)
				if slot then
					TakeInboxItem(mail_index, slot)
					return
				end
			end
		end
	end
	stop()
end

local function start()
	stop()
	if module.paused() or not C_Timer or not C_Timer.NewTicker or type(GetInboxNumItems) ~= "function" then
		return
	end
	if type(GetInboxHeaderInfo) ~= "function" then
		return
	end
	ticker = C_Timer.NewTicker(0.15, tick)
end

module.register({
	addon = addon_name, page = "loot", order = 30,
	id = id,
	name = "Take mail",
	description = "Takes the money and the attached items from the open mailbox, one letter at a time, and that letter leaves the inbox. Cash-on-delivery mail stays, a letter with nothing attached stays, closing the mailbox or turning this off stops the rest, turning this on while it is already open waits until you open it again, and holding Shift stops the rest of that visit.",
	events = { "MAIL_SHOW", "MAIL_CLOSED" },
	on_event = function(event)
		open = event == "MAIL_SHOW"
		if open then
			start()
		else
			stop()
		end
	end,
	apply = function(enabled)
		if not enabled then
			stop()
		end
	end,
})
