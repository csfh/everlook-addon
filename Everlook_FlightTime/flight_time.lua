local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "flight_time"
local frame, label, route, hooked, poller
local interval = 0
local next_trip = 0
local update, start_watch, stop_watch

local function readable(value)
	return not (issecretvalue and issecretvalue(value)) and value ~= nil
end

local function number(value)
	return readable(value) and type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function island_feed()
	return Everlook.island and type(Everlook.island.notify) == "function"
		and module.enabled("smart_island") and module.get("smart_island", "source_flight")
end

local function notify(payload)
	local ok, result = pcall(Everlook.island.notify, payload)
	if not ok and geterrorhandler then geterrorhandler()(type(result) == "string" and result or "Everlook flight notice failed") end
	return ok and type(result) == "number" and result or nil
end

local function end_island(completed)
	if not route or not route.island_handle then return end
	local delivered
	if completed and island_feed() then
		delivered = notify({ source = "everlook.flight_time", key = route.island_key, kind = "flight", severity = "success",
			text = "Arrived at " .. route.destination, presentation = "toast" })
	end
	if not delivered and Everlook.island and type(Everlook.island.dismiss) == "function" then
		pcall(Everlook.island.dismiss, route.island_handle)
	end
	route.island_handle, route.last_island = nil, nil
end

local function duration(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function update_island(now, elapsed, known)
	if not island_feed() then end_island(false); return end
	if route.last_island and now - route.last_island < 1 then return end
	route.last_island = now
	local detail = duration(elapsed) .. " elapsed"
	local progress
	local clock = duration(elapsed)
	if known then
		progress = math.min(1, elapsed / known.seconds)
		if elapsed < known.seconds then clock = duration(known.seconds - elapsed) end
		detail = detail .. (elapsed < known.seconds and ", ~" .. duration(known.seconds - elapsed) .. " left" or ", estimate exceeded")
	end
	local compact = { icon = "flight", text = clock }
	if #route.destination <= 16 and route.destination:find("|", 1, true) == nil and route.destination:find("\n", 1, true) == nil then
		compact.trailing = route.destination
	end
	local delivered = notify({ source = "everlook.flight_time", key = route.island_key, kind = "flight",
		text = "Flying to " .. route.destination, detail = detail, progress = progress, presentation = "status", capsule = compact })
	if delivered then route.island_handle = delivered else end_island(false) end
end

local function flights()
	local settings = EverlookDB.qol[id]
	settings.routes = settings.routes or {}
	return settings.routes
end

local function departure(index)
	if not module.enabled(id) or not NumTaxiNodes or not TaxiNodeName or not TaxiNodeGetType then return end
	local origin
	local count = NumTaxiNodes()
	if not number(count) or count < 1 then return end
	for node = 1, count do
		local kind = TaxiNodeGetType(node)
		if readable(kind) and kind == "CURRENT" then origin = TaxiNodeName(node); break end
	end
	local destination = TaxiNodeName(index)
	if not readable(origin) or not readable(destination) or type(origin) ~= "string" or type(destination) ~= "string" or origin == destination then return end
	local side = UnitFactionGroup and UnitFactionGroup("player") or ""
	local realm = GetRealmName and GetRealmName() or ""
	if not readable(side) or not readable(realm) or type(side) ~= "string" or type(realm) ~= "string" then return end
	local now = GetTime and GetTime()
	if not number(now) then return end
	end_island(false)
	next_trip = next_trip + 1
	route = { key = realm .. ":" .. side .. ":" .. origin .. ">" .. destination, requested = now, destination = destination, origin = origin,
		island_key = "flight:" .. next_trip }
	start_watch()
end

function stop_watch()
	interval = 0
	if poller then poller:SetScript("OnUpdate", nil) end
end

function start_watch()
	if not poller then return end
	poller:SetScript("OnUpdate", function(_, elapsed)
		interval = interval + elapsed
		if interval >= 0.25 then interval = 0; update() end
	end)
end

function update()
	if not module.enabled(id) or not UnitOnTaxi or not route then
		if frame then frame:Hide() end
		stop_watch()
		return
	end
	local now = GetTime()
	local flying = UnitOnTaxi("player")
	if not number(now) or not readable(flying) or type(flying) ~= "boolean" then frame:Hide(); return end
	if not flying then
		if route.started then
			local elapsed = now - route.started
			if elapsed > 1 then
				local previous = flights()[route.key]
				if type(previous) ~= "table" or not number(previous.seconds) or previous.seconds <= 0 then previous = nil end
				local samples = previous and previous.samples or 0
				if not number(samples) or samples < 0 then samples = 0 end
				flights()[route.key] = { seconds = ((previous and previous.seconds or 0) * samples + elapsed) / (samples + 1), samples = samples + 1 }
				if Everlook.taxi and Everlook.taxi.learn_duration then
					Everlook.taxi.learn_duration(route.origin, route.destination, elapsed)
				end
			end
			end_island(true)
			route = nil
		elseif now - route.requested > 10 then end_island(false); route = nil end
		frame:Hide()
		if not route then stop_watch() end
		return
	end
	route.started = route.started or now
	local elapsed = now - route.started
	if elapsed < 0 then frame:Hide(); return end
	local known = flights()[route.key]
	if type(known) ~= "table" or not number(known.seconds) or known.seconds <= 0 then known = nil end
	local text = route.destination .. "  " .. duration(elapsed)
	if known and module.get(id, "remaining") then text = text .. "  (~" .. duration(known.seconds - elapsed) .. " left)" end
	label:SetText(text)
	update_island(now, elapsed, known)
	if module.get(id, "only_island") and route.island_handle then frame:Hide() else frame:Show() end
end

local function apply(enabled)
	if not enabled then
		end_island(false)
		route = nil
		if frame then frame:Hide() end
		stop_watch()
		return
	end
	if not frame then
		frame = CreateFrame("Frame", "EverlookFlightTime", UIParent)
		frame:SetSize(400, 28)
		frame:SetPoint("TOP", 0, -150)
		label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		label:SetPoint("CENTER")
		-- The poller is its own frame so hiding the timer does not stop the sample.
		-- It stays idle on the ground. TakeTaxiNode starts it, and landing stops it.
		poller = CreateFrame("Frame", "EverlookFlightPoller")
		frame:Hide()
	end
	if route then start_watch() end
	if not hooked and TakeTaxiNode and hooksecurefunc then hooksecurefunc("TakeTaxiNode", departure); hooked = true end
end

module.register({
	addon = addon_name, page = "map", order = 30,
	id = id, name = "Flight time", description = "Shows a timer at the top of the screen for a flight you take after this is on, with the destination and the elapsed time, and remembers the route when that flight lasts more than a second. A flight already in the air stays hidden, the timer stays hidden on the ground, a shorter flight is not remembered, and reloading or turning this off during a flight discards that measurement.",
	options = {
		remaining = { name = "Show estimated time remaining", default = true, description = "Adds the learned time left to the timer at the top of the screen once a finished flight on this route has been recorded. Before that, or with this off, that timer keeps the destination and the elapsed time, and the Island keeps its own estimate." },
		only_island = { name = "Show flight timer only in Island", default = false, description = "Hides the timer at the top of the screen while the Island is showing this flight. That timer stays when Smart island is off, Show flight activity is off, or the Island does not accept the notice." },
	},
	apply = apply, events = { "ADDON_LOADED" }, on_event = function() apply(true) end,
})
