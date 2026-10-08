local addon_name = ...
local Everlook = Everlook

-- Alt-right-click names what is under the cursor. The key binding is the only
-- listener, so secure frames stay unhooked. Say is proximity chat. The party
-- message is what another Smart island shows.
local share = {}
Everlook.island_share = share

local PREFIX = "Everlook"
local OPTION = "share_click"
local REPEAT_AFTER = 0.4
local NAME_LIMIT = 80
local WIRE_KIND = { unit = true, item = true, object = true, quest = true, spell = true }
local ISLAND_KIND = { unit = "info", item = "loot", object = "info", quest = "quest", spell = "info" }

BINDING_NAME_EVERLOOK_SHARE = "Share what you are pointing at"

local last_kind, last_name, last_at

local function secret(value)
	return issecretvalue and issecretvalue(value) and true or false
end

local function plain_name(value)
	if secret(value) or type(value) ~= "string" then return nil end
	if value == "" or #value > NAME_LIMIT or value:find("%S") == nil then return nil end
	if value:find("|", 1, true) or value:find("\n", 1, true) or value:find("\t", 1, true) then return nil end
	return value
end

local function safe_id(value)
	if secret(value) or type(value) ~= "number" then return nil end
	if value ~= value or value < 1 or value > 9007199254740991 or value % 1 ~= 0 then return nil end
	return value
end

local function island_enabled()
	return Everlook.module and Everlook.module.enabled and Everlook.module.enabled("smart_island") == true
end

local function sharing()
	return island_enabled() and Everlook.module.get("smart_island", OPTION) == true
end

local function typing()
	if type(GetCurrentKeyBoardFocus) ~= "function" then return false end
	local focus = GetCurrentKeyBoardFocus()
	if secret(focus) then return false end
	return focus ~= nil
end

local function item_link(link)
	if secret(link) or type(link) ~= "string" or #link == 0 or #link > 255 then return nil end
	if link:find("\n", 1, true) or link:find("\t", 1, true) then return nil end
	local found = false
	local start = 1
	while true do
		local at = link:find("|H", start, true)
		if not at then break end
		if link:sub(at, at + 6) ~= "|Hitem:" then return nil end
		found = true
		start = at + 7
	end
	if not found then return nil end
	return link
end

local function id_from_link(link)
	if secret(link) or type(link) ~= "string" then return nil end
	local digits = link:match("item:(%d+)")
	if not digits then return nil end
	return safe_id(tonumber(digits))
end

local function unit_subject()
	if type(UnitExists) ~= "function" then return nil end
	local exists = UnitExists("mouseover")
	if secret(exists) or not exists then return nil end
	if type(UnitIsUnit) == "function" then
		local mine = UnitIsUnit("mouseover", "player")
		if not secret(mine) and mine then return "self" end
	end
	if type(UnitName) ~= "function" then return nil end
	local name = plain_name(UnitName("mouseover"))
	if not name then return nil end
	return { kind = "unit", name = name }
end

local function item_subject()
	if not GameTooltip or type(GameTooltip.GetItem) ~= "function" then return nil end
	local name, link = GameTooltip:GetItem()
	name = plain_name(name)
	if not name then return nil end
	return { kind = "item", name = name, link = item_link(link), id = id_from_link(link) }
end

local function quest_subject()
	if type(GetMouseFoci) ~= "function" or not (C_QuestLog and type(C_QuestLog.GetTitleForQuestID) == "function") then
		return nil
	end
	local foci = GetMouseFoci()
	local frame = foci and foci[1]
	if secret(frame) or frame == nil or frame == WorldFrame then return nil end
	local depth = 0
	while frame and depth < 6 do
		local id = frame.questID or frame.questId
		if not secret(id) then
			id = safe_id(id)
			if id then
				local title = plain_name(C_QuestLog.GetTitleForQuestID(id))
				if title then return { kind = "quest", name = title, id = id } end
			end
		end
		if type(frame.GetParent) ~= "function" then return nil end
		frame = frame:GetParent()
		depth = depth + 1
	end
end

