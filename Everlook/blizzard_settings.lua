local _, Everlook = ...

-- Makes sure one of the game's own settings has the value a module needs, and puts it back
-- when the module is turned off. The settings it knows are named like this:
--   action_bar_2 to action_bar_8   the Action Bar checkboxes under Gameplay, Action Bars
-- It makes the calls the game's own settings page makes, and reads and writes nothing until a
-- few seconds after the character has entered the world, because the game says its values are
-- wrong until the server has sent them, and a loading screen can be long.
-- What it changed is kept per character in EverlookDB.qol.blizzard_settings.changed, and only
-- that is put back, and only while the setting still has the value this gave it.
local settings = {}
local SETTLE = 5
local TOGGLE_COUNT = 7
local entered_at
local waiting, timer_set = {}, false

local function toggle_of(key)
	local number = type(key) == "string" and tonumber(key:match("^action_bar_(%d)$"))
	if number and number >= 2 and number <= 8 then return number - 1 end
end

local function character()
	local guid = type(UnitGUID) == "function" and UnitGUID("player") or nil
	if type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then return nil end
	return guid
end

local function changed(guid)
	if type(EverlookDB) ~= "table" then return nil end
	EverlookDB.qol = EverlookDB.qol or {}
	local qol = EverlookDB.qol
	qol.blizzard_settings = qol.blizzard_settings or {}
	local store = qol.blizzard_settings
	store.changed = store.changed or {}
	store.changed[guid] = store.changed[guid] or {}
	return store.changed[guid]
end

local function settled()
	return entered_at ~= nil and type(GetTime) == "function" and GetTime() - entered_at >= SETTLE
end

-- One timer serves every wait, and looks again when it fires if the clock has not run long enough.
local function schedule()
	if timer_set or #waiting == 0 or not entered_at or type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then return end
	timer_set = true
	C_Timer.After(SETTLE, function()
		timer_set = false
		if not settled() then schedule(); return end
		local queue = waiting
		waiting = {}
		for _, queued in ipairs(queue) do queued() end
	end)
end

-- Runs the function once the game's settings can be trusted, at once when they already can.
function settings.when_settled(callback)
	if settled() then callback(); return end
	waiting[#waiting + 1] = callback
	schedule()
end

-- The clock starts when the character first enters the world, which comes after the loading
-- screen and not before it.
local frame = type(CreateFrame) == "function" and CreateFrame("Frame") or nil
if frame then
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:SetScript("OnEvent", function()
		if entered_at then return end
		entered_at = type(GetTime) == "function" and GetTime() or nil
		schedule()
	end)
end

-- The toggles as the game gives them, or why not.
local function read()
	if type(GetActionBarToggles) ~= "function" or type(SetActionBarToggles) ~= "function" or type(GetTime) ~= "function" then
		return nil, "unavailable"
	end
	if not settled() then return nil, "waiting" end
	if type(InCombatLockdown) ~= "function" or InCombatLockdown() then return nil, "combat" end
	return { GetActionBarToggles() }
end

-- True when the setting has the wanted value, changed or already so. Otherwise false and why:
-- unknown, invalid, unknown character, unavailable, waiting, combat or unreadable. The
-- reasons waiting and combat are worth trying again, the others are not.
function settings.ensure(key, wanted)
	local index = toggle_of(key)
	if not index then return false, "unknown" end
	if type(wanted) ~= "boolean" then return false, "invalid" end
	local guid = character()
	local record = guid and changed(guid)
	if not record then return false, "unknown character" end
	local values, why = read()
	if not values then return false, why end
	if type(values[index]) ~= "boolean" then return false, "unreadable" end
	if values[index] == wanted then return true end
	-- Written first, so a change that fails halfway can still be put back.
	record[key] = { previous = values[index], set = wanted }
	values[index] = wanted
	SetActionBarToggles(unpack(values, 1, TOGGLE_COUNT))
	return true
end

-- Puts a setting back to what it was before ensure changed it. True when there is nothing
-- left to put back, false and why when it could not be read yet.
function settings.release(key)
	local index = toggle_of(key)
	if not index then return false, "unknown" end
	local guid = character()
	local record = guid and changed(guid)
	local remembered = record and record[key]
	if not remembered then return true end
	local values, why = read()
	if not values then return false, why end
	if type(values[index]) ~= "boolean" then return false, "unreadable" end
	record[key] = nil
	if values[index] == remembered.set then
		values[index] = remembered.previous
		SetActionBarToggles(unpack(values, 1, TOGGLE_COUNT))
	end
	return true
end

Everlook.blizzard_settings = settings
