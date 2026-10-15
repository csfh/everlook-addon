-- The shared secret-value helpers and the out-of-combat queue.
return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)
	local function load(extra)
		local Everlook = {}
		local env
		env = setmetatable({
			EventUtil = { ContinueOnAddOnLoaded = function() end, ContinueOnPlayerLogin = function() end },
			CreateFrame = function()
				local frame = { events = {} }
				function frame:RegisterEvent(event) self.events[event] = true end
				function frame:SetScript(_, callback) self.on_event = callback end
				env.created[#env.created + 1] = frame
				return frame
			end,
		}, { __index = _G })
		env._G = env
		env.created = {}
		for key, value in pairs(extra or {}) do env[key] = value end
		for _, file in ipairs({ "world", "combat" }) do
			local chunk = assert(loadfile(source(file)))
			setfenv(chunk, env)
			chunk("Everlook", Everlook)
		end
		return Everlook, env
	end

	do
		local addon = load({ issecretvalue = function(value) return value == "hidden" end })
		check("a hidden value is secret and gives no public value", addon.secret("hidden") == true and addon.public("hidden") == nil)
		check("a number, a string and a table are public and come back as they are",
			addon.public(7) == 7 and addon.public("name") == "name" and addon.secret(7) == false)
		local list = {}
		check("a table is returned as the same table", addon.public(list) == list)
		check("nil is public and stays nil", addon.public(nil) == nil and addon.secret(nil) == false)
		check("false stays false", addon.public(false) == false)
		local plain = load()
		check("a client with no secret values hides nothing", plain.secret("hidden") == false and plain.public("hidden") == "hidden")
	end

	do
		local fighting = false
		local failures = {}
		local addon, env = load({
			InCombatLockdown = function() return fighting end,
			geterrorhandler = function() return function(message) failures[#failures + 1] = message end end,
		})
		local ran = {}
		addon.after_combat("bar", function() ran[#ran + 1] = "now" end)
		check("out of combat the work runs at once", table.concat(ran, ",") == "now")
		fighting = true
		addon.after_combat("bar", function() ran[#ran + 1] = "first" end)
		addon.after_combat("other", function() ran[#ran + 1] = "other" end)
		addon.after_combat("bar", function() error("boom") end)
		addon.after_combat("bar", function() ran[#ran + 1] = "last" end)
		check("in combat nothing runs yet", #ran == 1)
		local frame = env.created[#env.created]
		check("the queue listens for the end of combat", frame and frame.events.PLAYER_REGEN_ENABLED == true)
		fighting = false
		frame.on_event(frame, "PLAYER_REGEN_ENABLED")
		check("when combat ends each key runs once with its latest work, in the order first asked", table.concat(ran, ",") == "now,last,other")
		frame.on_event(frame, "PLAYER_REGEN_ENABLED")
		check("a second end of combat runs nothing again", #ran == 3)
		fighting = true
		addon.after_combat("broken", function() error("boom") end)
		addon.after_combat("after", function() ran[#ran + 1] = "after" end)
		fighting = false
		frame.on_event(frame, "PLAYER_REGEN_ENABLED")
		check("work that errors is reported and does not stop the next", #failures == 1 and tostring(failures[1]):find("boom", 1, true) and ran[#ran] == "after")
	end
	do
		local fighting, loaded, calls = false, {}, 0
		local addon, env = load({
			InCombatLockdown = function() return fighting end,
			C_AddOns = {
				IsAddOnLoaded = function(name) return loaded[name] == true end,
				LoadAddOn = function(name)
					calls = calls + 1
					if name == "Everlook_Missing" then return false, "MISSING" end
					loaded[name] = true
					return true
				end,
			},
		})
		fighting = true
		local ok, why = addon.load_data_addon("Everlook_Catalog", "an item tooltip")
		check("a data addon is not loaded in combat, and says why", ok == false and why == "in combat" and calls == 0 and addon.data_addons.Everlook_Catalog.state == "waiting")
		check("the reason it was wanted is kept", addon.data_addons.Everlook_Catalog.reason == "an item tooltip")
		fighting = false
		local frame = env.created[#env.created]
		frame.on_event(frame, "PLAYER_REGEN_ENABLED")
		check("it loads when combat ends, once", loaded.Everlook_Catalog == true and calls == 1 and addon.data_addons.Everlook_Catalog.state == "loaded")
		check("asking again for a loaded addon does not load it again", addon.load_data_addon("Everlook_Catalog", "again") == true and calls == 1)
		local missing, failure = addon.load_data_addon("Everlook_Missing", "test")
		check("a load that fails says so and is not retried", missing == false and failure == "MISSING" and addon.data_addons.Everlook_Missing.state == "failed")
		local plain = load({})
		check("a client that cannot load addons on demand is told so", plain.load_data_addon("Everlook_Catalog", "x") == false and plain.data_addons.Everlook_Catalog.state == "unsupported")
	end

	do
		-- The shared catalog: loaded on demand, once, never in combat.
		local calls, in_combat = 0, false
		local addon, env = load({
			InCombatLockdown = function() return in_combat end,
			C_AddOns = { LoadAddOn = function() calls = calls + 1; return false, "MISSING" end },
		})
		check("a pack that cannot load is nil and asked for once", addon.data_pack("tooltip") == nil and addon.data_pack("tooltip") == nil and calls == 1)
		local ready, ready_env
		ready, ready_env = load({ C_AddOns = { LoadAddOn = function() ready_env.Everlook_Data = { loaded = true }; return true end } })
		check("a pack that loads is returned, and then returned again without loading", ready.data_pack("tooltip").loaded == true and ready.data_pack("tooltip").loaded == true)
		local waiting_calls = 0
		local waiting = load({ InCombatLockdown = function() return true end, C_AddOns = { LoadAddOn = function() waiting_calls = waiting_calls + 1; return true end } })
		check("in combat the pack is nil and nothing loads", waiting.data_pack("tooltip") == nil and waiting_calls == 0)
	end

end
