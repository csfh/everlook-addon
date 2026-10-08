local _, Everlook = ...
local registry = Everlook.module
Everlook.settings = {}
local category

local function setting(page, module, key)
	local option = module.options[key]
	local variable = "Everlook_QoL_" .. module.id .. "_" .. key
	local proxy = Settings.RegisterProxySetting(page, variable, type(option.default), option.name, option.default,
		function() return registry.get(module.id, key) end,
		function(value) registry.set(module.id, key, value) end)
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
		local slider = Settings.CreateSliderOptions(option.min, option.max, option.step or 1)
		if MinimalSliderWithSteppersMixin then
			slider:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, tostring)
		end
		return Settings.CreateSlider(page, proxy, slider, option.description or module.description)
	end
end

local function add_option(page, page_layout, module, key, toggle)
	local control = setting(page, module, key)
	control:SetParentInitializer(toggle, function() return registry.enabled(module.id) end)
end

local subpages = {}

-- Module addons load after Everlook, so the page waits for login, when all of
-- them have registered and their key bindings are known.
EventUtil.ContinueOnPlayerLogin(function()
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
	Settings.RegisterAddOnCategory(category)
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
