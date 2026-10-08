local _, Everlook = ...

Everlook.taxi = {}

local function public(value)
	if Everlook.world.usable(value) then
		return value
	end
end

local function scale(value)
	value = public(value)
	if type(value) ~= "number" or value < 0 or value > 1 then
		return nil
	end
	return math.floor(value * 1000 + 0.5)
end

local function side()
	local faction = public(UnitFactionGroup and UnitFactionGroup("player"))
	if faction == "Alliance" then
		return 1
	end
	if faction == "Horde" then
		return 2
	end
end

local function current_state()
	local states = Enum and Enum.FlightPathState
	if type(states) == "table" and type(states.Current) == "number" then
		return states.Current
	end
	return 0
end

local function current_node(node)
	return public(node.state) == current_state()
end

local function route_cost(node)
	local slot = public(node.slotIndex)
	if type(slot) ~= "number" or type(TaxiNodeCost) ~= "function" then
		return nil
	end
	return public(TaxiNodeCost(slot))
end

function Everlook.taxi.learn_duration(origin, destination, seconds)
	if type(origin) ~= "string" or type(destination) ~= "string" or origin == "" or destination == "" then
		return
	end
	if type(seconds) ~= "number" or seconds <= 1 or not Everlook.world.each then
		return
	end
	local from_id, to_id, from_count, to_count
	from_count, to_count = 0, 0
	Everlook.world.each("taxiNodes", function(_, row)
		if type(row) == "table" and row.name == origin then
			from_count = from_count + 1
			from_id = row.id
		end
		if type(row) == "table" and row.name == destination then
			to_count = to_count + 1
			to_id = row.id
		end
	end)
	if from_count ~= 1 or to_count ~= 1 or from_id == nil or to_id == nil then
		return
	end
	Everlook.world.store("taxiRoutes", {
		fromNodeId = from_id,
		toNodeId = to_id,
		durationSeconds = math.floor(seconds + 0.5),
	})
end

function Everlook.taxi.scan()
	local mapId = C_Map and C_Map.GetBestMapForUnit and public(C_Map.GetBestMapForUnit("player")) or nil
	if C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and type(mapId) == "number" then
		local nodes = C_TaxiMap.GetAllTaxiNodes(mapId)
		if type(nodes) == "table" then
			local current
			for i = 1, #nodes do
				local node = nodes[i]
				local x = type(node.position) == "table" and scale(node.position.x) or nil
				local y = type(node.position) == "table" and scale(node.position.y) or nil
				local name = public(node.name)
				local id = public(node.nodeID)
				if type(id) == "number" and type(name) == "string" and x and y then
					Everlook.world.store("taxiNodes", {
						id = id,
						name = name,
						mapId = mapId,
						x = x,
						y = y,
						factionSide = side(),
					})
					if current_node(node) then
						current = id
					end
				end
			end
			if type(current) == "number" then
				for i = 1, #nodes do
					local node = nodes[i]
					local id = public(node.nodeID)
					local cost = route_cost(node)
					if type(id) == "number" and id ~= current and type(cost) == "number" then
						Everlook.world.store("taxiRoutes", {
							fromNodeId = current,
							toNodeId = id,
							cost = cost,
						})
					end
				end
			end
			return
		end
	end
	return
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("TAXIMAP_OPENED")
frame:SetScript("OnEvent", function()
	Everlook.taxi.scan()
end)
