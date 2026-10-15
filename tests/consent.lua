-- The question that comes before any recording: when it may appear, and what each answer does.
return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)
	local function load(extra)
		local db = {}
		local Everlook = { say = function() end }
		local env = setmetatable({ EverlookDB = db }, { __index = _G })
		env._G = env
		local pending = {}
		env.CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end, UnregisterEvent = function() end } end
		env.C_Timer = { After = function(_, fn) pending[#pending + 1] = fn end }
		env.StaticPopupDialogs = {}
		env.shown = {}
		env.StaticPopup_Show = function(which) env.shown[#env.shown + 1] = which end
		for key, value in pairs(extra or {}) do env[key] = value end
		for _, name in ipairs({ "config", "consent" }) do
			local chunk = assert(loadfile(source(name)))
			setfenv(chunk, env)
			chunk("Everlook", Everlook)
		end
		return Everlook, env, db, pending
	end
	local function run_all(pending)
		local now = pending
		for index = 1, #now do local fn = now[index]; now[index] = nil; fn() end
	end

	local addon, env, db, pending = load()
	addon.consent.start()
	check("a fresh install asks after it settles, not at once", #env.shown == 0 and #pending == 1)
	run_all(pending)
	check("then the question is shown once", #env.shown == 1 and env.shown[1] == "EVERLOOK_COLLECT" and env.StaticPopupDialogs.EVERLOOK_COLLECT.hideOnEscape)
	local dialog = env.StaticPopupDialogs.EVERLOOK_COLLECT
	dialog.OnCancel(nil, nil, "override")
	check("a dialog the game closes is not an answer", db.collect == nil and not addon.config.asked())
	dialog.OnCancel(nil, nil, "clicked")
	check("No, or Escape, is an answer and records nothing", db.collect == false and addon.config.asked() and not addon.config.collecting())
	dialog.OnAccept()
	check("Yes allows recording", db.collect == true and addon.config.collecting())

	for _, answer in ipairs({ true, false }) do
		local answered, _, _, answered_pending = load()
		answered.config.set_collecting(answer)
		answered.consent.start()
		check("an install that answered " .. tostring(answer) .. " is not asked again", #answered_pending == 0)
	end

	for reason, extra in pairs({
		combat = { InCombatLockdown = function() return true end },
		cinematic = { InCinematic = function() return true end },
		dialog = { StaticPopup_ForEachShownDialog = function(fn) fn({ which = "SOMETHING_ELSE" }) end },
	}) do
		local blocked, blocked_env, _, blocked_pending = load(extra)
		check("it is not shown in " .. reason, blocked.consent.blocked() == reason and blocked.consent.show() == false and #blocked_env.shown == 0)
		blocked.consent.start()
		run_all(blocked_pending)
		check("and it waits to try again after " .. reason, #blocked_pending == 1 and #blocked_env.shown == 0)
	end

	local open, open_env = load({ StaticPopup_ForEachShownDialog = function(fn) fn({ which = "EVERLOOK_COLLECT" }) end })
	check("its own open dialog does not block it", open.consent.blocked() == nil and open.consent.show() == true and #open_env.shown == 1)
end
