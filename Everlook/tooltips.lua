local _, Everlook = ...

-- One owner for the game's tooltip post-calls. A module adds a callback for a kind of tooltip
-- and the first one for that kind installs a single post-call, so the game calls Everlook once
-- per tooltip however many modules add lines. Each callback runs under pcall: an error in one
-- is shown by the game's error handler and counted, and the next still runs.
Everlook.tooltips = { failures = {} }
local service = Everlook.tooltips

local KINDS = { item = "Item", spell = "Spell", unit = "Unit" }
local LEGACY_SCRIPTS = { item = "OnTooltipSetItem", unit = "OnTooltipSetUnit" }

local callbacks = { item = {}, spell = {}, unit = {} }
local installed = {}
-- What each owner last put on a tooltip: the key it was for and how many lines the tooltip
-- held afterwards. A tooltip is rebuilt for the same thing without being cleared now and then;
-- fewer lines than before means it was rebuilt and the owner may add its lines again.
local added = setmetatable({}, { __mode = "k" })

local function state_for(tooltip)
	local state = added[tooltip]
	if state then return state end
	state = {}
	added[tooltip] = state
	if type(tooltip.HasScript) == "function" and tooltip:HasScript("OnTooltipCleared")
		and type(tooltip.HookScript) == "function" and not tooltip.everlook_tooltips_clear then
		tooltip.everlook_tooltips_clear = true
		tooltip:HookScript("OnTooltipCleared", function(self) added[self] = nil end)
	end
	return state
end

local function line_count(tooltip)
	return type(tooltip.NumLines) == "function" and tooltip:NumLines() or 0
end

-- Whether an owner has already put its lines for this key on this tooltip.
function service.done(owner, tooltip, key)
	local entry = state_for(tooltip)[owner]
	return entry ~= nil and entry.key == key and line_count(tooltip) >= entry.lines
end

-- True the first time an owner asks for a key on a tooltip, and again after the tooltip is
-- cleared or rebuilt. The caller adds its lines when this is true.
function service.once(owner, tooltip, key)
	if service.done(owner, tooltip, key) then return false end
	state_for(tooltip)[owner] = { key = key, lines = line_count(tooltip) }
	return true
end

local function dispatch(kind, tooltip, data)
	for _, entry in ipairs(callbacks[kind]) do
		local ok, message = pcall(entry.fn, tooltip, data)
		if not ok then
			service.failures[entry.owner] = (service.failures[entry.owner] or 0) + 1
			if Everlook.errors then Everlook.errors.note(entry.owner, message) end
			local handler = geterrorhandler and geterrorhandler()
			if handler then pcall(handler, message) end
		end
		local state = added[tooltip]
		if state and state[entry.owner] then state[entry.owner].lines = line_count(tooltip) end
	end
end

local function install(kind)
	if installed[kind] then return end
	if type(TooltipDataProcessor) == "table" and type(TooltipDataProcessor.AddTooltipPostCall) == "function"
		and type(Enum) == "table" and type(Enum.TooltipDataType) == "table" and Enum.TooltipDataType[KINDS[kind]] ~= nil then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType[KINDS[kind]], function(tooltip, data) dispatch(kind, tooltip, data) end)
		installed[kind] = true
	elseif LEGACY_SCRIPTS[kind] and GameTooltip and type(GameTooltip.HasScript) == "function" and GameTooltip:HasScript(LEGACY_SCRIPTS[kind]) then
		GameTooltip:HookScript(LEGACY_SCRIPTS[kind], function(tooltip) dispatch(kind, tooltip) end)
		installed[kind] = true
	end
end

-- Adds a callback for "item", "spell" or "unit" tooltips. It is called with the tooltip and the
-- game's tooltip data, and installs the one post-call for that kind when it is the first.
-- Nothing happens when the client has no way to add to a tooltip.
function service.add(owner, kind, fn)
	assert(callbacks[kind], "Unknown tooltip kind")
	local list = callbacks[kind]
	for _, entry in ipairs(list) do
		if entry.owner == owner and entry.fn == fn then return end
	end
	list[#list + 1] = { owner = owner, fn = fn }
	install(kind)
end
