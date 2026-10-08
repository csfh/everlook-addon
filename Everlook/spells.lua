local _, Everlook = ...

Everlook.spells = {}

local function public(value)
	if Everlook.world.usable(value) then
		return value
	end
end

local function spell_text(reader, spellId)
	if type(reader) ~= "function" then
		return nil
	end
	local ok, value = pcall(reader, spellId)
	if not ok then
		return nil
	end
	value = public(value)
	if type(value) == "string" and value ~= "" then
		return value
	end
end

local function cooldown_ms(spellId)
	local reader = GetSpellBaseCooldown
	if type(reader) ~= "function" and C_Spell and type(C_Spell.GetSpellBaseCooldown) == "function" then
		reader = C_Spell.GetSpellBaseCooldown
	end
	if type(reader) ~= "function" then
		return nil
	end
	local ok, cooldown = pcall(reader, spellId)
	if not ok then
		return nil
	end
	cooldown = public(cooldown)
	if type(cooldown) ~= "number" or cooldown <= 0 or cooldown ~= math.floor(cooldown) then
		return nil
	end
	return cooldown
end

local function spell_power(spellId)
	local reader = C_Spell and C_Spell.GetSpellPowerCost or GetSpellPowerCost
	if type(reader) ~= "function" then
		return nil, nil
	end
	local ok, costs = pcall(reader, spellId)
	if not ok or type(costs) ~= "table" then
		return nil, nil
	end
	local list = costs
	if costs.cost ~= nil or costs.type ~= nil then
		list = { costs }
	end
	for i = 1, #list do
		local cost = list[i]
		if type(cost) == "table" then
			local amount = public(cost.cost)
			if amount == nil then
				amount = public(cost.minCost)
			end
			local kind = public(cost.type)
			if type(amount) == "number" and amount > 0 and amount == math.floor(amount) then
				if type(kind) ~= "number" or kind < 0 or kind ~= math.floor(kind) then
					kind = nil
				end
				return kind, amount
			end
		end
	end
	return nil, nil
end

local function spell_school(spellId)
	local reader = GetSpellSchool
	if type(reader) ~= "function" and C_Spell and type(C_Spell.GetSpellSchool) == "function" then
		reader = C_Spell.GetSpellSchool
	end
	if type(reader) ~= "function" then
		return nil
	end
	local ok, school = pcall(reader, spellId)
	if not ok then
		return nil
	end
	school = public(school)
	if type(school) ~= "number" or school <= 0 or school ~= math.floor(school) then
		return nil
	end
	return school
end

local function spell_fields(spellId)
	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(spellId)
		if type(info) == "table" then
			return public(info.name), public(info.castTime), public(info.iconID), public(info.maxRange), public(info.minRange)
		end
	end
	if C_Spell and C_Spell.GetSpellName then
		return public(C_Spell.GetSpellName(spellId))
	end
end

local requested = {}

-- Name and description settle the spell once a rank is known, or a load
-- retry has finished. Repeat casts only add npc counts.
local recorded = {}

-- Every successful npc cast used to allocate a row. The counter is the only
-- change, so one scratch row is stored again and again.
local npc_cast = { casts = 1 }

local function note_cast(npcId, spellId)
	npc_cast.npcId = npcId
	npc_cast.spellId = spellId
	Everlook.world.count("npcSpells", npc_cast)
end

local function request_text(spellId)
	if requested[spellId] then
		return
	end
	requested[spellId] = true
	if C_Spell and C_Spell.RequestLoadSpellData then
		C_Spell.RequestLoadSpellData(spellId)
	end
end

local function spell_rank(spellId, hinted)
	hinted = public(hinted)
	if type(hinted) == "string" and hinted ~= "" then
		return hinted
	end
	local subtext = C_Spell and C_Spell.GetSpellSubtext or GetSpellSubtext
	local rank = spell_text(subtext, spellId)
	if rank then
		return rank
	end
	if GetSpellInfo then
		local ok, _, sub = pcall(GetSpellInfo, spellId)
		if ok then
			sub = public(sub)
			if type(sub) == "string" and sub ~= "" then
				return sub
			end
		end
	end
