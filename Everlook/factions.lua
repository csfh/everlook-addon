local _, Everlook = ...

Everlook.factions = {}

local function public(value)
	if Everlook.world.usable(value) then
		return value
	end
end

-- Standing is not stored. Once a scan sees the same names, parents, and sides,
-- a later event with the same list size does not read each faction again.
local noted_name = {}
local noted_parent = {}
local noted_side = {}
local settled_count

local function faction_side(data)
	if type(data) ~= "table" then
		return nil
	end
	local side = public(data.side)
	if side == 1 or side == 2 then
		return side
	end
	local group = public(data.factionGroup or data.group)
	if group == "Alliance" then
		return 1
	end
	if group == "Horde" then
		return 2
	end
end

local function record_faction(id, name, parentId, side)
	id = public(id)
	name = public(name)
	if type(id) ~= "number" or type(name) ~= "string" or name == "" then
		return false
	end
	parentId = public(parentId)
	if type(parentId) ~= "number" then
		parentId = false
	end
	side = public(side)
	if side ~= 1 and side ~= 2 then
		side = nil
	end
	if noted_name[id] == name and noted_parent[id] == parentId and noted_side[id] == (side or false) then
		return true
	end
	noted_name[id] = name
	noted_parent[id] = parentId
	noted_side[id] = side or false
	local row = {
		id = id,
		name = name,
		parentFactionId = parentId ~= false and parentId or nil,
	}
	if side then
		row.side = side
	end
	Everlook.world.store("factions", row)
	return false
end

local function finish_scan(count, ready)
	if ready then
		settled_count = count
	else
		settled_count = nil
	end
end

function Everlook.factions.scan()
	if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
		local count = public(C_Reputation.GetNumFactions())
		if type(count) ~= "number" then
			return
		end
		if count == settled_count then
			return
		end
		local ready = true
		for index = 1, count do
			local data = C_Reputation.GetFactionDataByIndex(index)
			if type(data) == "table" and not data.isHeader then
				if record_faction(data.factionID, data.name, data.parentFactionID, faction_side(data)) ~= true then
					ready = false
				end
			end
		end
		finish_scan(count, ready)
		return
	end
	if not GetNumFactions or not GetFactionInfo then
		return
	end
	local count = public(GetNumFactions())
	if type(count) ~= "number" then
		return
	end
	if count == settled_count then
		return
	end
	local ready = true
	for index = 1, count do
		local name, _, _, _, _, _, _, _, isHeader, _, _, _, _, factionId = GetFactionInfo(index)
		if not isHeader then
			if record_faction(factionId, name) ~= true then
				ready = false
			end
		end
	end
	finish_scan(count, ready)
end

-- Reputation events arrive in bursts and this list does not store standing.
-- Later bursts share one walk per second. The walk still reads each faction
-- until the list has settled. Without a timer or a usable clock, each event
-- walks the list immediately.
local SCAN_WINDOW = 1
local scanned_at = 0
local scan_waiting = false

local function run_scan()
	scan_waiting = false
	if type(GetTime) == "function" then
		local now = GetTime()
		if type(now) == "number" then
			scanned_at = now
		end
	end
	Everlook.factions.scan()
end

local function request_scan()
	if type(GetTime) ~= "function" or not C_Timer or type(C_Timer.After) ~= "function" then
		Everlook.factions.scan()
		return
	end
	local now = GetTime()
	if type(now) ~= "number" then
		Everlook.factions.scan()
		return
	end
	if (now - scanned_at) >= SCAN_WINDOW then
		run_scan()
		return
	end
	if scan_waiting then
		return
	end
	scan_waiting = true
	local delay = SCAN_WINDOW - (now - scanned_at)
	if delay < 0.05 then
		delay = 0.05
	end
	C_Timer.After(delay, run_scan)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("UPDATE_FACTION")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function()
	request_scan()
end)
