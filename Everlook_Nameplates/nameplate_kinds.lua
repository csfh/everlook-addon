local addon_name = ...
local Everlook = Everlook

-- The kinds of nameplate the game makes, told apart from what the plate itself says. The game builds a plate the
-- same way for all of them and switches parts on and off, so a kind is read from those switches. Anything a plate
-- does not answer is read from the unit, and anything neither answers leaves the kind unknown, which a strategy
-- treats as hands off.
local plates = Everlook.nameplates or {}
Everlook.nameplates = plates
plates.api = 1

plates.KINDS = {
	"enemy_npc", "enemy_player", "friendly_npc", "friendly_player", "name_only", "simplified", "widgets_only", "forbidden", "personal",
}

local function plain(value)
	return value ~= nil and not (issecretvalue and issecretvalue(value))
end
plates.plain = plain

-- A plate or its frame answering a yes-or-no question, or nil when it cannot say.
local function ask(target, method, ...)
	if type(target) ~= "table" or type(target[method]) ~= "function" then return nil end
	local ok, value = pcall(target[method], target, ...)
	if ok and plain(value) and type(value) == "boolean" then return value end
	return nil
end

-- The unit a plate shows. The game's own accessor comes first; the fields it keeps the token in have differed.
function plates.unit_of(plate)
	if type(plate) ~= "table" then return nil end
	local unit
	if type(plate.GetUnit) == "function" then
		local ok, value = pcall(plate.GetUnit, plate)
		if ok then unit = value end
	end
	unit = unit or plate.unitToken or plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
	if plain(unit) and type(unit) == "string" then return unit end
end

function plates.plate_of(unit)
	local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
	if type(plate) ~= "table" then return nil end
	return plate
end

function plates.kind_of(plate, unit)
	if type(plate) ~= "table" then return nil end
	if ask(plate, "IsForbidden") then return "forbidden" end
	local frame = plate.UnitFrame
	if type(frame) ~= "table" then return nil end
	if ask(frame, "IsForbidden") then return "forbidden" end
	unit = unit or plates.unit_of(plate)
	if unit and UnitIsUnit and plain(UnitIsUnit(unit, "player")) and UnitIsUnit(unit, "player") then return "personal" end
	if frame.widgetsOnlyMode == true then return "widgets_only" end
	if ask(frame, "IsShowOnlyName") then return "name_only" end
	if ask(frame, "IsSimplified") then return "simplified" end
	local player = ask(frame, "IsPlayer")
	if player == nil and unit and UnitIsPlayer then
		local value = UnitIsPlayer(unit)
		if plain(value) then player = value and true or false end
	end
	local friend = ask(frame, "IsFriend")
	if friend == nil and unit and UnitCanAttack then
		local attackable = UnitCanAttack("player", unit)
		if plain(attackable) then friend = not attackable end
	end
	if player == nil or friend == nil then return nil end
	if player then return friend and "friendly_player" or "enemy_player" end
	return friend and "friendly_npc" or "enemy_npc"
end
