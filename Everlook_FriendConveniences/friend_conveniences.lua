local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "friend_conveniences"

local function full_name(name)
	-- A secret name still has type "string", and string methods on it error.
	if issecretvalue and issecretvalue(name) then return nil end
	if type(name) ~= "string" then return nil end
	local player, realm = name:match("^([^%-]+)%-(.+)$")
	if not player then player, realm = name, GetNormalizedRealmName and GetNormalizedRealmName() or "" end
	return player:lower() .. "-" .. realm:gsub("%s", ""):lower()
end

local function trusted(name)
	local target = full_name(name)
	if not target then return false end
	if module.get(id, "friends") and C_FriendList then
		for index = 1, C_FriendList.GetNumFriends() do
			local friend = C_FriendList.GetFriendInfoByIndex(index)
			if friend and full_name(friend.name) == target then return true end
		end
	end
	if module.get(id, "guild") and IsInGuild and IsInGuild() and GetNumGuildMembers then
		for index = 1, GetNumGuildMembers() do
			if full_name(GetGuildRosterInfo(index)) == target then return true end
		end
	end
	return false
end

module.register({
	addon = addon_name, page = "social", order = 10,
	id = id, name = "Friend conveniences",
	description = "When a party invite or a duel arrives, this accepts or declines it if the matching choice below is on, and closes that request. This stays quiet in combat or while you hold Shift, a request those choices leave alone stays on screen, and turning this off leaves every invite and duel for you.",
	options = {
		friends = { name = "Accept party invites from friends", default = true, description = "Accepts a party invite from someone on your in-game friend list and closes it. A Battle.net friend who is not also on that list stays, the names have to match, realm included, one already showing waits for the next, this stays quiet in combat or while you hold Shift, and turning this off leaves the next invite." },
		guild = { name = "Accept party invites from guildmates", default = false, description = "Accepts a party invite from a guildmate and closes it. You need to be in the guild, the names have to match, realm included, one already showing waits for the next, this stays quiet in combat or while you hold Shift, and turning this off leaves a guild invite when the friend choice does not accept it and Decline party invites from everyone else is off." },
		decline_others = { name = "Decline party invites from everyone else", default = false, description = "Declines a party invite that is not from a friend or guildmate you have chosen to accept, and closes the invite. With both of those options off, every invite is declined, one already showing waits for the next, this stays quiet in combat or while you hold Shift, nothing happens when the client cannot decline it, and turning this off leaves an invite those choices do not accept." },
		block_duels = { name = "Decline duels", default = false, description = "Declines a duel someone offers you and closes the request. One already showing waits for the next, this stays quiet in combat or while you hold Shift, nothing happens when the client cannot cancel it, and turning this off leaves the next one for you." },
	},
	events = { "PARTY_INVITE_REQUEST", "DUEL_REQUESTED" },
	on_event = function(event, name)
		if module.paused() or (InCombatLockdown and InCombatLockdown()) then return end
		if event == "PARTY_INVITE_REQUEST" and trusted(name) and AcceptGroup then
			AcceptGroup()
			if StaticPopup_Hide then StaticPopup_Hide("PARTY_INVITE") end
		elseif event == "PARTY_INVITE_REQUEST" and module.get(id, "decline_others") and DeclineGroup then
			DeclineGroup()
			if StaticPopup_Hide then StaticPopup_Hide("PARTY_INVITE") end
		elseif event == "DUEL_REQUESTED" and module.get(id, "block_duels") and CancelDuel then
			CancelDuel()
			if StaticPopup_Hide then StaticPopup_Hide("DUEL_REQUESTED") end
		end
	end,
})
