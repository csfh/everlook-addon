local _, Everlook = ...

Everlook.scan = {}

local function say(text)
	if Everlook.say then
		Everlook.say(text)
	end
end

function Everlook.scan.once()
	say("Scanning bags, equipment, and nearby units.")
	if Everlook.items and Everlook.items.scan_bags then
		Everlook.items.scan_bags()
	end
	if Everlook.items and Everlook.items.scan_equipped then
		Everlook.items.scan_equipped()
	end
	if Everlook.npcs and Everlook.npcs.scan_units then
		Everlook.npcs.scan_units()
	end
	say("Scanning quests and factions.")
	if Everlook.quests and Everlook.quests.scan then
		Everlook.quests.scan()
	end
	if Everlook.factions and Everlook.factions.scan then
		Everlook.factions.scan()
	end
	if Everlook.location and Everlook.location.player then
		Everlook.location.player(true)
	end
end

function Everlook.scan.wide()
	Everlook.scan.once()
	say("Scanning the spellbook.")
	if Everlook.spells and Everlook.spells.scan_book then
		Everlook.spells.scan_book()
	end
	say("Scanning talents.")
	if Everlook.talents and Everlook.talents.scan then
		Everlook.talents.scan()
	end
	say("Checking quest chains.")
	if Everlook.quests and Everlook.quests.scan_wide then
		Everlook.quests.scan_wide()
	end
	Everlook.scan.catalog()
end

local currency_signature
local profession_signature

local function usable(value)
	return not Everlook.world or not Everlook.world.usable or Everlook.world.usable(value)
end

function Everlook.scan.catalog()
	if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize and C_CurrencyInfo.GetCurrencyListInfo then
		local size = C_CurrencyInfo.GetCurrencyListSize()
		if type(size) == "number" then
			local ids, found = {}, {}
			for index = 1, size do
				local info = C_CurrencyInfo.GetCurrencyListInfo(index)
				if type(info) == "table" and not info.isHeader then
					local currency_id = info.currencyID or info.currencyId
					local name = info.name
					if type(currency_id) == "number" and type(name) == "string" and name ~= "" and usable(name) then
						ids[#ids + 1] = currency_id
						found[#found + 1] = { id = currency_id, name = name, icon = info.iconFileID or info.icon }
					end
				end
			end
			table.sort(ids)
			local signature = table.concat(ids, ",")
			if signature ~= currency_signature then
				currency_signature = signature
				for index = 1, #found do
					Everlook.world.store("currencies", found[index])
				end
			end
		end
	end
	if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then
		return
	end
	local first, second, archaeology, fishing, cooking = GetProfessions()
	local indexes = { first, second, archaeology, fishing, cooking }
	local ids, found = {}, {}
	for index = 1, 5 do
		local slot = indexes[index]
		if type(slot) == "number" then
			local name, _, _, _, _, _, skill_line = GetProfessionInfo(slot)
			if type(skill_line) == "number" and type(name) == "string" and name ~= "" and usable(name) then
				ids[#ids + 1] = skill_line
				found[#found + 1] = {
					id = skill_line,
					name = name,
					isProfession = index <= 2,
					isSecondary = index > 2,
				}
			end
		end
	end
	table.sort(ids)
	local signature = table.concat(ids, ",")
	if signature == profession_signature then
		return
	end
	profession_signature = signature
	for index = 1, #found do
		Everlook.world.store("skillLines", found[index])
	end
end

function Everlook.scan.now()
	EverlookDB = EverlookDB or {}
	EverlookDB.eager = nil
	say("Eager scan started.")
	Everlook.scan.wide()
	say("Eager scan finished.")
end
