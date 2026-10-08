local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "hide_clutter"

-- Each element is shown by its own Blizzard frame in response to events that
-- the frame registers for itself. Unregistering those events hides the
-- element and registering them again brings it back, which is what the
-- default UI's own /uierrorsoff does for error messages. The boss emote frame
-- is left out: this client feeds it through a private callback, not events.
local elements = {
	talking_head = { frame = "TalkingHeadFrame", events = { "TALKINGHEAD_REQUESTED" } },
	zone_text = { frame = "ZoneTextFrame", events = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" } },
	error_messages = { frame = "UIErrorsFrame", events = { "UI_ERROR_MESSAGE" } },
	raid_warnings = { frame = "RaidWarningFrame", events = { "CHAT_MSG_RAID_WARNING" } },
}
local hidden = {}

-- StanceBar is protected. The secure driver owns visibility and reapplies it
-- after Blizzard shows the bar, including in combat. Addon code never calls
-- Hide on it or runs its protected update through an insecure stack.
local stance_frame

local function combat_blocks_stance()
	return type(InCombatLockdown) ~= "function" or InCombatLockdown()
end

local function stance_wanted(enabled)
	return enabled and module.get(id, "stance_bar") == true
end

local function apply_stance(enabled)
	local frame = stance_frame or _G.StanceBar
	if not frame or combat_blocks_stance() then return end
	if type(RegisterStateDriver) ~= "function" or type(UnregisterStateDriver) ~= "function"
		or type(securecallfunction) ~= "function" or type(frame.Update) ~= "function" then return end
	if stance_wanted(enabled) then
		if stance_frame then return end
		RegisterStateDriver(frame, "visibility", "hide")
		stance_frame = frame
	elseif stance_frame then
		-- Unregistering alone leaves statehidden set. Clear it securely first,
		-- then let Blizzard decide whether this class has a bar to show.
		RegisterStateDriver(frame, "visibility", "show")
		UnregisterStateDriver(frame, "visibility")
		stance_frame = nil
		securecallfunction(frame.Update, frame)
	end
end

local function apply(enabled)
	for key, element in pairs(elements) do
		local frame = _G[element.frame]
		local wanted = enabled and module.get(id, key)
		if frame and wanted ~= (hidden[key] == true) then
			for _, event in ipairs(element.events) do
				if wanted then frame:UnregisterEvent(event) else frame:RegisterEvent(event) end
			end
			hidden[key] = wanted or nil
		end
	end
	apply_stance(enabled)
end

module.register({
	addon = addon_name, page = "interface", order = 10,
	id = id, name = "Hide clutter",
	description = "Stops a new talking head, center-screen zone name, red error, or raid warning when that choice is on, and hides the stance bar when that choice is on. Turning this off lets the next one show, the stance bar waits until combat ends and then the game decides whether it belongs on screen, and a choice here does nothing until this is on.",
	options = {
		talking_head = { name = "Hide the talking head", default = true, description = "Stops a new talking-head portrait from appearing when an NPC starts speaking. One already on screen can still close, and turning this off lets the next one show." },
		zone_text = { name = "Hide the center-screen zone name", default = true, description = "Stops the large zone name, and the line under it, from appearing when you change areas. The minimap's zone label stays, a name already on screen can finish, and turning this off lets the next area change show that text." },
		error_messages = { name = "Hide red error messages", default = false, description = "Stops new red errors, such as \"Out of range\", from appearing on screen. Information messages, system messages, and chat stay, a message already showing can finish, and turning this off lets the next red error show." },
		raid_warnings = { name = "Hide raid warnings", default = false, description = "Stops a new raid warning from appearing on screen. The warning still appears in chat, one already showing can finish, and turning this off lets the next one show." },
		stance_bar = { name = "Hide the stance, stealth, and aura bar", default = false, description = "Hides the bar for stances, stealth, auras, and aspects, and keeps it hidden when the game shows that bar again. The change waits until combat ends, and turning this off lets the game decide whether the bar belongs on screen." },
	},
	apply = apply, out_of_combat = true,
	events = { "PLAYER_ENTERING_WORLD" }, on_event = function() apply(module.enabled(id)) end,
})
