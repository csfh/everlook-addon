local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "radial_menu"

-- The key is a click on this button, which Bindings.xml binds as a CLICK action.
local BUTTON = "EverlookRadialButton"
local ACTION = "CLICK " .. BUTTON .. ":LeftButton"

BINDING_HEADER_EVERLOOK = "Everlook"
_G["BINDING_NAME_" .. ACTION] = "Open radial menu"

-- The wheel is open between key down and key up.
local active = false
-- Who was under the cursor when the wheel opened, and what each of its wedges does. By the time the key goes up
-- the cursor is over a wedge, so "mouseover" no longer points at them.
local target, offered
-- True while the button carries an action that has not been cleared yet.
local armed = false

local function usable(value)
	return value ~= nil and not (issecretvalue and issecretvalue(value))
end

local function in_combat()
	return InCombatLockdown and InCombatLockdown()
end

local function label(global, fallback)
	local text = _G[global]
	return type(text) == "string" and text or fallback
end

-- Pings use secure macros; focus and raid marks use the button's native unit actions.
-- Other wedges call functions that addon code may use during the key release. Protected attributes wait out combat.

-- Trade and inspect work on a unit token. The one that was "mouseover" is stale, so the recorded guid is
-- resolved again. A token that does not resolve back to the same guid means the unit is out of reach.
-- UnitGUID can turn secret after the wheel opens. Comparing that value errors, so the wedge does nothing.
local function same_guid(token, guid)
	if not token or not UnitGUID then return false end
	local current = UnitGUID(token)
	return usable(current) and current == guid
end

local function token_for(who)
	if not who or not usable(who.guid) then return nil end
	if same_guid(who.token, who.guid) then return who.token end
	local token = UnitTokenFromGUID and UnitTokenFromGUID(who.guid)
	if usable(token) and same_guid(token, who.guid) then return token end
end

local function named(who)
	return who.name ~= nil
end

local function can_lead()
	return IsInGroup and IsInGroup() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player"))
end

-- Anyone may mark in a party. A raid leaves marking to the leader and assistants.
local function can_mark()
	if not IsInRaid then return false end
	return not IsInRaid() or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

local function macro(type, text, macro_text, available)
	return { type = type, text = text, macro = macro_text, available = available }
end

local function call(type, text, run, available)
	return { type = type, text = text, run = run, available = available }
end

-- The ping macros are the game's numeric aliases: 1 attack, 2 warning, 3 on my way, 4 assist. They ping whatever
-- is under the cursor when the key goes up, which is why the wheel is steered by direction and not distance.
local function ping(number, text)
	return macro("ping_" .. number, text, function() return "/ping " .. number end)
end

local function mark(index, text)
	return { type = "raidtarget", text = text, marker = index, available = can_mark, secure_unit = true }
end

local function with_name(command)
	return function(who) return command .. " " .. who.name end
end

local trade = call("trade", function() return label("TRADE", "Trade") end,
	function(who) local token = token_for(who); if token and InitiateTrade then InitiateTrade(token) end end)
local invite = macro("invite", function() return label("INVITE", "Invite") end, with_name("/invite"), named)
local guild_invite = macro("guild_invite", function() return label("GUILD_INVITE", "Guild invite") end, with_name("/ginvite"),
	function(who) return named(who) and CanGuildInvite and CanGuildInvite() end)
local whisper = call("whisper", function() return label("WHISPER", "Whisper") end,
	function(who) if ChatFrameUtil and ChatFrameUtil.SendTell then ChatFrameUtil.SendTell(who.name) end end, named)
local add_friend = macro("add_friend", function() return label("ADD_FRIEND", "Add friend") end, with_name("/friend"), named)
local inspect = call("inspect", function() return label("INSPECT", "Inspect") end,
	function(who) local token = token_for(who); if token and InspectUnit then InspectUnit(token) end end)