end

function Everlook.spells.record(unit, spellId, extra)
	spellId = public(spellId)
	if type(spellId) ~= "number" then
		return
	end
	local npcId
	-- The player is not a creature. Combat casts must not read that guid.
	if unit and unit ~= "player" and UnitGUID then
		npcId = Everlook.npcs.creature_id(UnitGUID(unit))
	end
	-- Load events call record with no unit. Those must still refresh the row.
	if unit and recorded[spellId] and extra == nil then
		if npcId then
			note_cast(npcId, spellId)
		end
		return
	end
	local hinted = extra
	local waiting = requested[spellId]
	extra = extra or {}
	local name, castTime, icon, rangeMax, rangeMin = spell_fields(spellId)
	local row = { id = spellId }
	if type(name) == "string" and name ~= "" then
		row.name = name
	end
	if type(castTime) == "number" then
		row.castTimeMs = castTime
	end
	if type(icon) == "number" and icon > 0 then
		row.icon = icon
	end
	if type(rangeMax) == "number" then
		row.rangeMax = rangeMax
	end
	if type(rangeMin) == "number" and rangeMin > 0 and rangeMin == math.floor(rangeMin) then
		row.rangeMin = rangeMin
	end
	local describe = C_Spell and C_Spell.GetSpellDescription or GetSpellDescription
	local rank = spell_rank(spellId, extra.subName)
	local description = spell_text(describe, spellId)
	if rank then
		row.rank = rank
	else
		request_text(spellId)
	end
	if description then
		row.description = description
	else
		request_text(spellId)
	end
	local cooldown = cooldown_ms(spellId)
	if cooldown then
		row.cooldownMs = cooldown
	end
	local powerType, powerCost = spell_power(spellId)
	if powerCost then
		row.powerCost = powerCost
		if type(powerType) == "number" then
			row.powerType = powerType
		end
	end
	local school = spell_school(spellId)
	if school then
		row.school = school
	end
	if row.name then
		Everlook.world.store("spells", row)
	end
	if row.name and row.description and not recorded[spellId] then
		if row.rank or (unit == nil and hinted == nil and waiting) then
			recorded[spellId] = true
		end
	end
	if npcId then
		note_cast(npcId, spellId)
	end
end

function Everlook.spells.scan_book()
	if not C_SpellBook or not C_SpellBook.GetNumSpellBookSkillLines or not C_SpellBook.GetSpellBookSkillLineInfo or not C_SpellBook.GetSpellBookItemInfo then
		return
	end
	local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
	local lines = public(C_SpellBook.GetNumSpellBookSkillLines())
	if type(lines) ~= "number" then
		return
	end
	for line = 1, lines do
		local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
		if type(info) == "table" then
			local offset = public(info.itemIndexOffset) or 0
			local count = public(info.numSpellBookItems) or 0
			if type(offset) == "number" and type(count) == "number" then
				for slot = offset + 1, offset + count do
					local item = C_SpellBook.GetSpellBookItemInfo(slot, bank)
					if type(item) == "table" then
						local spellId = public(item.spellID)
						if type(spellId) == "number" and spellId > 0 then
							Everlook.spells.record(nil, spellId, { subName = public(item.subName) })
						end
					end
				end
			end
		end
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:RegisterEvent("SPELL_TEXT_UPDATE")
frame:RegisterEvent("SPELL_DATA_LOAD_RESULT")
frame:SetScript("OnEvent", function(_, event, first, second, third)
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		Everlook.spells.record(first, third)
		return
	end
	local spellId = public(first)
	if type(spellId) ~= "number" then
		return
	end
	if event == "SPELL_DATA_LOAD_RESULT" and public(second) ~= true then
		return
	end
	Everlook.spells.record(nil, spellId)
end)
