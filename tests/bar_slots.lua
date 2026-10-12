-- The action bar slots module: how it edits an Edit Mode layout as plain data, and how it
-- switches to that layout and back, on a stand-in for C_EditMode. How the game reacts to
-- the calls, and whether they taint its action bars, is not tested here.
return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)

	local SYSTEM, ALWAYS, VISIBLE = 0, 9, 5
	local PRESET, ACCOUNT, CHARACTER = 0, 1, 2
	local constants = {
		Enum = {
			EditModeSystem = { ActionBar = SYSTEM },
			EditModeActionBarSetting = { AlwaysShowButtons = ALWAYS, VisibleSetting = VISIBLE },
			EditModeLayoutType = { Preset = PRESET, Account = ACCOUNT, Character = CHARACTER },
		},
		Constants = { EditModeConsts = { EditModeMaxLayoutsPerType = 5 } },
	}

	-- A layout the way the game hands it out: systems with settings as { setting, value } rows.
	local function layout(name, layout_type, always)
		local systems = {}
		for index = 1, 3 do
			systems[#systems + 1] = { system = SYSTEM, systemIndex = index, isInDefaultPosition = true,
				settings = { { setting = VISIBLE, value = 0 }, { setting = ALWAYS, value = always } } }
		end
		systems[#systems + 1] = { system = 99, systemIndex = 2, settings = { { setting = ALWAYS, value = 1 } } }
		return { layoutName = name, layoutType = layout_type, systems = systems }
	end
	local function always_of(item, system_index)
		for _, system in ipairs(item.systems) do
			if system.system == SYSTEM and system.systemIndex == system_index then
				for _, row in ipairs(system.settings) do if row.setting == ALWAYS then return row.value end end
			end
		end
	end
	local function presets() return { layout("Modern", PRESET, 1), layout("Classic", PRESET, 1), layout("Minimalist", PRESET, 1) } end

	local function load_module(extra)
		local env = setmetatable({}, { __index = _G })
		env._G = env
		env.EverlookDB = {}
		env.UnitGUID = function() return "Player-1" end
		env.IsShiftKeyDown = function() return false end
		env.IsLoggedIn = function() return true end
		local loaded, frames = {}, {}
		env.EventUtil = { ContinueOnAddOnLoaded = function(name, callback) loaded[name] = callback end }
		env.CreateFrame = function()
			local frame = { events = {}, scripts = {} }
			function frame:RegisterEvent(event) self.events[event] = true end
			function frame:SetScript(name, callback) self.scripts[name] = callback end
			frames[#frames + 1] = frame
			return frame
		end
		for key, value in pairs(constants) do env[key] = value end
		for key, value in pairs(extra or {}) do env[key] = value end
		local addon = {}
		env.Everlook = addon
		for _, file in ipairs({ "module", "bar_layouts", "bar_slots" }) do
			local chunk = assert(loadfile(source(file)))
			setfenv(chunk, env)
			chunk(file == "bar_slots" and "Everlook_ActionBarSlots" or "Everlook", addon)
		end
		local function fire(event)
			for _, frame in ipairs(frames) do
				if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event) end
			end
		end
		return addon, env, loaded, fire
	end

	-- Pure logic on layout data.
	do
		local addon = load_module()
		local layouts = addon.bar_layouts
		local c = layouts.constants()
		check("the constants come from the game's own enums", c and c.system == SYSTEM and c.always_show == ALWAYS and c.character == CHARACTER and c.max == 5)

		local item = layout("Mine", ACCOUNT, 1)
		check("hiding empty slots reports a change", layouts.hide_empty(item, c) == true)
		check("the bars above the main bar stop showing empty slots", always_of(item, 2) == 0 and always_of(item, 3) == 0)
		check("the main bar and other systems keep theirs", always_of(item, 1) == 1 and item.systems[4].settings[1].value == 1)
		check("other settings stay as they were", item.systems[2].settings[1].value == 0)
		check("hiding again reports nothing to change", layouts.hide_empty(item, c) == false)

		local bare = layout("Bare", ACCOUNT, 1)
		bare.systems[2].settings = { { setting = VISIBLE, value = 0 } }
		check("a bar with no such row gets one set to hidden", layouts.hide_empty(bare, c) == true and always_of(bare, 2) == 0)

		local info = { layouts = { layout("Mine", ACCOUNT, 1) }, activeLayout = 1 }
		local result = layouts.prepare(info, presets(), c)
		check("from a preset a copy named Everlook is added after the saved layouts", result and result.created and #info.layouts == 2 and info.layouts[2].layoutName == "Everlook")
		check("the copy is a character layout", info.layouts[2].layoutType == CHARACTER)
		check("its index counts the presets first", result.index == 3 + 2)
		check("the copy hides the empty slots", always_of(info.layouts[2], 2) == 0 and always_of(info.layouts[2], 3) == 0)
		check("what it came from is remembered by name and type", result.previous and result.previous.name == "Modern" and result.previous.type == PRESET)
		check("the other saved layout is untouched", always_of(info.layouts[1], 2) == 1)

		local from_preset = presets()
		local source_layout = from_preset[1]
		layouts.prepare({ layouts = {}, activeLayout = 1 }, from_preset, c)
		check("the preset it copied is not changed", always_of(source_layout, 2) == 1)
		local fresh = { layouts = {}, activeLayout = 1 }
		layouts.prepare(fresh, presets(), c)
		check("the copy shares no tables with its source", fresh.layouts[1].systems[2].settings ~= source_layout.systems[2].settings)

		local saved = { layouts = { layout("Mine", ACCOUNT, 1), layout("Everlook", ACCOUNT, 1) }, activeLayout = 4 }
		result = layouts.prepare(saved, presets(), c)
		check("an Everlook layout that exists is reused", result and not result.created and #saved.layouts == 2 and result.index == 3 + 2)
		check("and has its empty slots hidden", result.changed and always_of(saved.layouts[2], 2) == 0)
		check("the layout in use is remembered", result.previous.name == "Mine" and result.previous.type == ACCOUNT)

		saved = { layouts = { layout("Everlook", ACCOUNT, 0) }, activeLayout = 4 }
		result = layouts.prepare(saved, presets(), c)
		check("when Everlook is already in use and done, nothing changes and nothing is remembered", result and not result.changed and result.previous == nil and result.index == 4)

		local full = { layouts = {}, activeLayout = 1 }
		for index = 1, 5 do full.layouts[index] = layout("Char " .. index, CHARACTER, 1) end
		local failed, reason = layouts.prepare(full, presets(), c)
		check("a full set of character layouts stops it", failed == nil and reason == "full" and #full.layouts == 5)

		failed, reason = layouts.prepare({ layouts = {}, activeLayout = 9 }, presets(), c)
		check("an active layout that is not there stops it", failed == nil and reason == "no active layout")
		check("a missing list stops it", layouts.prepare(nil, presets(), c) == nil and layouts.prepare({ layouts = {}, activeLayout = 1 }, nil, c) == nil)
		check("missing constants stop it", layouts.prepare({ layouts = {}, activeLayout = 1 }, presets(), nil) == nil)

		local both = { layouts = { layout("Mine", ACCOUNT, 1), layout("Mine", CHARACTER, 1) }, activeLayout = 1 }
		check("a layout is found by name and type", layouts.find(both, presets(), { name = "Mine", type = CHARACTER }) == 5
			and layouts.find(both, presets(), { name = "Mine", type = ACCOUNT }) == 4 and layouts.find(both, presets(), { name = "Classic", type = PRESET }) == 2)
		check("a layout that is gone is not found", layouts.find(both, presets(), { name = "Gone", type = ACCOUNT }) == nil)
	end

	-- Wiring, on a stand-in for C_EditMode that hands out copies like the game does.
	local function world(options)
		options = options or {}
		local state = { saved = options.saved or { layout("Mine", ACCOUNT, 1) }, active = options.active or 4, calls = {}, edit_mode = false, combat = false, ready = true, valid_names = true }
		local addon, env, loaded, fire
		local function copy(value)
			if type(value) ~= "table" then return value end
			local result = {}
			for key, inner in pairs(value) do result[key] = copy(inner) end
			return result
		end
		local extra = {
			InCombatLockdown = function() return state.combat end,
			EditModeManagerFrame = { IsEditModeActive = function() return state.edit_mode end },
			EditModePresetLayoutManager = { GetCopyOfPresetLayouts = function() return presets() end },
			C_EditMode = {
				GetLayouts = function()
					if not state.ready then return nil end
					return { layouts = copy(state.saved), activeLayout = state.active }
				end,
				SaveLayouts = function(info)
					state.calls[#state.calls + 1] = "save"
					state.saved = copy(info.layouts)
				end,
				OnLayoutAdded = function(index, activate, imported)
					state.calls[#state.calls + 1] = "added:" .. index .. ":" .. tostring(activate) .. ":" .. tostring(imported)
					if activate then state.active = index end
					fire("EDIT_MODE_LAYOUTS_UPDATED")
				end,
				SetActiveLayout = function(index)
					state.calls[#state.calls + 1] = "active:" .. index
					state.active = index
					fire("EDIT_MODE_LAYOUTS_UPDATED")
				end,
				IsValidLayoutName = function() return state.valid_names end,
			},
		}
		extra.EverlookDB = options.db
		extra.UnitGUID = options.guid and function() return options.guid end or nil
		for key, value in pairs(options.extra or {}) do extra[key] = value end
		addon, env, loaded, fire = load_module(extra)
		loaded["Everlook_ActionBarSlots"]()
		return addon, env, state, fire
	end
	local function layout_named(state, name)
		for _, item in ipairs(state.saved) do if item.layoutName == name then return item end end
	end

	do
		local addon, env, state = world()
		check("the module is registered, off, on the Interface page", addon.module.get("action_bar_slots", "enabled") == false)
		check("a disabled module leaves the layouts alone", #state.calls == 0 and #state.saved == 1)

		addon.module.set("action_bar_slots", "enabled", true)
		check("enabling saves a new Everlook layout and makes it the active one", state.calls[1] == "save" and state.calls[2] == "added:5:true:false" and state.active == 5)
		check("the saved layout hides empty slots on the bars above the main bar", layout_named(state, "Everlook") and always_of(layout_named(state, "Everlook"), 2) == 0)
		local remembered = env.EverlookDB.qol.action_bar_slots.switched["Player-1"]
		check("the layout in use before is remembered by name and type", remembered and remembered.name == "Mine" and remembered.type == ACCOUNT)
		local count = #state.calls
		addon.module.set("action_bar_slots", "enabled", true)
		check("applying again does not save again", #state.calls == count)

		addon.module.set("action_bar_slots", "enabled", false)
		check("disabling switches back to the layout that was in use", state.calls[#state.calls] == "active:4" and state.active == 4)
		check("the Everlook layout is kept", layout_named(state, "Everlook") ~= nil)
		count = #state.calls
		addon.module.set("action_bar_slots", "enabled", false)
		check("disabling again does nothing", #state.calls == count)
	end

	do
		-- The player switched layouts themselves: disabling does not switch them back.
		local addon, _, state = world()
		addon.module.set("action_bar_slots", "enabled", true)
		state.active = 3
		local count = #state.calls
		addon.module.set("action_bar_slots", "enabled", false)
		check("a layout the player chose is not switched away", #state.calls == count and state.active == 3)
		addon.module.set("action_bar_slots", "enabled", true)
		check("enabling later switches to the Everlook layout that is already there", state.calls[#state.calls] == "active:5" and state.active == 5 and #state.saved == 2)
	end

	do
		-- The option is one for the account, the layout in use is one for each character.
		local db = {}
		local first, _, first_state = world({ db = db, guid = "Player-A" })
		first.module.set("action_bar_slots", "enabled", true)
		check("the first character switches", first_state.active == 5)
		local second, _, second_state = world({ db = db, guid = "Player-B" })
		check("another character logging in with it on switches too", second_state.active == 5 and second_state.calls[1] == "save")
		second.module.set("action_bar_slots", "enabled", false)
		check("turning it off there switches that character back", second_state.active == 4)
		check("and keeps the first character's way back", db.qol.action_bar_slots.switched["Player-A"] ~= nil and db.qol.action_bar_slots.switched["Player-B"] == nil)
		local _, _, again = world({ db = db, guid = "Player-A", saved = first_state.saved, active = first_state.active })
		check("the first character switches back when it logs in with it off", again.active == 4 and again.calls[1] == "active:4")
		check("and its way back is cleared", db.qol.action_bar_slots.switched["Player-A"] == nil)
		local _, _, unknown = world({ db = { qol = { action_bar_slots = { enabled = true } } }, extra = { UnitGUID = function() return nil end } })
		check("a character it cannot name is left alone", #unknown.calls == 0)
	end

	do
		-- Already on the Everlook layout with the slots hidden: nothing to switch to, nothing to switch back.
		local addon, _, state = world({ saved = { layout("Everlook", CHARACTER, 0) }, active = 4 })
		addon.module.set("action_bar_slots", "enabled", true)
		check("nothing is saved or switched when the layout in use is already right", #state.calls == 0)
		addon.module.set("action_bar_slots", "enabled", false)
		check("and turning it off leaves the player where they are", #state.calls == 0 and state.active == 4)
	end

	do
		-- An Everlook layout that already exists is reused, not copied again.
		local addon, _, state = world({ saved = { layout("Mine", ACCOUNT, 1), layout("Everlook", ACCOUNT, 1) } })
		addon.module.set("action_bar_slots", "enabled", true)
		check("an existing Everlook layout is saved and switched to, not added", state.calls[1] == "save" and state.calls[2] == "active:5" and #state.saved == 2 and state.active == 5)
		check("and has its empty slots hidden", always_of(layout_named(state, "Everlook"), 3) == 0)
	end

	do
		-- Guards.
		local addon, _, state, fire = world()
		state.combat = true
		addon.module.set("action_bar_slots", "enabled", true)
		check("nothing happens in combat", #state.calls == 0)
		state.combat = false
		fire("PLAYER_REGEN_ENABLED")
		check("it goes ahead when combat ends", state.calls[1] == "save" and state.active == 5)

		addon, _, state = world()
		state.edit_mode = true
		addon.module.set("action_bar_slots", "enabled", true)
		check("nothing happens while Edit Mode is open", #state.calls == 0)

		addon, _, state, fire = world()
		state.ready = false
		addon.module.set("action_bar_slots", "enabled", true)
		check("nothing happens before the game has its layouts", #state.calls == 0)
		state.ready = true
		fire("EDIT_MODE_LAYOUTS_UPDATED")
		check("it tries again when the layouts arrive", state.calls[1] == "save" and state.active == 5)

		addon, _, state = world()
		state.valid_names = false
		addon.module.set("action_bar_slots", "enabled", true)
		check("a name the game refuses stops it", #state.calls == 0)

		addon, _, state = world({ extra = { C_EditMode = {} } })
		check("a client without the layout calls does nothing and does not fail", pcall(addon.module.set, "action_bar_slots", "enabled", true) and #state.calls == 0)

		local full = {}
		for index = 1, 5 do full[index] = layout("Char " .. index, CHARACTER, 1) end
		addon, _, state = world({ saved = full })
		addon.module.set("action_bar_slots", "enabled", true)
		check("a full set of character layouts stops it", #state.calls == 0 and #state.saved == 5)
	end

	do
		-- Logging in with it already on and done does nothing.
		local addon, env, state, fire = world()
		addon.module.set("action_bar_slots", "enabled", true)
		local count = #state.calls
		fire("PLAYER_ENTERING_WORLD")
		fire("EDIT_MODE_LAYOUTS_UPDATED")
		check("events after it is done change nothing", #state.calls == count)
		check("its record does not share a name with an option", env.EverlookDB.qol.action_bar_slots.switched["Player-1"] ~= nil)
	end
end
