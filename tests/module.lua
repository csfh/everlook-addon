-- The module registry on its own: registration from other addons, settings
-- page order, and extensions that add to a module another addon registered.
return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)
	local function load_registry()
		local namespace = {}
		local loaded, waiting, frames = {}, {}, {}
		local env = setmetatable({}, { __index = _G })
		env._G = env
		env.frames = frames
		env.EverlookDB = {}
		env.EventUtil = {
			ContinueOnAddOnLoaded = function(name, callback)
				if loaded[name] then return callback() end
				waiting[name] = waiting[name] or {}
				table.insert(waiting[name], callback)
			end,
		}
		env.CreateFrame = function()
			local frame = { events = {} }
			function frame:RegisterEvent(event)
				if env.unknown_events and env.unknown_events[event] then error("Frame:RegisterEvent(): Attempt to register unknown event \"" .. event .. "\"") end
				self.events[event] = true
			end
			function frame:UnregisterEvent(event) self.events[event] = nil end
			function frame:SetScript(_, callback) self.on_event = callback end
			frames[#frames + 1] = frame
			return frame
		end
		local chunk = assert(loadfile(source("module")))
		setfenv(chunk, env)
		chunk("Everlook", namespace)
		local function finish(name)
			loaded[name] = true
			for _, callback in ipairs(waiting[name] or {}) do callback() end
			waiting[name] = nil
		end
		local function fire(event, ...)
			for _, frame in ipairs(frames) do
				if frame.events[event] then frame.on_event(frame, event, ...) end
			end
		end
		finish("Everlook")
		return namespace.module, env, finish, fire
	end

	local function plain(registry, id, page, order, extra)
		local spec = { id = id, name = id, description = id, addon = "Everlook_" .. id, page = page, order = order }
		for key, value in pairs(extra or {}) do spec[key] = value end
		return registry.register(spec)
	end

	do
		local registry, env, finish = load_registry()
		local applied = {}
		plain(registry, "late", "vendors", 10, {
			options = { amount = { name = "Amount", default = 3, min = 1, max = 5 } },
			apply = function(enabled) applied[#applied + 1] = enabled end,
		})
		check("a module waits for its own addon before its first apply", #applied == 0 and env.EverlookDB.qol == nil)
		env.EverlookDB.qol = { late = { amount = "three", enabled = true } }
		finish("Everlook_late")
		check("a module registered after Everlook still gets its defaults and one apply",
			#applied == 1 and applied[1] == true and registry.get("late", "amount") == 3 and env.EverlookDB.qol.late.amount == nil)
	end

	do
		local registry, env, finish = load_registry()
		plain(registry, "sliders", "map", 10, {
			options = {
				whole = { name = "Whole", default = 12, min = 10, max = 20, step = 1 },
				fraction = { name = "Fraction", default = 0.5, min = 0, max = 1, step = 0.1 },
				quarter = { name = "Quarter", default = 1, min = 0.25, max = 4, step = 0.25 },
				coarse = { name = "Coarse", default = 100, min = 80, max = 150, step = 5 },
			},
		})
		finish("Everlook_sliders")
		registry.set("sliders", "whole", 13.47)
		check("a slider value snaps to its nearest step", registry.get("sliders", "whole") == 13 and env.EverlookDB.qol.sliders.whole == 13)
		registry.set("sliders", "coarse", 97)
		check("a step wider than one snaps to its multiple", registry.get("sliders", "coarse") == 95)
		registry.set("sliders", "coarse", 98)
		check("a value halfway past a step rounds up", registry.get("sliders", "coarse") == 100)
		registry.set("sliders", "fraction", 0.1 + 0.2)
		check("a fractional step stores exactly the number it names", env.EverlookDB.qol.sliders.fraction == 0.3)
		registry.set("sliders", "quarter", 0.4)
		check("a quarter step snaps from the minimum", registry.get("sliders", "quarter") == 0.5)
		registry.set("sliders", "coarse", 500)
		check("a value above the maximum is held at it", registry.get("sliders", "coarse") == 150)
		registry.set("sliders", "coarse", 1)
		check("a value below the minimum is held at it", registry.get("sliders", "coarse") == 80)
		env.EverlookDB.qol.sliders.fraction = 0.1 + 0.2
		env.EverlookDB.qol.sliders.whole = 13.4
		check("a saved value off its step reads back on it", registry.get("sliders", "fraction") == 0.3 and registry.get("sliders", "whole") == 13)
	end

	do
		local registry = load_registry()
		check("a module that is not loaded counts as off",registry.enabled("missing") == false and registry.loaded("missing") == false)
		check("an unknown page is refused", not pcall(plain, registry, "lost", "nowhere", 10))
		check("the old catch-all Interface page is gone", not pcall(plain, registry, "catchall", "interface", 10))
		check("a module must name its addon", not pcall(registry.register, { id = "anonymous", name = "x", page = "map", order = 10 }))
		check("a module must have a place on its page", not pcall(plain, registry, "unplaced", "map"))
		plain(registry, "twice", "map", 10)
		check("a module id registers once", not pcall(plain, registry, "twice", "map", 20))
	end

	do
		local registry = load_registry()
		plain(registry, "third", "map", 30)
		plain(registry, "first", "map", 10)
		plain(registry, "quest", "quests", 10)
		plain(registry, "second", "map", 20)
		local order, grouped, labels = registry.chapters()
		local ids = {}
		for _, module in ipairs(grouped.map) do ids[#ids + 1] = module.id end
		check("a page lists its modules by order, whatever addon loaded first", table.concat(ids, ",") == "first,second,third")
		check("pages keep their place and label", order[1] == "quests" and order[7] == "map" and labels.loot == "Loot and mail" and #grouped.quests == 1)
		check("a page with no loaded module is empty", #grouped.vendors == 0)
	end

	do
		local registry, env, finish, fire = load_registry()
		local host_applies, extension_applies, heard = {}, {}, {}
		plain(registry, "host", "smart_island", 10, {
			options = { size = { name = "Size", default = 100, min = 80, max = 150 } },
			sections = {
				{ name = "Placement", keys = { "size" }, after = function(layout) layout[#layout + 1] = "host button" end },
				{ name = "Notices", keys = {} },
			},
			apply = function(enabled) host_applies[#host_applies + 1] = enabled end,
		})
		finish("Everlook_host")
		registry.extend("host", {
			id = "loot", addon = "Everlook_loot", order = 20,
			options = { feed_loot = { name = "Loot", default = false } },
			sections = { { name = "Notices", keys = { "feed_loot" }, after = function(layout) layout[#layout + 1] = "loot button" end } },
			events = { "CHAT_MSG_LOOT" },
			on_event = function(event, message) heard[#heard + 1] = event .. ":" .. message end,
			apply = function(enabled) extension_applies[#extension_applies + 1] = enabled end,
		})
		registry.extend("host", {
			id = "mail", addon = "Everlook_mail", order = 10,
			options = { feed_mail = { name = "Mail", default = true } },
			sections = { { name = "Notices", keys = { "feed_mail" } }, { name = "Extra", keys = {} } },
		})
		check("an extension's apply waits for its addon", #extension_applies == 0)
		finish("Everlook_loot")
		finish("Everlook_mail")
		check("an extension's option is saved under the host",
			registry.get("host", "feed_loot") == false and registry.get("host", "feed_mail") == true and env.EverlookDB.qol.host.feed_mail == nil)
		registry.set("host", "feed_loot", true)
		check("an extension option is set through the host", env.EverlookDB.qol.host.feed_loot == true and registry.get("host", "feed_loot") == true)
		check("an option name is taken once per host", not pcall(registry.extend, "host", {
			id = "clash", addon = "Everlook_clash", order = 30, options = { size = { name = "Size", default = 1 } },
		}))
		check("an extension needs its host", not pcall(registry.extend, "absent", { id = "orphan", addon = "Everlook_orphan", order = 10 }))
		fire("CHAT_MSG_LOOT", "while off")
		check("an extension hears nothing while the host is off", #heard == 0)
		local before = #extension_applies
		registry.set("host", "enabled", true)
		check("an extension applies with the host's state", #extension_applies == before + 1 and extension_applies[#extension_applies] == true and host_applies[#host_applies] == true)
		fire("CHAT_MSG_LOOT", "epic")
		check("an extension hears its events while the host is on", heard[1] == "CHAT_MSG_LOOT:epic" and #heard == 1)

		local sections = registry.sections(registry.modules[1])
		local names, notices = {}, nil
		for _, section in ipairs(sections) do
			names[#names + 1] = section.name
			if section.name == "Notices" then notices = section end
		end
		check("extension sections join the host's, and new ones come after", table.concat(names, ",") == "Placement,Notices,Extra")
		check("extension keys follow the host's keys in extension order", table.concat(notices.keys, ",") == "feed_mail,feed_loot")
		local layout = {}
		notices.after(layout)
		sections[1].after(layout)
		check("section buttons keep running after an extension adds its own", layout[1] == "loot button" and layout[2] == "host button")
		check("a host without sections has no merged sections", registry.sections(plain(registry, "simple", "map", 10)) == nil)
		local hooks = registry.extensions("host")
		check("a host reaches its extensions in order to call hooks of its own", #hooks == 2 and hooks[1].id == "mail" and hooks[2].id == "loot")
		check("a module that is not loaded has no extensions", #registry.extensions("missing") == 0)
	end

	do
		local registry, _, finish = load_registry()
		plain(registry, "host", "smart_island", 10, {
			options = { repair = { name = "Repair", default = true } },
			sections = { { name = "Activity", keys = { "repair" } } },
		})
		finish("Everlook_host")
		for _, spec in ipairs({
			{ id = "warnings", order = 20, key = "bags" },
			{ id = "experience", order = 10, key = "experience" },
		}) do
			registry.extend("host", {
				id = spec.id, addon = "Everlook_" .. spec.id, order = spec.order,
				options = { [spec.key] = { name = spec.key, default = false } },
				sections = { { name = "Activity", keys = { spec.key }, before = "repair" } },
			})
		end
		local activity = registry.sections(registry.modules[1])[1]
		check("an extension can place its rows before one of the host's", table.concat(activity.keys, ",") == "experience,bags,repair")
	end
	do
		local registry, env, finish, fire = load_registry()
		local handled, errors = {}, {}
		env.geterrorhandler = function() return function(message) errors[#errors + 1] = message end end
		env.unknown_events = { NOT_IN_THIS_CLIENT = true }
		plain(registry, "breaks", "map", 10, { events = { "PING", "NOT_IN_THIS_CLIENT" }, on_event = function() error("boom") end })
		plain(registry, "steady", "map", 20, { events = { "PING" }, on_event = function(event) handled[#handled + 1] = event end })
		finish("Everlook_breaks")
		finish("Everlook_steady")
		local function listening()
			for _, frame in ipairs(env.frames) do if frame.events.PING then return true end end
			return false
		end
		check("a disabled module has no events registered", listening() == false)
		fire("PING")
		check("a disabled module is not told about an event", #handled == 0 and #errors == 0)
		registry.set("breaks", "enabled", true)
		registry.set("steady", "enabled", true)
		check("a module that names an event the client lacks still loads, and the event is noted", registry.loaded("breaks") and registry.unsupported_events.NOT_IN_THIS_CLIENT == true)
		fire("PING")
		check("a listener that errors does not stop the next one", #handled == 1 and #errors == 1 and tostring(errors[1]):find("boom", 1, true) ~= nil)
		check("the error is counted for the module that raised it", registry.listener_failures.breaks == 1 and registry.listener_failures.steady == nil)
		registry.set("breaks", "enabled", false)
		registry.set("steady", "enabled", false)
		check("turning every owner off stops listening for the event", listening() == false)
	end

	do
		local registry, env, finish, fire = load_registry()
		local after = 0
		plain(registry, "waits", "map", 10, { events = { "PLAYER_REGEN_ENABLED" }, on_event = function() end, out_of_combat = true, apply = function() after = after + 1 end })
		finish("Everlook_waits")
		local before = after
		fire("PLAYER_REGEN_ENABLED")
		check("the registry keeps listening for the end of combat while no module wants the event", after == before + 1)
	end

	do
		local registry, env, finish = load_registry()
		env.EverlookDB.qol = { tidy = { enabled = true, amount = 3, size = 2, mode = "gone" } }
		plain(registry, "tidy", "map", 10, {
			options = {
				amount = { name = "Amount", default = 3, min = 1, max = 5 },
				size = { name = "Size", default = 1, min = 1, max = 5 },
				mode = { name = "Mode", default = "a", choices = { { "a", "A" }, { "b", "B" } } },
			},
		})
		finish("Everlook_tidy")
		local stored = env.EverlookDB.qol.tidy
		check("a value equal to its default is not kept", stored.amount == nil)
		check("a value the player changed is kept", stored.enabled == true and stored.size == 2)
		check("a value no longer on the list is dropped", stored.mode == nil and registry.get("tidy", "mode") == "a")
		registry.set("tidy", "size", 1)
		check("setting an option back to its default stores nothing", stored.size == nil and registry.get("tidy", "size") == 1)
	end

	do
		local registry, env, finish = load_registry()
		plain(registry, "moved", "map", 10, { options = { limit = { name = "Limit", default = 5, min = 1, max = 9 } } })
		finish("Everlook_moved")
		check("an untouched option reads the default and stores nothing", registry.get("moved", "limit") == 5 and env.EverlookDB.qol.moved.limit == nil)
		local db = env.EverlookDB
		local later, later_env, later_finish = load_registry()
		later_env.EverlookDB = db
		plain(later, "moved", "map", 10, { options = { limit = { name = "Limit", default = 7, min = 1, max = 9 } } })
		later_finish("Everlook_moved")
		check("a default that changes in code reaches a player who never set it", later.get("moved", "limit") == 7)
	end

end
