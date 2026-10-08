local addon_name = ...
local Everlook = Everlook
local kit = Everlook.island_feed_kit
local plain_number, now, option, dismiss, notify = kit.plain_number, kit.now, kit.option, kit.dismiss, kit.notify
local dismiss_map, map_pending = kit.dismiss_map, kit.map_pending
local state = {}

-- A notice when a faction reaches a higher standing.
local function standing_label(reaction)
	local globals = _G
	if not globals then return end
	local label = globals["FACTION_STANDING_LABEL" .. reaction]
	if type(label) ~= "string" or label == "" or (issecretvalue and issecretvalue(label)) then return end
	return label
end

local function secret(value)
	return issecretvalue and issecretvalue(value)
end

local function faction_rows()
	if not C_Reputation or not C_Reputation.GetNumFactions or not C_Reputation.GetFactionDataByIndex then return nil end
	local count = plain_number(C_Reputation.GetNumFactions())
	if not count or count < 0 or count > 1000 or count % 1 ~= 0 then return nil end
	local rows, complete = {}, true
	for index = 1, count do
		local data = C_Reputation.GetFactionDataByIndex(index)
		if secret(data) or type(data) ~= "table" then
			complete = false
		elseif secret(data.isHeader) or secret(data.isHeaderWithRep) or secret(data.factionID) or secret(data.reaction) then
			complete = false
		else
			local id, reaction = plain_number(data.factionID), plain_number(data.reaction)
			local pure_header = data.isHeader == true and data.isHeaderWithRep ~= true
			if not pure_header and id and reaction and id % 1 == 0 and reaction % 1 == 0 and reaction >= 1 then
				local name = data.name
				if secret(name) or type(name) ~= "string" or name == "" then name = "Faction " .. id end
				rows[#rows + 1] = { id = id, name = name, reaction = reaction }
			end
		end
	end
	return rows, complete
end

local function reputation()
	state.rep_handles = state.rep_handles or {}
	if not option("feed_reputation") then
		dismiss_map(state.rep_handles)
		if not map_pending(state.rep_handles) then state.rep, state.rep_handles = nil, nil end
		return
	end
	local rows, complete = faction_rows()
	if not rows then return end
	if not state.rep then
		state.rep = {}
		for index = 1, #rows do state.rep[rows[index].id] = rows[index].reaction end
		return
	end
	local seen = {}
	for index = 1, #rows do
		local row = rows[index]
		seen[row.id] = true
		local prior = state.rep[row.id]
		state.rep[row.id] = row.reaction
		if prior and row.reaction > prior then
			state.rep_handles[row.id] = notify({
				source = "everlook.reputation", key = "rep:" .. row.id, kind = "reputation", stack = "standing",
				text = row.name, detail = standing_label(row.reaction) or "Standing increased",
				actions = { { id = "open", label = "Open reputation", type = "callback", on_click = function()
					if ToggleCharacter then ToggleCharacter("ReputationFrame") end
				end } },
			})
		end
	end
	local gone = {}
	if complete then
		for id in pairs(state.rep_handles) do
			if not seen[id] then gone[#gone + 1] = id end
		end
	end
	for index = 1, #gone do
		local id = gone[index]
		if dismiss(state.rep_handles[id]) then state.rep_handles[id] = nil end
	end
end

local function poll()
	if not kit.due(state.slow_at) then return end
	state.slow_at = now()
	reputation()
end

Everlook.module.extend("smart_island", {
	id = "reputation", addon = addon_name, order = 40,
	options = {
		feed_reputation = { name = "Reputation", default = false, description = "Tells you when a faction moves to a higher standing than the one already recorded, and names that faction and the new standing, saying Standing increased when that standing has no name. Gains inside the same standing stay quiet, and so do a drop, the first reading, a heading that does not track its own standing, and a standing the client hides, a later rise joins that notice while it is still up, and turning this off clears it.", presets = { Quiet = false, Standard = false, Informative = true } },
	},
	sections = { { name = "Notices", keys = { "feed_reputation" } } },
	events = { "UPDATE_FACTION", "PLAYER_ENTERING_WORLD" },
	on_event = function(event) if event == "PLAYER_ENTERING_WORLD" then poll() else reputation() end end,
	apply = function(enabled)
		if not enabled then state = {}; return end
		state.slow_at = nil
		poll()
	end,
	refresh = function(force)
		if not force then poll() end
	end,
})
