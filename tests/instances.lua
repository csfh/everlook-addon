-- Dungeon entrances and boss fights: what is recorded, and what is not.
return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)
	local function load()
		local rows = {}
		local Everlook
		Everlook = {
			world = {
				usable = function(value) return value ~= "secret" end,
				count = function(bucket, row)
					local copy = {}
					for key, value in pairs(row) do copy[key] = value end
					rows[#rows + 1] = { bucket = bucket, row = copy }
				end,
			},
			location = { player = function() return Everlook.here end },
		}
		local state = { inside = false, instance = { "Wailing Caverns", "party", 1, "Normal", 5, 0, false, 43 }, now = 100, handler = nil }
		local env = setmetatable({
			CreateFrame = function() return { RegisterEvent = function() end, SetScript = function(_, _, fn) state.handler = fn end } end,
			IsInInstance = function() return state.inside end,
			GetInstanceInfo = function() return unpack(state.instance) end,
			GetTime = function() return state.now end,
		}, { __index = _G })
		env._G = env
		local chunk = assert(loadfile(source("instances")))
		setfenv(chunk, env)
		chunk("Everlook", Everlook)
		Everlook.here = { mapId = 1413, x = 524, y = 377 }
		return Everlook, state, rows
	end

	local addon, state, rows = load()
	state.handler(nil, "PLAYER_LEAVING_WORLD")
	state.inside, state.now = true, 105
	state.handler(nil, "PLAYER_ENTERING_WORLD")
	local entry = rows[1]
	check("an arrival inside an instance counts one entry at the place the player left from, rounded to the grid",
		#rows == 1 and entry.bucket == "instanceEntrances" and entry.row.instanceId == 43 and entry.row.mapId == 1413
		and entry.row.x == 525 and entry.row.y == 375 and entry.row.enters == 1 and entry.row.name == "Wailing Caverns")
	state.handler(nil, "PLAYER_ENTERING_WORLD")
	check("a second arrival with no new outdoor point counts nothing", #rows == 1)

	local _, late, late_rows = load()
	late.handler(nil, "PLAYER_LEAVING_WORLD")
	late.inside, late.now = true, 400
	late.handler(nil, "PLAYER_ENTERING_WORLD")
	check("a point noted long before is not an entrance", #late_rows == 0)

	local _, indoors, indoor_rows = load()
	indoors.inside = true
	indoors.handler(nil, "PLAYER_LEAVING_WORLD")
	indoors.handler(nil, "PLAYER_ENTERING_WORLD")
	check("a point is never noted from inside an instance", #indoor_rows == 0)

	local _, battleground, bg_rows = load()
	battleground.instance = { "Warsong Gulch", "pvp", 0, "", 10, 0, false, 489 }
	battleground.handler(nil, "PLAYER_LEAVING_WORLD")
	battleground.inside = true
	battleground.handler(nil, "PLAYER_ENTERING_WORLD")
	check("a battleground is not a dungeon entrance", #bg_rows == 0)

	local _, secret, secret_rows = load()
	secret.instance = { "Wailing Caverns", "party", 1, "Normal", 5, 0, false, "secret" }
	secret.handler(nil, "PLAYER_LEAVING_WORLD")
	secret.inside = true
	secret.handler(nil, "PLAYER_ENTERING_WORLD")
	check("an instance id the client hides records nothing", #secret_rows == 0)

	state.handler(nil, "ENCOUNTER_END", 585, "Lady Anacondra", 1, 5, 1)
	state.handler(nil, "ENCOUNTER_END", 585, "Lady Anacondra", 1, 5, 0)
	check("a kill and a wipe each count once, in the instance the player is in", #rows == 3 and rows[2].bucket == "instanceEncounters" and rows[2].row.instanceId == 43
		and rows[2].row.encounterId == 585 and rows[2].row.kills == 1 and rows[2].row.wipes == 0 and rows[3].row.kills == 0 and rows[3].row.wipes == 1 and rows[3].row.name == "Lady Anacondra")
	state.handler(nil, "ENCOUNTER_END", "secret", "x", 1, 5, 1)
	state.instance = { "Elwynn Forest", "none", 0, "", 0, 0, false, 0 }
	state.handler(nil, "ENCOUNTER_END", 586, "Boss", 1, 5, 1)
	check("a fight with a hidden id, or outside an instance, counts nothing", #rows == 3)
end
