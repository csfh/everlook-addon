local _, Everlook = ...
local registry = Everlook.module
Everlook.settings = {}
local category

local function whole(number)
	return math.floor(number + 0.5)
end

-- An option with `percent` is saved as a fraction, such as 0.8, and shown as
-- 80%, so a slider counts in whole numbers and the saved value keeps its meaning.
local function shown(option, value)
	if option.percent and type(value) == "number" then return whole(value * 100) end
	return value
end

-- The native slider hands over the value under the thumb. The label shows the
-- step that value will be saved on.
local function slider_label(option)
	local unit = option.percent and "%" or option.unit or ""
	return function(value)
		return tostring(whole(shown(option, registry.snap(option, option.percent and value / 100 or value)))) .. unit
	end
end

local function setting(page, module, key)
	local option = module.options[key]
	local variable = "Everlook_QoL_" .. module.id .. "_" .. key
	local proxy = Settings.RegisterProxySetting(page, variable, type(option.default), option.name, shown(option, option.default),
		function() return shown(option, registry.get(module.id, key)) end,
		function(value) registry.set(module.id, key, option.percent and value / 100 or value) end)
	if option.choices then
		local function choices()
			local container = Settings.CreateControlTextContainer()
			for _, choice in ipairs(option.choices) do container:Add(choice[1], choice[2]) end
			return container:GetData()
		end
		return Settings.CreateDropdown(page, proxy, choices, option.description or module.description)
	elseif type(option.default) == "boolean" then
		return Settings.CreateCheckbox(page, proxy, option.description or module.description)
	else
		local slider = Settings.CreateSliderOptions(shown(option, option.min), shown(option, option.max), shown(option, option.step or 1))
		if MinimalSliderWithSteppersMixin then
			slider:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, slider_label(option))
		end
		return Settings.CreateSlider(page, proxy, slider, option.description or module.description)
	end
end

local function add_option(page, page_layout, module, key, toggle)
	local control = setting(page, module, key)
	control:SetParentInitializer(toggle, function() return registry.enabled(module.id) end)
end

local subpages = {}

-- The game's own switch for logging taint is its console variable. The log
-- helps when chasing a blocked action, but at level 2 calls to methods that
-- addons hook have failed with "attempt to call a nil value", and choosing
-- level 2 on this page crashed the client while the settings menu rebuilt, on
-- build 70338. So the page only turns the log off. Turning it on is /console.
local TAINT_LOG = "taintLog"
local TAINT_LOG_HELP = "Writes what taints addon code to Logs/taint.log, which helps when chasing a blocked action. Keep it off otherwise: with it on, the game can make calls to methods that addons hook fail with \"attempt to call a nil value\", which has been seen at level 2. This page only turns it off, because choosing level 2 here crashed the game. To turn it on, type /console taintLog 1 or /console taintLog 2."

local function turn_taint_log_off()
	SetCVar(TAINT_LOG, 0)
	Everlook.say("Taint log is off.")
end

