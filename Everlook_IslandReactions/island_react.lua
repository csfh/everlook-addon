local addon_name = ...
local Everlook = Everlook

-- Tells the island when something happened that deserves a flash. The island
-- draws the flash and never decides what a kill is, so the deciding is here.
local function option(key)
	return Everlook.module.get("smart_island", key) == true
end

local function react(kind)
	local api = Everlook.island
	if api and type(api.react) == "function" then api.react(kind) end
end

-- A loot line is yours when it matches one of the client's first-person formats.
local OWN_LOOT = { "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE" }
local patterns

local function own_loot(message)
	if issecretvalue and issecretvalue(message) then return false end
	if type(message) ~= "string" then return false end
	if not patterns then
		patterns = {}
		for _, name in ipairs(OWN_LOOT) do
			local format = _G[name]
			if type(format) == "string" then
				-- Some languages number the slots ("%1$s"); the order does not matter to a match.
				local plain = format:gsub("%%(%d)%$([sd])", "%%%2")
				local escaped = plain:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0"):gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
				patterns[#patterns + 1] = "^" .. escaped .. "$"
			end
		end
	end
	for _, pattern in ipairs(patterns) do
		if message:find(pattern) then return true end
	end
	return false
end

-- Experience from a kill is the one kill signal this client gives: it cannot read the
-- combat log. A kill that gives none, a grey one, gives no reaction.
local function gave_experience(message)
	local experience = Everlook.island_experience
	return experience and type(experience.kill_xp) == "function" and experience.kill_xp(message) ~= nil
end

Everlook.module.extend("smart_island", {
	id = "reactions", addon = addon_name, order = 30,
	options = {
		react_level = { name = "Flash on level up", default = true, description = "Flashes the island in gold when you level up. It needs Show reactions, and it stays off while Do not disturb is on.", presets = { Quiet = false, Standard = true, Informative = true } },
		react_kill = { name = "Flash on a kill", default = false, description = "Flashes the island in the accent color when a kill gives you experience. A kill that gives none, such as a grey one, does not flash, because this client gives no other sign of a kill. It needs Show reactions and the experience feed's addon, and a long fight flashes at most four times a second.", presets = { Quiet = false, Standard = false, Informative = false } },
		react_loot = { name = "Flash on loot", default = false, description = "Flashes the island in green when you loot something. Other players' loot does not flash. It needs Show reactions.", presets = { Quiet = false, Standard = false, Informative = false } },
	},
	sections = { { name = "Notices", keys = { "react_level", "react_kill", "react_loot" }, before = "reduced_motion" } },
	events = { "PLAYER_LEVEL_UP", "CHAT_MSG_COMBAT_XP_GAIN", "CHAT_MSG_LOOT" },
	on_event = function(event, message)
		if event == "PLAYER_LEVEL_UP" then
			if option("react_level") then react("level") end
		elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
			if option("react_kill") and gave_experience(message) then react("kill") end
		elseif event == "CHAT_MSG_LOOT" then
			if option("react_loot") and own_loot(message) then react("loot") end
		end
	end,
})
