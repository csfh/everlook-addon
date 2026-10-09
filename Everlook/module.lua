local _, Everlook = ...

-- Module addons register here. The registry keeps their settings in
-- EverlookDB.qol, sends them their events, and places them on a settings page.
Everlook.module = { modules = {} }
local registry = Everlook.module
local by_id, listeners = {}, {}
local frame = CreateFrame("Frame")

-- The settings pages, in the order the left list shows them. A module names
-- its page with `page` and its place on that page with `order`.
local PAGES = {
	{ id = "quests", label = "Quests" },
	{ id = "vendors", label = "Vendors" },
	{ id = "loot", label = "Loot and mail" },
	{ id = "social", label = "Social" },
	{ id = "chat", label = "Chat" },
	{ id = "tooltips", label = "Tooltips" },
	{ id = "map", label = "Map" },
	{ id = "interface", label = "Interface" },
	{ id = "smart_island", label = "Smart island" },
	{ id = "radial_menu", label = "Radial menu" },
}
local page_labels = {}
for _, page in ipairs(PAGES) do page_labels[page.id] = page.label end

local function saved(id)
	EverlookDB = EverlookDB or {}
	EverlookDB.qol = EverlookDB.qol or {}
	EverlookDB.qol[id] = EverlookDB.qol[id] or {}
	return EverlookDB.qol[id]
end

-- An option with choices holds one of their values. A saved value that is no
-- longer on the list falls back to the default.
local function allowed(option, value)
	if not option.choices then return true end
	for _, choice in ipairs(option.choices) do
		if choice[1] == value then return true end
	end
	return false
end

-- How many decimals a step or minimum is written with, so a value that lands
-- on a step is stored as that number and not as 0.30000000000000004.
local function decimals(number)
	for places = 0, 6 do
		local scaled = number * 10 ^ places
		if math.abs(scaled - math.floor(scaled + 0.5)) < 1e-9 then return places end
	end
	return 6
end

-- A slider's value held between its ends and on its steps, counted from the minimum.
local function on_step(option, value)
	local step = option.step or 1
	value = option.min + math.floor((value - option.min) / step + 0.5) * step
	value = math.max(option.min, math.min(option.max, value))
	return tonumber(string.format("%." .. math.max(decimals(step), decimals(option.min)) .. "f", value))
end

local function fill_defaults(id, options)
	local values = saved(id)
	for key, option in pairs(options) do
		if type(values[key]) ~= type(option.default) or not allowed(option, values[key]) then values[key] = option.default end
	end
end

registry.snap = on_step

function registry.get(id, key)
	local module = assert(by_id[id], "Unknown Everlook module")
	local value = EverlookDB and EverlookDB.qol and EverlookDB.qol[id] and EverlookDB.qol[id][key]
	local option = module.options[key]
	if option and not (issecretvalue and issecretvalue(value)) and type(value) == type(option.default) and allowed(option, value) then
		if type(value) == "number" then
			if value ~= value or value == math.huge or value == -math.huge then return option.default end
			if option.min then return on_step(option, value) end
		end
		return value
	end
	return option and option.default
end

function registry.loaded(id)
	return by_id[id] ~= nil
end

-- False for a module whose addon is not loaded, so one module can ask about
-- another that the player turned off in the addon list.
function registry.enabled(id)
	return by_id[id] ~= nil and registry.get(id, "enabled") == true
end

function registry.paused()
	return IsShiftKeyDown and IsShiftKeyDown()
end

local function apply(module)
	local enabled = registry.enabled(module.id)
	if module.apply then module.apply(enabled) end
	for _, extension in ipairs(module.extensions) do
		if extension.apply then extension.apply(enabled) end
	end
end

function registry.set(id, key, value)
	local module = assert(by_id[id], "Unknown Everlook module")
	local option = assert(module.options[key], "Unknown Everlook module option")
	assert(not (issecretvalue and issecretvalue(value)) and type(value) == type(option.default) and allowed(option, value), "Invalid Everlook module option")
	if type(value) == "number" then assert(value == value and value > -math.huge and value < math.huge, "Invalid Everlook module number") end
	if option.min then value = on_step(option, value) end
	saved(id)[key] = value
	apply(module)
end

local function by_order(left, right)
	if left.order ~= right.order then return left.order < right.order end
	return left.id < right.id
end

