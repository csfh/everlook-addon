local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "chat_tweaks"

Everlook.chat_tweaks = {}

local button_names = {
	"ChatFrameMenuButton", "ChatFrameChannelButton", "ChatFrameToggleVoiceDeafenButton",
	"ChatFrameToggleVoiceMuteButton", "QuickJoinToastButton",
}
-- The game's own fade time, set when each chat window loads (ChatFrameOverrides.lua).
local default_fade_seconds = 120

local original_points = setmetatable({}, { __mode = "k" })
local original_fade = setmetatable({}, { __mode = "k" })
local was_shown, hooked = {}, {}
local hiding = false

local function move_edit_box(frame, name, on_top)
	local box = frame.editBox
	if not box then return end
	if on_top then
		if not original_points[box] then
			local points = {}
			for index = 1, box:GetNumPoints() do points[index] = { box:GetPoint(index) } end
			original_points[box] = points
		end
		box:ClearAllPoints()
		box:SetPoint("BOTTOMLEFT", _G[name .. "Tab"] or frame, "TOPLEFT", -5, 2)
		box:SetPoint("RIGHT", frame.ScrollBar or frame, "RIGHT", 8, 0)
	elseif original_points[box] then
		box:ClearAllPoints()
		for _, point in ipairs(original_points[box]) do box:SetPoint(point[1], point[2], point[3], point[4], point[5]) end
		original_points[box] = nil
	end
end

local function set_fade(frame, enabled)
	if not frame.SetTimeVisible then return end
	if enabled then
		if original_fade[frame] == nil then
			original_fade[frame] = frame.GetTimeVisible and frame:GetTimeVisible() or default_fade_seconds
		end
		frame:SetTimeVisible(module.get(id, "fade_seconds"))
	elseif original_fade[frame] ~= nil then
		frame:SetTimeVisible(original_fade[frame])
		original_fade[frame] = nil
	end
end

-- The game can show these again, for example when voice chat changes, so a
-- hidden button is hidden again as it appears. A button that was already
-- hidden before the module ran stays hidden when the module lets go.
local function set_buttons(hide)
	for _, name in ipairs(button_names) do
		local button = _G[name]
		if button then
			if hide then
				if was_shown[name] == nil then was_shown[name] = button:IsShown() end
				if not hooked[name] then
					hooked[name] = true
					button:HookScript("OnShow", function(self)
						if hiding then
							was_shown[name] = true
							self:Hide()
						end
					end)
				end
				button:Hide()
			elseif was_shown[name] ~= nil then
				if was_shown[name] then button:Show() end
				was_shown[name] = nil
			end
		end
	end
end

local filter_events = {
	"CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_GUILD", "CHAT_MSG_WHISPER", "CHAT_MSG_CHANNEL",
}
local filters_on = false

function Everlook.chat_tweaks.stamp(message)
	if not module.enabled(id) or not module.get(id, "timestamps") then
		return message
	end
	if issecretvalue and issecretvalue(message) then
		return message
	end
	if type(message) ~= "string" then
		return message
	end
	local hour, minute = 0, 0
	if type(GetGameTime) == "function" then
		hour, minute = GetGameTime()
	end
	if type(hour) ~= "number" then hour = 0 end
	if type(minute) ~= "number" then minute = 0 end
	return string.format("%02d:%02d ", hour, minute) .. message
end

-- ChatFrameUtil.ProcessMessageEventFilters (ChatFrameFilters.lua) drops the
-- line when the first return is true. A changed line has to come back as
-- false, then the new text, then every argument that followed it.
local function stamp_filter(_, _, message, ...)
	if issecretvalue and issecretvalue(message) then
		return false
	end
	local stamped = Everlook.chat_tweaks.stamp(message)
	if stamped == message then
		return false
	end
	return false, stamped, ...
end

local filter_add, filter_remove

local function message_filters()
	local util = ChatFrameUtil
	if type(util) == "table" and type(util.AddMessageEventFilter) == "function" and type(util.RemoveMessageEventFilter) == "function" then
		return util.AddMessageEventFilter, util.RemoveMessageEventFilter
	end
	if type(ChatFrame_AddMessageEventFilter) == "function" and type(ChatFrame_RemoveMessageEventFilter) == "function" then
		return ChatFrame_AddMessageEventFilter, ChatFrame_RemoveMessageEventFilter
	end
end

local function set_filters(on)
	if on == filters_on then
		return
	end
	if on then
		filter_add, filter_remove = message_filters()
	end
	if not filter_add then
		return
	end
	for index = 1, #filter_events do
		local event = filter_events[index]
		if on then
			filter_add(event, stamp_filter)
		else
			filter_remove(event, stamp_filter)
		end
	end
	filters_on = on
	if not on then
		filter_add, filter_remove = nil, nil
	end
end

local function apply(enabled)
	hiding = enabled and module.get(id, "hide_buttons")
	set_filters(enabled and module.get(id, "timestamps"))
	for _, name in ipairs(CHAT_FRAMES or {}) do
		local frame = _G[name]
		if frame then
			move_edit_box(frame, name, enabled and module.get(id, "editbox_top"))
			set_fade(frame, enabled)
		end
	end
	set_buttons(hiding)
end

module.register({
	addon = addon_name, page = "chat", order = 10,
	id = id, name = "Chat tweaks",
	description = "Moves each chat window's edit box above its tab, or above the window when it has no tab, and hides the chat buttons, while those choices are on, and sets how long lines stay before they fade, including after the game rebuilds those windows. Turning this off puts the box and the earlier fade time back and shows only the buttons that were visible, a window with no edit box or that cannot fade is left alone, and the time prefix stays on its own option.",
	options = {
		editbox_top = { name = "Put the edit box above the chat window", default = true, description = "Moves each chat window's edit box above that window's tab, or above the window when it has no tab. The chat buttons and the fade time stay on their own options, a window with no edit box is left alone, and turning this off puts the box back where it was." },
		hide_buttons = { name = "Hide the chat buttons", default = true, description = "Hides the chat menu, channel, voice deafen, voice mute, and quick join buttons, and hides them again if the game shows them. A button that was already hidden stays hidden, the edit box and the fade time stay on their own options, and turning this off brings back only the buttons that were showing." },
		fade_seconds = { name = "Chat fade time", default = default_fade_seconds, min = 10, max = 600, step = 10, unit = " s", description = "Sets how long messages stay on each chat window before they fade, from 10 to 600 seconds, in steps of 10, and the game's own value is 120. The edit box and the chat buttons stay on their own options, a window that cannot fade is left alone, this number does nothing until Chat tweaks is on, and turning Chat tweaks off puts the earlier fade time back." },
		timestamps = { name = "Prefix chat lines with the time", default = false, description = "While Chat tweaks is on, this adds the realm time, as hours and minutes, in front of new say, yell, party, guild, channel, and incoming whisper lines, or 00:00 when the client has no clock. Party leader, raid, raid leader, raid warning, officer, instance, outgoing whisper, Battle.net whisper, emote, and system lines stay as they are, and so does text the client hides, a line already showing keeps whatever it has, turning this off or turning Chat tweaks off leaves the time off new lines, and nothing happens when the client has no chat filter." },
	},
	events = { "UPDATE_CHAT_WINDOWS", "UPDATE_FLOATING_CHAT_WINDOWS" },
	on_event = function() apply(true) end,
	apply = apply,
})
