local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "chat_format"

-- Blizzard builds a chat line as format(CHAT_<TYPE>_GET .. message, sender).
-- Replacing those strings sets the prefix without ever reading the message,
-- which can be secret in restricted content. The message keeps the color the
-- game gives the line, since the abbreviation's color ends with |r.
local ABBREVIATIONS = {
	SAY = "S", YELL = "Y",
	PARTY = "P", PARTY_LEADER = "PL", RAID = "R", RAID_LEADER = "RL", RAID_WARNING = "RW",
	GUILD = "G", OFFICER = "O", INSTANCE_CHAT = "I", INSTANCE_CHAT_LEADER = "IL",
	WHISPER = "W", WHISPER_INFORM = "To", BN_WHISPER = "W", BN_WHISPER_INFORM = "To",
	CHANNEL = false,
}
local FALLBACK_COLOR = "ffffff"

-- An invisible, empty color span in front of every line this module formats.
-- Only a line that carries it gets its sender's brackets removed, so system
-- messages keep theirs.
local MARK = "|cff000001|r"
local MARK_PATTERN = MARK:gsub("%p", "%%%0")

local originals = {}
local wrapped = setmetatable({}, { __mode = "k" })

local function hex(info)
	if type(info) ~= "table" or type(info.r) ~= "number" or type(info.g) ~= "number" or type(info.b) ~= "number" then
		return FALLBACK_COLOR
	end
	return string.format("%02x%02x%02x", math.floor(info.r * 255 + 0.5), math.floor(info.g * 255 + 0.5), math.floor(info.b * 255 + 0.5))
end

local function color(text, info)
	return "|cff" .. hex(info) .. text .. "|r"
end

-- The strings use the sender once and the message follows after a space,
-- so the line reads: abbreviation, name, message.
local function format_for(kind, abbreviation)
	local info = ChatTypeInfo and ChatTypeInfo[kind]
	local prefix = abbreviation and (color(abbreviation, info) .. " ") or ""
	return MARK .. prefix .. "%s "
end

local function apply_formats(on)
	for kind, abbreviation in pairs(ABBREVIATIONS) do
		local name = "CHAT_" .. kind .. "_GET"
		if on then
			if _G[name] ~= nil then
				if originals[name] == nil then originals[name] = _G[name] end
				_G[name] = format_for(kind, abbreviation)
			end
		elseif originals[name] ~= nil then
			_G[name] = originals[name]
			originals[name] = nil
		end
	end
end

local function strip_brackets(text)
	local replaced = text:gsub("(|Hplayer:[^|]*|h)%[(.-)%](|h)", "%1%2%3", 1)
	if replaced ~= text then return replaced end
	return (text:gsub("(|HBNplayer:[^|]*|h)%[(.-)%](|h)", "%1%2%3", 1))
end

local function shrink_channel(text)
	return (text:gsub("|Hchannel:channel:(%d+)|h%[[^%]]*%]|h ", function(number)
		local info = ChatTypeInfo and ChatTypeInfo["CHANNEL" .. number]
		return "|Hchannel:channel:" .. number .. "|h" .. color(number, info) .. "|h "
	end, 1))
end

function Everlook.chat_format_line(text)
	if not module.enabled(id) or type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then
		return text
	end
	if not text:find(MARK, 1, true) then
		return text
	end
	return strip_brackets(shrink_channel((text:gsub(MARK_PATTERN, ""))))
end

-- Chat windows come and go, so each one found is wrapped once. The wrapper
-- checks the toggle on every line, like the other permanent hooks.
local function wrap(frame)
	if type(frame) ~= "table" or wrapped[frame] or type(frame.AddMessage) ~= "function" then return end
	local add = frame.AddMessage
	frame.AddMessage = function(self, text, ...)
		return add(self, Everlook.chat_format_line(text), ...)
	end
	wrapped[frame] = true
end

-- Options, Social stores the format in showTimestamps. "none" is the
-- dropdown's off value, and ChatFrameUtil.GetTimestampFormat returns nothing
-- for it. The previous choice comes back when this option or the module turns off.
local cvar = "showTimestamps"
local timestamp_before

local function set_timestamps(hidden)
	if type(GetCVar) ~= "function" or type(SetCVar) ~= "function" then
		return
	end
	if hidden then
		if timestamp_before == nil then
			local current = GetCVar(cvar)
			if type(current) ~= "string" or (issecretvalue and issecretvalue(current)) then
				return
			end
			timestamp_before = current
		end
		SetCVar(cvar, "none")
	elseif timestamp_before ~= nil then
		SetCVar(cvar, timestamp_before)
		timestamp_before = nil
	end
end

local function apply(enabled)
	apply_formats(enabled)
	set_timestamps(enabled and module.get(id, "hide_timestamps"))
	if not enabled then return end
	for _, name in ipairs(CHAT_FRAMES or {}) do
		wrap(_G[name])
	end
end

module.register({
	addon = addon_name, page = "chat", order = 20,
	id = id,
	name = "Compact chat lines",
	description = "Shows say, yell, party, raid, guild, officer, instance, and whisper lines as a short label (S, Y, P, PL, R, RL, RW, G, O, I, IL, W, or To), the name, then the message, with no brackets, and a numbered channel as its number. The label takes that chat's color, or white when that chat has none, the name keeps its class color and the message keeps the color the game gives it, a system line, an emote, text the client hides, and a line already showing stay as they are, the option Hide the game's chat timestamps starts on and stays separate, turning this off puts the game's own format back for new lines and, while that option is still on, puts back the timestamp choice from before this was turned on, and a client with none of those chat formats or with no timestamp choice it can save is left alone.",
	options = {
		hide_timestamps = { name = "Hide the game's chat timestamps", default = true, description = "While Compact chat lines is on, this sets Timestamps in Options, Social to None and keeps the choice that was in place when that hide started. Turning this off, or turning Compact chat lines off while this stays on, puts that choice back when one was saved, the next hide keeps the choice in place then, and a client that cannot read or save the current choice is left alone." },
	},
	events = { "UPDATE_CHAT_COLOR", "UPDATE_CHAT_WINDOWS", "UPDATE_FLOATING_CHAT_WINDOWS" },
	on_event = function() apply(true) end,
	apply = apply,
})