-- What the module registry noted while loading: events this client does not know, and listeners that raised.
local function module_problems()
	local lines = {}
	local events = {}
	for event in pairs(registry.unsupported_events or {}) do events[#events + 1] = event end
	table.sort(events)
	if #events > 0 then lines[#lines + 1] = "This client has no event " .. table.concat(events, ", ") .. "; the modules that name it ran without it." end
	local failed = {}
	for id, count in pairs(registry.listener_failures or {}) do failed[#failed + 1] = id .. " (" .. count .. ")" end
	table.sort(failed)
	if #failed > 0 then lines[#lines + 1] = "Errors in module event handlers since login: " .. table.concat(failed, ", ") .. "." end
	return table.concat(lines, " ")
end

local function add_debug_page()
	local has_taint_log = false
	if type(GetCVar) == "function" and type(SetCVar) == "function" then
		local present, current = pcall(GetCVar, TAINT_LOG)
		has_taint_log = present and current ~= nil
	end
	local problems = module_problems()
	if not has_taint_log and problems == "" then return end
	local page, page_layout = Settings.RegisterVerticalLayoutSubcategory(category, "Debug")
	subpages[#subpages + 1] = page
	if problems ~= "" then
		page_layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Modules", problems))
	end
	if has_taint_log then
		page_layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Taint log", TAINT_LOG_HELP))
		page_layout:AddInitializer(CreateSettingsButtonInitializer("Taint log", "Turn off", turn_taint_log_off, TAINT_LOG_HELP, true))
	end
end

-- Module addons load after Everlook, so the page waits for login, when all of
-- them have registered and their key bindings are known.
local function build()
	if not Settings or not Settings.RegisterProxySetting or not Settings.RegisterVerticalLayoutCategory
		or not Settings.RegisterVerticalLayoutSubcategory or not Settings.RegisterCanvasLayoutSubcategory then return end
	local layout
	category, layout = Settings.RegisterVerticalLayoutCategory("Everlook")
	if Everlook.config and Everlook.config.describe then
		local _, signing = Everlook.config.describe()
		if type(signing) == "string" and signing ~= "" then
			layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(signing))
		end
	end
	layout:AddInitializer(CreateSettingsButtonInitializer("Eager scan", "Scan", Everlook.scan.now,
		"Read your bags, gear, spellbook, talents, currencies, professions, nearby units, factions and quest lines once, now.", true))
	-- Each subject is a page in the list on the left.
	local order, grouped, labels = registry.chapters()
	for _, group in ipairs(order) do
		local modules = grouped[group]
		if #modules > 0 then
			local page, page_layout = Settings.RegisterVerticalLayoutSubcategory(category, labels[group])
			subpages[#subpages + 1] = page
			for _, module in ipairs(modules) do
				page_layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(module.name, module.description))
				local toggle = setting(page, module, "enabled")
				-- The game's own key row. Its listener saves the binding, so the key can be set here or under Key Bindings.
				local binding_index = module.keybinding and C_KeyBindings and C_KeyBindings.GetBindingIndex
					and C_KeyBindings.GetBindingIndex(module.keybinding)
				if binding_index and CreateKeybindingEntryInitializer then
					page_layout:AddInitializer(CreateKeybindingEntryInitializer(binding_index))
				end
				for _, extra in ipairs(module.extra_keybindings or {}) do
					local extra_index = C_KeyBindings and C_KeyBindings.GetBindingIndex and C_KeyBindings.GetBindingIndex(extra)
					if extra_index and CreateKeybindingEntryInitializer then
						page_layout:AddInitializer(CreateKeybindingEntryInitializer(extra_index))
					end
				end
				local sections = registry.sections(module)
				if sections then
					local covered = {}
					for _, section in ipairs(sections) do
						page_layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(section.name))
						for _, key in ipairs(section.keys) do
							assert(module.options[key], "Unknown Everlook section option " .. module.id .. "." .. key)
							assert(not covered[key], "Duplicate Everlook section option " .. module.id .. "." .. key)
							covered[key] = true
							add_option(page, page_layout, module, key, toggle)
						end
						if section.after then section.after(page_layout) end
					end
					for key in pairs(module.options) do
						if key ~= "enabled" then assert(covered[key], "Everlook section missing " .. module.id .. "." .. key) end
					end
				else
					local keys = {}
					for key in pairs(module.options) do if key ~= "enabled" then keys[#keys + 1] = key end end
					table.sort(keys)
					for _, key in ipairs(keys) do
						add_option(page, page_layout, module, key, toggle)
					end
					if module.settings_initializers then module.settings_initializers(page_layout) end
				end
			end
		end
	end
	subpages[#subpages + 1] = Settings.RegisterCanvasLayoutSubcategory(category, Everlook.collected.page(), "Collected data")
	if Everlook.sched and Everlook.sched.page then
		subpages[#subpages + 1] = Settings.RegisterCanvasLayoutSubcategory(category, Everlook.sched.page(), "Performance")
	end
	add_debug_page()
	Settings.RegisterAddOnCategory(category)
end

-- Timed into the load trace: bytes too, where the client says.
local built = false
local function ensure()
	if built then return end
	built = true
	local trace = Everlook.trace
	if not trace then return build() end
	local before = collectgarbage and collectgarbage("count")
	trace.span("settings", build)
	if before then trace.count("settings_kb", math.floor(collectgarbage("count") - before)) end
end

-- Nobody opens the page during the loading screen, and building it takes
-- milliseconds and over a megabyte, so it waits for a coming frame once every
-- module has registered. Opening the page first builds it on the spot.
EventUtil.ContinueOnPlayerLogin(function()
	if Everlook.sched and Everlook.world and Everlook.world.defer then
		Everlook.world.defer("settings", ensure)
	else
		ensure()
	end
end)

local function showing_everlook()
	if not SettingsPanel or not SettingsPanel:IsShown() then return false end
	local current = SettingsPanel:GetCurrentCategory()
	if current == category then return true end
	for index = 1, #subpages do
		if subpages[index] == current then return true end
	end
	return false
end

-- The minimap icon and /everlook both come here: open the Everlook page, or
-- close the settings window if it is already showing Everlook or one of its subpages.
function Everlook.settings.toggle()
	ensure()
	if not category then return end
	if showing_everlook() then
		HideUIPanel(SettingsPanel)
	else
		Settings.OpenToCategory(category:GetID())
	end
end

SLASH_EVERLOOK1 = "/everlook"
SlashCmdList = SlashCmdList or {}
SlashCmdList.EVERLOOK = Everlook.settings.toggle