function registry.chapters()
	local grouped, order, labels = {}, {}, {}
	for _, page in ipairs(PAGES) do
		order[#order + 1] = page.id
		labels[page.id] = page.label
		grouped[page.id] = {}
	end
	for _, module in ipairs(registry.modules) do
		local list = grouped[module.page]
		list[#list + 1] = module
	end
	for _, list in pairs(grouped) do table.sort(list, by_order) end
	return order, grouped, labels
end

-- The host's sections with each extension's keys and buttons added. An
-- extension's keys follow the host's, or go in front of the host key its
-- section names as `before`. A section the host does not have comes after the
-- host's own.
function registry.sections(module)
	if not module.sections then return nil end
	local merged, by_name = {}, {}
	local function section_for(name)
		if not by_name[name] then
			by_name[name] = { name = name, keys = {}, afters = {} }
			merged[#merged + 1] = by_name[name]
		end
		return by_name[name]
	end
	local function add(section)
		local target = section_for(section.name)
		local at = #target.keys + 1
		for index, key in ipairs(target.keys) do
			if key == section.before then at = index; break end
		end
		for _, key in ipairs(section.keys or {}) do
			table.insert(target.keys, at, key)
			at = at + 1
		end
		if section.after then target.afters[#target.afters + 1] = section.after end
	end
	for _, section in ipairs(module.sections) do add(section) end
	for _, extension in ipairs(module.extensions) do
		for _, section in ipairs(extension.sections or {}) do add(section) end
	end
	for _, section in ipairs(merged) do
		local afters = section.afters
		section.after = #afters > 0 and function(layout)
			for _, after in ipairs(afters) do after(layout) end
		end or nil
		section.afters = nil
	end
	return merged
end

-- A host calls hooks of its own on its extensions, in their order.
function registry.extensions(id)
	local module = by_id[id]
	return module and module.extensions or {}
end

local function listen(owner, events, on_event)
	for _, event in ipairs(events or {}) do
		if not listeners[event] then listeners[event] = {}; frame:RegisterEvent(event) end
		listeners[event][#listeners[event] + 1] = { owner = owner, on_event = on_event }
	end
end

-- Defaults and the first apply wait for the module's own addon to finish
-- loading, so a module spread over several files sees all of them.
function registry.register(module)
	assert(type(module.id) == "string", "Everlook module needs an id")
	assert(not by_id[module.id], "Duplicate Everlook module " .. module.id)
	assert(type(module.addon) == "string", "Everlook module " .. module.id .. " names no addon")
	assert(page_labels[module.page], "Everlook module " .. module.id .. " has no settings page")
	assert(type(module.order) == "number", "Everlook module " .. module.id .. " has no place on its page")
	module.options = module.options or {}
	module.options.enabled = { name = "Enable " .. module.name, default = false, description = module.description }
	module.extensions = {}
	by_id[module.id] = module
	registry.modules[#registry.modules + 1] = module
	listen(module, module.events, module.on_event)
	EventUtil.ContinueOnAddOnLoaded(module.addon, function()
		fill_defaults(module.id, module.options)
		apply(module)
	end)
	return module
end

-- An extension adds options, settings rows and events to a module another
-- addon registered. Its options are saved under the host, and its events and
-- apply run with the host's enabled state.
function registry.extend(host_id, extension)
	local host = assert(by_id[host_id], "Everlook extension needs the " .. tostring(host_id) .. " module")
	assert(type(extension.id) == "string", "Everlook extension needs an id")
	assert(type(extension.addon) == "string", "Everlook extension " .. extension.id .. " names no addon")
	assert(type(extension.order) == "number", "Everlook extension " .. extension.id .. " has no order")
	for _, other in ipairs(host.extensions) do
		assert(other.id ~= extension.id, "Duplicate Everlook extension " .. extension.id)
	end
	extension.options = extension.options or {}
	for key, option in pairs(extension.options) do
		assert(not host.options[key], "Everlook option " .. host_id .. "." .. key .. " is already taken")
		host.options[key] = option
	end
	host.extensions[#host.extensions + 1] = extension
	table.sort(host.extensions, by_order)
	listen(host, extension.events, extension.on_event)
	EventUtil.ContinueOnAddOnLoaded(extension.addon, function()
		fill_defaults(host_id, extension.options)
		if extension.apply then extension.apply(registry.enabled(host_id)) end
	end)
	return extension
end

frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_REGEN_ENABLED" then
		for _, module in ipairs(registry.modules) do
			if module.out_of_combat then apply(module) end
		end
	end
	for _, listener in ipairs(listeners[event] or {}) do
		if registry.enabled(listener.owner.id) then listener.on_event(event, ...) end
	end
end)