local function spell_subject()
	if not GameTooltip or type(GameTooltip.GetSpell) ~= "function" then return nil end
	local name, second, third = GameTooltip:GetSpell()
	name = plain_name(name)
	if not name then return nil end
	return { kind = "spell", name = name, id = safe_id(second) or safe_id(third) }
end

local function on_world()
	if type(GetMouseFoci) ~= "function" then return true end
	local foci = GetMouseFoci()
	if secret(foci) or type(foci) ~= "table" then return true end
	local top = foci[1]
	return top == nil or top == WorldFrame
end

local function object_subject()
	if not on_world() or not GameTooltip or type(GameTooltip.IsShown) ~= "function" then return nil end
	local shown = GameTooltip:IsShown()
	if secret(shown) or not shown then return nil end
	local line = GameTooltipTextLeft1
	if not line or type(line.GetText) ~= "function" then return nil end
	local name = plain_name(line:GetText())
	if not name then return nil end
	return { kind = "object", name = name }
end

function share.subject()
	local unit = unit_subject()
	if unit == "self" then return nil end
	if unit then return unit end
	return item_subject() or quest_subject() or spell_subject() or object_subject()
end

function share.say_line(subject)
	if subject.kind == "item" and subject.link then return subject.link end
	return subject.name
end

function share.wire(subject)
	if type(subject) ~= "table" or not WIRE_KIND[subject.kind] then return nil end
	local name = plain_name(subject.name)
	if not name then return nil end
	local body = "1\t" .. subject.kind .. "\t" .. name
	if (subject.kind == "item" or subject.kind == "spell") and safe_id(subject.id) then
		body = body .. "\t" .. string.format("%.0f", subject.id)
	end
	if #body > 255 then return nil end
	return body
end

