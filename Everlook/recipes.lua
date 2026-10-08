local _, Everlook = ...

Everlook.recipes = {}

local function public(value)
	if Everlook.world.usable(value) then
		return value
	end
end

local function reagents_for(schematic)
	if type(schematic) ~= "table" or type(schematic.reagentSlotSchematics) ~= "table" then
		return nil
	end
	local reagents = {}
	for i = 1, #schematic.reagentSlotSchematics do
		local slot = schematic.reagentSlotSchematics[i]
		local reagent = type(slot) == "table" and slot.reagents and slot.reagents[1] or nil
		local itemId = type(reagent) == "table" and public(reagent.itemID) or nil
		if itemId then
			reagents[#reagents + 1] = {
				itemId = itemId,
				quantity = public(slot.quantityRequired),
			}
			Everlook.items.record(itemId, "recipe")
		end
	end
	if #reagents == 0 then
		return nil
	end
	return reagents
end

-- The list event repeats while a profession window is open. Later updates
-- skip a recipe after its name, reagent slot list, and output or reagent
-- have all been read.
local known = {}
local noted_profession
local noted_profession_name

function Everlook.recipes.scan()
	if not C_TradeSkillUI or not C_TradeSkillUI.GetAllRecipeIDs then
		return
	end
	local profession = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo() or nil
	local childId = type(profession) == "table" and public(profession.professionID) or nil
	local parentId = type(profession) == "table" and public(profession.parentProfessionID) or nil
	local skillLineId = (type(parentId) == "number" and parentId > 0) and parentId or childId
	local childName = type(profession) == "table" and public(profession.professionName) or nil
	local parentName = type(profession) == "table" and public(profession.parentProfessionName) or nil
	local skillName = (type(parentId) == "number" and parentId > 0 and type(parentName) == "string" and parentName ~= "") and parentName or childName
	if skillLineId and skillName and (noted_profession ~= skillLineId or noted_profession_name ~= skillName) then
		noted_profession = skillLineId
		noted_profession_name = skillName
		Everlook.world.store("skillLines", {
			id = skillLineId,
			name = skillName,
			isProfession = true,
		})
	end
	local ids = C_TradeSkillUI.GetAllRecipeIDs()
	if type(ids) ~= "table" then
		return
	end
	for i = 1, #ids do
		local spellId = public(ids[i])
		if type(spellId) == "number" and not known[spellId] then
			local info = C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(spellId) or nil
			local name = type(info) == "table" and public(info.name) or nil
			local schematic = C_TradeSkillUI.GetRecipeSchematic and C_TradeSkillUI.GetRecipeSchematic(spellId, false) or nil
			local crafted = type(schematic) == "table" and public(schematic.outputItemID) or nil
			local reagents = reagents_for(schematic)
			local slots = type(schematic) == "table" and schematic.reagentSlotSchematics
			local slots_ready = type(slots) == "table" and (#slots == 0 or reagents ~= nil)
			-- A recipe read before its profession was known is read again, so the skill line fills in.
			if name and skillLineId and slots_ready and (crafted or reagents) then
				known[spellId] = true
			end
			if name then
				Everlook.world.store("recipes", {
					spellId = spellId,
					name = name,
					skillLineId = skillLineId,
					craftedItemId = crafted,
					craftedMinimum = type(schematic) == "table" and public(schematic.quantityMin) or nil,
					craftedMaximum = type(schematic) == "table" and public(schematic.quantityMax) or nil,
					reagents = reagents,
				})
				Everlook.spells.record(nil, spellId)
				if crafted then
					Everlook.items.record(crafted, "recipe")
				end
			end
		end
	end
end

-- Show and list updates arrive together, then the list keeps firing while the
-- window is open. The first burst scans next tick; later ones share one scan
-- per second so schematics are not read on every event. Without a timer or a
-- usable clock, each event scans immediately.
local SCAN_WINDOW = 1
local scanned_at = 0
local scan_waiting = false

local function run_scan()
	scan_waiting = false
	if type(GetTime) == "function" then
		local now = GetTime()
		if type(now) == "number" then
			scanned_at = now
		end
	end
	Everlook.recipes.scan()
end

local function queue_scan()
	if scan_waiting then
		return
	end
	if type(GetTime) ~= "function" or not C_Timer or type(C_Timer.After) ~= "function" then
		Everlook.recipes.scan()
		return
	end
	local now = GetTime()
	if type(now) ~= "number" then
		Everlook.recipes.scan()
		return
	end
	local delay = 0
	if scanned_at ~= 0 and (now - scanned_at) < SCAN_WINDOW then
		delay = SCAN_WINDOW - (now - scanned_at)
		if delay < 0.05 then
			delay = 0.05
		end
	end
	scan_waiting = true
	C_Timer.After(delay, run_scan)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("TRADE_SKILL_SHOW")
frame:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
frame:SetScript("OnEvent", function()
	queue_scan()
end)
