local addon_name = ...
local Everlook = Everlook
local kit = Everlook.island_feed_kit
local option, dismiss, notify = kit.option, kit.dismiss, kit.notify
local state = {}

-- Information only. Accepting stays with the native invitation popup, which the
-- Island does not replace, so no protected call is made from a notice.
local function invite(name, tank, healer, damage)
	if not option("feed_invites") then
		if dismiss(state.invite_handle) then state.invite_handle = nil end
		return
	end
	if type(name) ~= "string" or name == "" or #name > 64 or (issecretvalue and issecretvalue(name)) then return end
	local role
	if tank == true then role = "tank" elseif healer == true then role = "healer" elseif damage == true then role = "damage dealer" end
	state.invite_handle = notify({
		source = "everlook.invites", key = "party-invite", kind = "invite", severity = "warning", duration = 10,
		text = name .. " invited you to a group", detail = role and ("Looking for a " .. role) or "Answer in the invitation popup",
	}) or state.invite_handle
end

local function invite_cancelled()
	if dismiss(state.invite_handle) then state.invite_handle = nil end
end

Everlook.module.extend("smart_island", {
	id = "invites", addon = addon_name, order = 70,
	options = {
		feed_invites = { name = "Group invites", default = false, description = "Shows a toast when someone invites you to a group, with the role when it is a finder invite. Accept or decline in the game's own invitation popup. The notice goes away when the invitation is cancelled.", presets = { Quiet = false, Standard = true, Informative = true } },
	},
	sections = { { name = "Notices", keys = { "feed_invites" } } },
	events = { "PARTY_INVITE_REQUEST", "PARTY_INVITE_CANCEL" },
	on_event = function(event, ...)
		if event == "PARTY_INVITE_REQUEST" then invite(...) else invite_cancelled() end
	end,
	apply = function(enabled)
		if not enabled then state = {} end
	end,
})