local function fields(text)
	local parts, start = {}, 1
	while true do
		local at = text:find("\t", start, true)
		if not at then
			parts[#parts + 1] = text:sub(start)
			return parts
		end
		if #parts >= 4 then return nil end
		parts[#parts + 1] = text:sub(start, at - 1)
		start = at + 1
	end
end

function share.read_wire(text)
	if secret(text) or type(text) ~= "string" or #text > 255 then return nil end
	local parts = fields(text)
	if not parts or #parts < 3 or #parts > 4 or parts[1] ~= "1" or not WIRE_KIND[parts[2]] then return nil end
	local name = plain_name(parts[3])
	if not name then return nil end
	local subject = { kind = parts[2], name = name }
	if #parts == 3 then return subject end
	if parts[2] ~= "item" and parts[2] ~= "spell" then return nil end
	if not parts[4]:find("^%d+$") then return nil end
	local id = safe_id(tonumber(parts[4]))
	if not id then return nil end
	subject.id = id
	return subject
end

local function notice_key(speaker)
	local key = "share:" .. (speaker or "self")
	if #key > 64 then key = key:sub(1, 64) end
	return key
end

function share.present(speaker, subject)
	if not island_enabled() or not subject or not (Everlook.island and type(Everlook.island.notify) == "function") then
		return nil
	end
	local text = subject.name
	if speaker then text = speaker .. ": " .. subject.name end
	local payload = {
		source = "everlook",
		key = notice_key(speaker),
		kind = ISLAND_KIND[subject.kind] or "info",
		text = text,
	}
	if subject.kind == "item" and safe_id(subject.id) then payload.item_id = subject.id end
	if subject.kind == "spell" and safe_id(subject.id) then payload.spell_id = subject.id end
	return Everlook.island.notify(payload)
end

local function say(text)
	if secret(text) or type(text) ~= "string" or text == "" then return end
	if C_ChatInfo and type(C_ChatInfo.InChatMessagingLockdown) == "function" then
		local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
		if ok and not secret(locked) and locked then return end
	end
	local function send()
		if C_ChatInfo and type(C_ChatInfo.SendChatMessage) == "function" then
			return C_ChatInfo.SendChatMessage(text, "SAY")
		end
		if type(SendChatMessage) == "function" then
			return SendChatMessage(text, "SAY")
		end
	end
	pcall(send)
end

local function group_channel()
	if type(IsInGroup) ~= "function" then return nil end
	local home = LE_PARTY_CATEGORY_HOME
	local instance = LE_PARTY_CATEGORY_INSTANCE
	if home ~= nil and IsInGroup(home) then return "PARTY" end
	if instance ~= nil and IsInGroup(instance) then return "INSTANCE_CHAT" end
	if IsInGroup() then return "PARTY" end
end

local function send_party(body, channel)
	if not body or not channel or not (C_ChatInfo and type(C_ChatInfo.SendAddonMessage) == "function") then return end
	pcall(C_ChatInfo.SendAddonMessage, PREFIX, body, channel)
end

local function clock()
	if type(GetTime) ~= "function" then return nil end
	local value = GetTime()
	if secret(value) or type(value) ~= "number" or value ~= value then return nil end
	return value
end

local function repeated(subject)
	local now = clock()
	if not now then return false end
	if last_kind == subject.kind and last_name == subject.name and last_at and (now - last_at) < REPEAT_AFTER then
		return true
	end
	last_kind, last_name, last_at = subject.kind, subject.name, now
	return false
end

function share.click()
	if not sharing() or typing() then return end
	local subject = share.subject()
	if not subject or repeated(subject) then return end
	say(share.say_line(subject))
	local channel = group_channel()
	if channel then send_party(share.wire(subject), channel) end
	share.present(nil, subject)
end

function everlook_share_click()
	share.click()
end

local function player_name()
	local name, realm
	if type(UnitFullName) == "function" then
		name, realm = UnitFullName("player")
	end
	if secret(name) or type(name) ~= "string" or name == "" then
		name = type(UnitName) == "function" and UnitName("player") or nil
		realm = nil
	end
	if secret(name) or type(name) ~= "string" or name == "" then return nil end
	if secret(realm) or type(realm) ~= "string" then realm = nil end
	return name, realm
end

local function from_self(sender)
	if secret(sender) or type(sender) ~= "string" or sender == "" then return true end
	local name, realm = player_name()
	if not name then return false end
	if sender == name then return true end
	if realm and realm ~= "" and sender == name .. "-" .. realm then return true end
	return false
end

local function display_name(sender)
	if secret(sender) or type(sender) ~= "string" or sender == "" or #sender > NAME_LIMIT then return nil end
	if sender:find("|", 1, true) or sender:find("\n", 1, true) or sender:find("\t", 1, true) then return nil end
	local name, realm = sender:match("^([^%-]+)%-(.+)$")
	if not name or name == "" or not realm or realm == "" then return sender end
	local mine = type(GetNormalizedRealmName) == "function" and GetNormalizedRealmName() or nil
	if not secret(mine) and type(mine) == "string" and mine ~= "" and realm == mine and plain_name(name) then
		return name
	end
	return sender
end

function share.on_addon(prefix, text, _, sender)
	if prefix ~= PREFIX or not island_enabled() or from_self(sender) then return end
	local subject = share.read_wire(text)
	local speaker = display_name(sender)
	if not subject or not speaker then return end
	share.present(speaker, subject)
end

local function register_prefix()
	if C_ChatInfo and type(C_ChatInfo.RegisterAddonMessagePrefix) == "function" then
		pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_ENTERING_WORLD" then
		register_prefix()
	elseif event == "CHAT_MSG_ADDON" then
		share.on_addon(...)
	end
end)
register_prefix()

Everlook.module.extend("smart_island", {
	id = "share", addon = addon_name, order = 5,
	options = {
		share_click = { name = "Share an Alt-right-click", default = true, description = "Alt-right-click a unit, item, quest, spell, or world object to say its name and show it on the island. People in your party who have Smart island get that notice from you. A raid uses your party group. Nothing named, a secret name, and clicking yourself stay quiet. The key can be changed under Key Bindings. Turning this off stops sharing. Notices from other players stay." },
	},
	sections = { { name = "Notices", keys = { "share_click" }, before = "do_not_disturb" } },
})
