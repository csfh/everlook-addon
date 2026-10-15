local _, Everlook = ...

-- Work on protected frames has to wait for combat to end. A module hands it over under a key and
-- it runs at once when the player is out of combat, or when combat ends. A second request under
-- the same key replaces the first, so only the latest wish runs once.
local waiting, order = {}, {}
local frame

local function run(key, work)
	local ok, message = pcall(work)
	if not ok then
		if Everlook.errors then Everlook.errors.note(key, message) end
		local handler = geterrorhandler and geterrorhandler()
		if handler then pcall(handler, message) end
	end
end

local function in_combat()
	return InCombatLockdown and InCombatLockdown() == true
end

function Everlook.after_combat(key, work)
	assert(key ~= nil and type(work) == "function", "after_combat needs a key and a function")
	if not in_combat() then
		run(key, work)
		return
	end
	if waiting[key] == nil then order[#order + 1] = key end
	waiting[key] = work
	if not frame and CreateFrame then
		frame = CreateFrame("Frame")
		frame:RegisterEvent("PLAYER_REGEN_ENABLED")
		frame:SetScript("OnEvent", function()
			local keys, works = order, waiting
			order, waiting = {}, {}
			for _, queued in ipairs(keys) do run(queued, works[queued]) end
		end)
	end
end

-- A data addon that is loaded on demand (the catalog, once there is one) is never loaded in combat: loading
-- a large addon takes a frame's worth of time and a script error then can leave the fight with half a table.
-- `reason` says why it is wanted and is kept for the Debug page. In combat the load waits for the end of it.
-- Returns true when the addon is loaded now, otherwise false and why not.
Everlook.data_addons = {}

function Everlook.load_data_addon(name, reason)
	local record = Everlook.data_addons[name] or {}
	Everlook.data_addons[name] = record
	record.reason = reason
	if not (C_AddOns and C_AddOns.LoadAddOn) then
		record.state = "unsupported"
		return false, "this client cannot load addons on demand"
	end
	if C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name) then
		record.state = "loaded"
		return true
	end
	if in_combat() then
		record.state = "waiting"
		Everlook.after_combat("load:" .. name, function() Everlook.load_data_addon(name, reason) end)
		return false, "in combat"
	end
	local ok, failure = C_AddOns.LoadAddOn(name)
	if ok then
		record.state = "loaded"
		return true
	end
	record.state = "failed"
	record.failure = failure
	return false, tostring(failure or "unknown")
end