local inspect_player = call(inspect.type, inspect.text, inspect.run, function(who) return who.is_player end)
-- Follow uses the game's native name format, which omits your realm and handles Forever surnames.
local follow = call("follow", function() return label("FOLLOW", "Follow") end,
	function(who) FollowUnit(who.follow_name, true) end,
	function(who) return who.follow_name ~= nil and FollowUnit ~= nil end)
local duel = macro("duel", function() return label("DUEL", "Duel") end, with_name("/duel"), named)
local focus = { type = "focus", text = function() return label("SET_FOCUS", "Set focus") end, secure_unit = true }
local clear_mark = mark(0, function() return "Clear mark" end)
clear_mark.available = function(who) return can_mark() and who.marked ~= nil and who.marked ~= 0 end
local assist = ping(4, function() return label("PING_TYPE_ASSIST", "Assist") end)

-- Each context lists its wedges clockwise from the top.
local WEDGES = {
	-- The ground, objects and any creature that is not a hostile unit.
	ping = {
		ping(1, function() return label("PING_TYPE_ATTACK", "Attack") end),
		ping(2, function() return label("PING_TYPE_WARNING", "Warning") end),
		ping(3, function() return label("PING_TYPE_ON_MY_WAY", "On my way") end),
		assist,
	},
	player = { trade, invite, guild_invite, whisper, add_friend, inspect, follow, duel },
	member = { whisper, trade, inspect, follow, focus, assist },
	hostile = {
		focus, ping(1, function() return label("PING_TYPE_ATTACK", "Attack") end), assist,
		mark(8, function() return label("RAID_TARGET_8", "Skull") end),
		mark(7, function() return label("RAID_TARGET_7", "Cross") end),
		mark(6, function() return label("RAID_TARGET_6", "Square") end),
		clear_mark, inspect_player,
	},
	self = {
		macro("ready_check", function() return "Ready check" end, function() return "/readycheck" end),
		call("role_check", function() return "Role check" end, function() if InitiateRolePoll then InitiateRolePoll() end end),
		macro("pull_timer", function() return "Pull timer" end, function() return "/countdown 10" end),
		call("clear_marks", function() return "Clear marks" end, function() if RemoveRaidTargets then RemoveRaidTargets() end end),
	},
}

