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
end
