-- A kill that left nothing to loot: counted only when it is surely the player's own, and only once.
return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)
	local function load(extra, refuse)
		local counted = {}
		local timers = {}
		local Everlook
		Everlook = {
			public = function(value) if value ~= "hidden" then return value end end,
			world = { usable = function(value) return value ~= "hidden" end, count = function(bucket, row)
				local copy = {}
				for key, value in pairs(row) do copy[key] = value end
				counted[#counted + 1] = { bucket = bucket, row = copy }
			end },
			npcs = { creature_id = function(guid) return type(guid) == "string" and tonumber(guid:match("^Creature%-0%-1%-0%-2%-(%d+)")) or nil end, record = function() end },
			items = { id_from_link = function() end, record = function() end },
			objects = { record = function() end },
		}
		local state = { target = "Creature-0-1-0-2-448-abc", tap_denied = false, combat = true, loot = { false, true }, handler = nil, registered = {}, refuse = refuse }
		local env = setmetatable({
			CreateFrame = function() return {
				RegisterEvent = function(_, event) if state.refuse == event then error("unknown event") end state.registered[#state.registered + 1] = event end,
				RegisterUnitEvent = function(_, event) state.registered[#state.registered + 1] = event end,
				SetScript = function(_, _, fn) state.handler = fn end } end,
			C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end },
			UnitGUID = function(unit) if unit == "target" then return state.target end end,
			UnitIsTapDenied = function() return state.tap_denied end,
			UnitAffectingCombat = function() return state.combat end,
			CanLootUnit = function() return unpack(state.loot) end,
		}, { __index = _G })
		env._G = env
		for key, value in pairs(extra or {}) do env[key] = value end
		local chunk = assert(loadfile(source("drops")))
		setfenv(chunk, env)
		chunk("Everlook", Everlook)
		return Everlook, state, counted, timers, env
	end
	local function died(state, guid) state.handler(nil, "UNIT_DIED", guid) end

	local addon, state, counted, timers = load()
	died(state, "Creature-0-1-0-2-448-abc")
	check("a death is looked at a second later, not at once", #timers == 1 and timers[1].seconds == 1 and #counted == 0)
	timers[1].fn()
	check("an empty corpse of the player's own kill counts once, as an empty kill and nothing else", #counted == 1 and counted[1].bucket == "kills" and counted[1].row.npcId == 448
		and counted[1].row.empties == 1 and counted[1].row.kills == 0 and counted[1].row.loots == 0)
	died(state, "Creature-0-1-0-2-448-abc")
	check("the same corpse is not counted again", #timers == 1)

	local function none(label, setup)
		local _, local_state, local_counted, local_timers = load()
		setup(local_state)
		died(local_state, "Creature-0-1-0-2-448-abc")
		for _, timer in ipairs(local_timers) do timer.fn() end
		check(label, #local_counted == 0)
	end
	none("a creature that is not the player's target counts nothing", function(s) s.target = "Creature-0-1-0-2-999-zzz" end)
	none("a creature another player tapped counts nothing", function(s) s.tap_denied = true end)
	none("a death out of combat counts nothing", function(s) s.combat = false end)
	none("a corpse that holds loot counts nothing here, the loot window will count it", function(s) s.loot = { true, true } end)
	none("an answer the game does not give counts nothing", function(s) s.loot = {} end)
	none("a target the client hides counts nothing", function(s) s.target = "hidden" end)

	local _, hidden_state, hidden_counted, hidden_timers = load()
	hidden_state.handler(nil, "UNIT_DIED", "hidden")
	hidden_state.handler(nil, "UNIT_DIED", "Player-1-0000")
	check("a hidden id and a player count nothing and start no timer", #hidden_counted == 0 and #hidden_timers == 0)

	local _, bare_state, bare_counted, bare_timers = load({ CanLootUnit = false, UnitIsTapDenied = false })
	died(bare_state, "Creature-0-1-0-2-448-abc")
	check("a client without the functions counts nothing and raises nothing", #bare_counted == 0 and #bare_timers == 0)

	local function registered_by(refuse)
		local ok, _, refusing = pcall(load, nil, refuse)
		local seen = {}
		for _, event in ipairs(ok and refusing.registered or {}) do seen[event] = true end
		return ok, seen
	end
	local ok, seen = registered_by(nil)
	check("the death event is registered, and the loot event still is", ok and seen.UNIT_DIED and seen.LOOT_OPENED)
	local survived, kept = registered_by("UNIT_DIED")
	check("a client that refuses the death event does not break the file, and the loot event is still watched", survived and not kept.UNIT_DIED and kept.LOOT_OPENED)
end
