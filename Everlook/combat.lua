local _, Everlook = ...

-- Work on protected frames has to wait for combat to end. A module hands it over under a key and
-- it runs at once when the player is out of combat, or when combat ends. A second request under
-- the same key replaces the first, so only the latest wish runs once.
local waiting, order = {}, {}
local frame

local function run(key, work)
	local ok, message = pcall(work)
	if not ok then
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