local function wedges_for(context, who)
	local list, definitions = {}, {}
	for _, wedge in ipairs(WEDGES[context]) do
		if not wedge.available or wedge.available(who) then
			list[#list + 1] = wedge.text()
			definitions[#definitions + 1] = wedge
		end
	end
	return list, definitions
end

-- Over the 3D world the game lists no frame at all, so an empty list is the world. Any frame other than
-- the world frame is interface in the way.
local function context_under_cursor()
	local foci = GetMouseFoci and GetMouseFoci()
	if not foci or (foci[1] and foci[1] ~= WorldFrame) then return nil end
	if not UnitExists("mouseover") then return "ping" end
	if UnitIsUnit("mouseover", "player") then return can_lead() and "self" or "ping" end
	if UnitCanAttack("player", "mouseover") then return "hostile" end
	if UnitIsPlayer("mouseover") then
		return (UnitInParty("mouseover") or UnitInRaid("mouseover")) and "member" or "player"
	end
	return "ping"
end

local function capture_target()
	if not UnitGUID then return nil end
	local guid = UnitGUID("mouseover")
	if not usable(guid) then return nil end
	local who = { guid = guid, is_player = UnitIsPlayer("mouseover") }
	who.token = token_for(who)
	local marked = GetRaidTargetIndex and GetRaidTargetIndex("mouseover")
	if usable(marked) then who.marked = marked end
	local name, realm
	if UnitFullName then name, realm = UnitFullName("mouseover") end
	if usable(name) then
		local native_name
		if NameUtil and NameUtil.GetUnmodifiedUnitFullName then
			native_name = NameUtil.GetUnmodifiedUnitFullName("mouseover")
		elseif GetUnitName then
			native_name = GetUnitName("mouseover", true)
		end
		if usable(native_name) then who.follow_name = native_name end
		if not usable(realm) or realm == "" then realm = GetNormalizedRealmName and GetNormalizedRealmName() end
		if usable(realm) and realm ~= "" then name = name .. "-" .. realm end
		who.name = name
	end
	return who
end

local function open()
	if active or not module.enabled(id) or in_combat() then return end
	local context = context_under_cursor()
	if not context then return end
	local who
	if context ~= "ping" and context ~= "self" then
		who = capture_target()
		if not who then context = "ping" end
	end
	local texts, definitions = wedges_for(context, who)
	if #texts == 0 then return end
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	target, offered, active = who, definitions, true
	Everlook.wheel.open(texts, x / scale, y / scale)
end

-- The key coming up closes the wheel and, if a wedge was chosen, sets what the button does when its own click
-- handler runs next. That handler fires after this script, so the action goes on in time.
local function release(button)
	if not active then return end
	local index = Everlook.wheel.selected()
	Everlook.wheel.close()
	local wedge, who = offered[index or 0], target
	active, target, offered = false, nil, nil
	if not wedge or not module.enabled(id) or in_combat() then return end
	if wedge.secure_unit then
		local unit = token_for(who)
		if not unit then return end
		button:SetAttribute("type", wedge.type)
		button:SetAttribute("unit", unit)
		if wedge.marker ~= nil then
			button:SetAttribute("marker", wedge.marker)
			button:SetAttribute("action", wedge.marker == 0 and "clear" or "set")
		end
		armed = true
	elseif wedge.macro then
		button:SetAttribute("type", "macro")
		button:SetAttribute("macrotext", wedge.macro(who))
		armed = true
	else
		wedge.run(who)
	end
end

local function clear(button)
	if not armed or in_combat() then return end
	button:SetAttribute("type", nil)
	button:SetAttribute("macrotext", nil)
	button:SetAttribute("unit", nil)
	button:SetAttribute("marker", nil)
	button:SetAttribute("action", nil)
	armed = false
end

local button = CreateFrame("Button", BUTTON, UIParent, "SecureActionButtonTemplate")
button:RegisterForClicks("AnyDown", "AnyUp")
-- A key press fires nothing. The macro is set when the key comes up, and runs then.
button:SetAttribute("useOnKeyDown", false)
-- A binding's click has to reach a live button, so it is shown, but nothing can see it or click it. EllesmereUI's
-- Quickdraw sets its button up the same way and gets clicks from its key.
button:EnableMouse(false)
button:SetSize(1, 1)
button:SetAlpha(0)
button:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -300, 100)
button:Show()
button:SetScript("PreClick", function(self, _, down)
	if down then open() else release(self) end
end)
button:SetScript("PostClick", function(self, _, down)
	if not down then clear(self) end
end)

module.register({
	addon = addon_name, page = "radial_menu", order = 10,
	id = id,
	name = "Radial menu",
	description = "Hold the key over a player, a hostile unit, an object, the ground, or your own character, flick toward an action, and let go. The ground, an object, or a creature that is not hostile offers the Attack, Warning, On my way, and Assist pings, a friendly player outside your group offers Trade, Invite, Guild invite when you may invite, Whisper, Add friend, Inspect, Follow, and Duel, a group member you cannot attack offers Whisper, Trade, Inspect, Follow, Set focus, and an Assist ping, a hostile unit offers Set focus, the Attack and Assist pings, Skull, Cross, and Square when you can mark, Clear mark when you can mark and it is marked, and Inspect when it is a player, your own character offers Ready check, Role check, a ten second Pull timer, and Clear marks only when you lead or assist a group and otherwise those same ground pings, the wheel stays closed in combat, while the cursor is over the interface, and while this is off, letting go near the middle chooses nothing, a choice made after combat starts does nothing, anyone outside a raid can mark while a raid leaves marks to a leader or assistant, and you set the key below or under Key Bindings.",
	keybinding = ACTION,
	out_of_combat = true,
	apply = function() clear(button) end,
})
