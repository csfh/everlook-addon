-- Writes the golden world document that the site's tests read, from the addon's own
-- writer. One row per bucket goes through Everlook.world.store, and the packed
-- document() it returns is saved next to the named rows it was made from, so a test
-- on the other side can check that the reader turns it back into the same rows.
--
--   EVERLOOK_WORLD_FIXTURE=<path> lua5.1 tests/run.lua
--
-- The site's copy is web/tests/Fixtures/addon-world.json; `just fixture world` writes it.
return function(load_addon, path)
	local addon = load_addon()
	addon.world.reset()

	local rows = {
		maps = { { id = 37, name = "Elwynn Forest", parentMapId = 12, mapType = 3 } },
		factions = { { id = 72, name = "Stormwind", parentFactionId = 469, side = 1 } },
		spells = { { id = 116, name = "Frostbolt", castTimeMs = 1500, rangeMax = 30, rangeMin = 8, rank = "Rank 1", school = 16 } },
		skillLines = { { id = 164, name = "Blacksmithing", isProfession = true, isSecondary = false } },
		currencies = { { id = 81, name = "Epicurean's Award", icon = 134411 } },
		items = { { id = 2589, name = "Linen Cloth", quality = 1, itemLevel = 5, stackCount = 20, sellPrice = 13, buyPrice = 52, isCraftingReagent = true } },
		objects = { { id = 1731, name = "Copper Vein", objectType = "mining" } },
		npcs = { { id = 448, name = "Hogger", subtitle = "The Gnoll King", minLevel = 11, maxLevel = 11, classification = "elite", factionId = 17, maxHealth = 666, isTrainer = false } },
		quests = { { id = 176, title = "Wanted: Hogger", level = 11, requiredLevel = 9, description = "Hogger has been terrorizing Northshire.", progressText = "Have you found Hogger?", completionText = "Stormwind is safer.", questType = 1, factionSide = 1, mapId = 37, giverId = 448, requires = { 54 } } },
		talents = { { id = 1, name = "Improved Frostbolt", icon = 135846, classId = 8, treeId = 41, treeName = "Frost", nodeId = 90, tier = 1, column = 2, maxRank = 5, rank = 0, spellId = 11070 } },
		recipes = { { spellId = 2018, name = "Rough Copper Bomb", skillLineId = 164, craftedItemId = 4358, craftedMinimum = 1, craftedMaximum = 1, orangeSkill = 30, yellowSkill = 45 } },
		kills = { { npcId = 448, kills = 4, loots = 3, pickpockets = 0, skins = 1, empties = 2 } },
		drops = { { npcId = 448, itemId = 2589, drops = 2, quantity = 3 } },
		vendors = { { npcId = 54, itemId = 2589, price = 52, quantity = 1, stock = 20 } },
		merchantCosts = { { npcId = 54, itemId = 2589, position = 1, costItemId = 0, currencyId = 81, amount = 5 } },
		objectLoot = { { objectId = 1731, itemId = 2770, opens = 6, drops = 6, quantity = 8 } },
		fishingLoot = { { mapId = 37, areaId = 9, itemId = 6291, casts = 12, drops = 7, areaName = "Northshire Valley" } },
		npcSpells = { { npcId = 448, spellId = 116, casts = 3 } },
		npcFactions = { { npcId = 448, factionId = 72, reputation = 250 } },
		taxiNodes = { { id = 2, name = "Stormwind, Elwynn", mapId = 37, x = 612, y = 432, factionSide = 1 } },
		taxiRoutes = { { fromNodeId = 2, toNodeId = 6, cost = 192, durationSeconds = 75, hops = 2 } },
		instanceEntrances = { { instanceId = 43, mapId = 1413, x = 525, y = 375, enters = 3, name = "Wailing Caverns" } },
		offers = { { questId = 176, classId = 1, raceId = 1, band = 2, opens = 6, offered = 4 } },
		mapArt = { { mapId = 1429, artId = 2169, layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256, minScale = 1000, maxScale = 1000, zoomSteps = 0, tiles = { 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22 } } },
		mapOverlays = { { mapId = 1429, offsetX = 231, offsetY = 129, width = 462, height = 210, files = { 31, 32, 33, 34 }, top = 0, hover = 0 } },
		mapRects = { { mapId = 1429, parentId = 1415, left = 400000, right = 420000, top = 500000, bottom = 530000 } },
		questCredits = { { questId = 176, objective = 1, npcId = 448, credits = 4 } },
		instanceEncounters = { { instanceId = 43, encounterId = 585, kills = 2, wipes = 1, name = "Lady Anacondra" } },
	}

	local order = {}
	for bucket in pairs(rows) do
		order[#order + 1] = bucket
	end
	table.sort(order)
	for _, bucket in ipairs(order) do
		for _, row in ipairs(rows[bucket]) do
			addon.world.store(bucket, row)
		end
	end

	local function encode(value, indent)
		local kind = type(value)
		if kind == "string" then
			return '"' .. value:gsub('[%c"\\]', function(c)
				return string.format("\\u%04x", c:byte())
			end) .. '"'
		elseif kind == "number" or kind == "boolean" then
			return tostring(value)
		elseif kind ~= "table" then
			return "null"
		end
		local pad, inner = indent .. "  ", nil
		if #value > 0 or next(value) == nil then
			local items = {}
			for i = 1, #value do
				items[i] = pad .. encode(value[i], pad)
			end
			return #items == 0 and "[]" or "[\n" .. table.concat(items, ",\n") .. "\n" .. indent .. "]"
		end
		local keys = {}
		for key in pairs(value) do
			keys[#keys + 1] = key
		end
		table.sort(keys)
		inner = {}
		for i, key in ipairs(keys) do
			inner[i] = pad .. encode(tostring(key), pad) .. ": " .. encode(value[key], pad)
		end
		return "{\n" .. table.concat(inner, ",\n") .. "\n" .. indent .. "}"
	end

	local out = assert(io.open(path, "w"))
	out:write(encode({ document = addon.world.document(), rows = rows }, ""), "\n")
	out:close()
end
