local _, Everlook = ...

Everlook.instances = {}

-- Where a dungeon or raid is entered, and which bosses die in it. The last place the player stood outdoors
-- is noted as they leave the world, and the next arrival inside an instance counts as one entry there.
-- Points within QUANT thousandths of the map, 1.5 percent, are one entrance. A boss fight counts once when
-- it ends: a kill, or a wipe. Nothing here runs unless recording is on, because the rows go through the same gate.
local QUANT = 15
local FRESH = 120
local ENTERABLE = { party = true, raid = true, scenario = true }

local function public(value)
	if Everlook.world.usable(value) then return value end
end

local outside, noted_at

local function clock()
	return type(GetTime) == "function" and public(GetTime()) or nil
end

local function snap(value)
	return math.floor(value / QUANT + 0.5) * QUANT
end

-- Called as the player leaves the world (a dungeon always comes after a loading screen); it keeps the point only while the player is outdoors.
function Everlook.instances.note_outside()
	if type(IsInInstance) == "function" and IsInInstance() then return end
	local location = Everlook.location and Everlook.location.player(true)
	if not location then return end
	outside = { mapId = location.mapId, x = snap(location.x), y = snap(location.y) }
	noted_at = clock()
end

-- The instance the player is in now: its map id (the 8th return of GetInstanceInfo), its name and its kind.
local function here()
	if type(GetInstanceInfo) ~= "function" then return nil end
	local name, kind, _, _, _, _, _, instance_id = GetInstanceInfo()
	name, kind, instance_id = public(name), public(kind), public(instance_id)
	if type(instance_id) ~= "number" or instance_id <= 0 or not ENTERABLE[kind] then return nil end
	return instance_id, type(name) == "string" and name or nil
end

local entrance_row = { enters = 1 }

function Everlook.instances.arrived()
	if type(IsInInstance) ~= "function" or not IsInInstance() then return end
	local point, at = outside, noted_at
	outside, noted_at = nil, nil
	local instance_id, name = here()
	local now = clock()
	if not (point and instance_id and now and at and now - at <= FRESH) then return end
	entrance_row.instanceId, entrance_row.mapId, entrance_row.x, entrance_row.y = instance_id, point.mapId, point.x, point.y
	entrance_row.name = name
	Everlook.world.count("instanceEntrances", entrance_row)
end

local encounter_row = { kills = 0, wipes = 0 }

-- `success` is 1 for a kill and 0 for a wipe.
function Everlook.instances.encounter_ended(encounter_id, name, success)
	encounter_id, name, success = public(encounter_id), public(name), public(success)
	local instance_id = here()
	if not (instance_id and type(encounter_id) == "number" and encounter_id > 0) then return end
	encounter_row.instanceId, encounter_row.encounterId = instance_id, encounter_id
	encounter_row.name = type(name) == "string" and name or nil
	encounter_row.kills, encounter_row.wipes = success == 1 and 1 or 0, success == 0 and 1 or 0
	Everlook.world.count("instanceEncounters", encounter_row)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LEAVING_WORLD")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ENCOUNTER_END")
frame:SetScript("OnEvent", function(_, event, first, second, third, fourth, fifth)
	if event == "PLAYER_LEAVING_WORLD" then
		Everlook.instances.note_outside()
	elseif event == "PLAYER_ENTERING_WORLD" then
		Everlook.instances.arrived()
	elseif event == "ENCOUNTER_END" then
		-- encounterID, encounterName, difficultyID, groupSize, success
		Everlook.instances.encounter_ended(first, second, fifth)
	end
end)
