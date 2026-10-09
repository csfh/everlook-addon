return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)
	local function load(files)
		local addon = {}
		local frames, callbacks, tickers = {}, {}, {}
		local env = setmetatable({}, { __index = _G })
		env._G = env
		env.tickers = tickers
		function addon.say(text)
			addon.said = text
		end
		env.EventUtil = {
			ContinueOnAddOnLoaded = function(_, callback)
				callbacks[#callbacks + 1] = callback
			end,
			ContinueOnPlayerLogin = function() end,
		}
		env.IsShiftKeyDown = function()
			return false
		end
		env.C_Timer = {
			After = function(_, callback)
				callback()
			end,
			NewTicker = function(_, callback)
				local ticker = {
					callback = callback,
					Cancel = function(self)
						self.cancelled = true
					end,
				}
				tickers[#tickers + 1] = ticker
				return ticker
			end,
		}
		env.CreateFrame = function()
			local frame = { events = {}, scripts = {} }
			function frame:RegisterEvent(event)
				self.events[event] = true
			end
			function frame:SetScript(name, callback)
				self.scripts[name] = callback
			end
			function frame:SetSize() end
			function frame:SetPoint() end
			function frame:Hide()
				self.hidden = true
			end
			function frame:Show()
				self.hidden = false
			end
			function frame:CreateFontString()
				return {
					SetPoint = function() end,
					SetText = function(self, text)
						self.text = text
					end,
					Hide = function(self)
						self.hidden = true
					end,
					Show = function(self)
						self.hidden = false
					end,
				}
			end
			frames[#frames + 1] = frame
			return frame
		end
		for index = 1, #files do
			local chunk = assert(loadfile(source(files[index])))
			setfenv(chunk, env)
			chunk("Everlook", addon)
		end
		for index = 1, #callbacks do
			callbacks[index]()
		end
		local function fire(name, ...)
			for index = 1, #frames do
				local frame = frames[index]
				if frame.events[name] and frame.scripts.OnEvent then
					frame.scripts.OnEvent(frame, name, ...)
				end
			end
		end
		return addon, env, fire
	end

	local world, world_env = load({ "world" })
	world_env.DEFAULT_CHAT_FRAME = {
		AddMessage = function(_, text)
			world.said = text
		end,
	}
	world.world.reset()
	check("a session starts with no new rows", world.world.session_new() == 0)
	world.world.store("npcs", { id = 1, name = "Hogger" })
	check("the first store of a row counts as new", world.world.session_new() == 1)
	world.world.store("npcs", { id = 1, name = "Hogger" })
	check("storing that row again does not count", world.world.session_new() == 1)
	world.world.store("drops", { npcId = 1, itemId = 80, drops = 1 })
	world.world.count("drops", { npcId = 1, itemId = 80, drops = 3 })
	check("a counter on an existing row does not count as new", world.world.session_new() == 2)
	check("a zone change reports rows added since the last report", world.world.report_zone("Elwynn Forest") == true and world.said == "Everlook: 2 new rows in Elwynn Forest.")
	world.said = nil
	check("a quiet zone change says nothing", world.world.report_zone("Westfall") == false and world.said == nil)
	world.world.store("items", { id = 80, name = "Linen" })
	check("the next zone change reports only the new rows", world.world.report_zone("Redridge") == true and world.said == "Everlook: 1 new rows in Redridge.")
	world.world.store("npcs", { id = 10, name = "Hogger" })
	world.world.store("items", { id = 20, name = "Cloth" })
	world.world.store("items", { id = 21, name = "Sword" })
	world.world.store("items", { id = 22, name = "Shield" })
	world.world.store("items", { id = 23, name = "Helm" })
	world.world.store("spells", { id = 133, name = "Fireball" })
	world.world.store("vendors", { npcId = 10, itemId = 20 })
	world.world.store("vendors", { npcId = 10, itemId = 21 })
	world.world.store("vendors", { npcId = 10, itemId = 22 })
	world.world.store("vendors", { npcId = 10, itemId = 23 })
	world.world.store("drops", { npcId = 10, itemId = 20, drops = 4 })
	world.world.store("quests", { id = 176, title = "Wanted: Hogger", giverId = 10 })
	world.world.store("objectLoot", { objectId = 30, itemId = 20 })
	local sales = world.world.lookup("npc", 10)
	check("a creature tooltip keeps at most three related names", #sales == 3)
	local cloth = world.world.lookup("item", 20)
	local cloth_text = table.concat(cloth, "|")
	check("an item tooltip lists a vendor and a local drop count", cloth_text:find("Vendor: Hogger", 1, true) and cloth_text:find("Dropped by Hogger (4)", 1, true) and #cloth <= 3)
	check("an unknown id adds no lookup line", #world.world.lookup("item", 99999) == 0)
	world_env.issecretvalue = function(value)
		return value == 7
	end
	check("a secret id adds no lookup line", #world.world.lookup("item", 7) == 0)
	world_env.issecretvalue = nil
	check("object loot names the contained item", world.world.lookup("object", 30)[1] == "Contains Cloth")

	-- A tooltip rebuilds its lines by walking every related row, so only a
	-- change a line shows may trigger that walk. Moving creatures and repeat
	-- casts change nothing a tooltip says.
	local function walks_for(kind, id)
		local walks = 0
		world_env.pairs = function(value)
			walks = walks + 1
			return pairs(value)
		end
		local lines = world.world.lookup(kind, id)
		world_env.pairs = nil
		return walks, table.concat(lines, "|")
	end
	walks_for("npc", 10)
	world.world.store("npcs", { id = 10, locations = { { mapId = 37, x = 120, y = 340 } } })
	check("a creature seen somewhere new keeps its tooltip lines", (walks_for("npc", 10)) == 0)
	world.world.store("npcSpells", { npcId = 10, spellId = 133, casts = 1 })
	walks_for("npc", 10)
	world.world.count("npcSpells", { npcId = 10, spellId = 133, casts = 1 })
	check("a repeat cast keeps its tooltip lines", (walks_for("npc", 10)) == 0)
	world.world.count("drops", { npcId = 10, itemId = 20, drops = 1 })
	local _, recounted = walks_for("item", 20)
	check("a new drop updates the drop count a tooltip shows", recounted:find("Dropped by Hogger (5)", 1, true) ~= nil)
	world.world.store("npcs", { id = 10, name = "Hogger the Great" })
	local _, renamed = walks_for("item", 20)
	check("a renamed creature updates the tooltips that name it", renamed:find("Vendor: Hogger the Great", 1, true) ~= nil)

	local counted, saved, fire_saved = load({ "world" })
	saved.EverlookDB = {}
	saved.C_EncodingUtil = {
		SerializeCBOR = function()
			return "cbor"
		end,
		EncodeBase64 = function(value)
			return value
		end,
	}
	counted.world.store("npcs", { id = 1, name = "A" })
	counted.world.store("npcs", { id = 2, name = "B" })
	counted.world.flush()
	check("a flush records the row count and payload length", saved.EverlookDB.worldRows == 2 and saved.EverlookDB.worldBytes == #saved.EverlookDB.world)
	counted.world.reset()
	saved.EverlookDB = {}
	counted.world.flush(true)
	check("an empty document flushes as zero rows and zero bytes", saved.EverlookDB.worldRows == 0 and saved.EverlookDB.worldBytes == 0)
	counted.world.store("npcs", { id = 3, name = "C" })
	check("the load message includes the row count", counted.world.load_message():find("1 rows", 1, true) ~= nil)

	-- WoW writes saved variables only when the player logs out or reloads, so
	-- packing and signing the world any earlier only costs frames.
	local playing, played, fire_played = load({ "world" })
	local encodes = 0
	played.EverlookDB = {}
	played.C_EncodingUtil = {
		SerializeCBOR = function()
			encodes = encodes + 1
			return "cbor"
		end,
		EncodeBase64 = function(value)
			return value
		end,
	}
	playing.world.store("npcs", { id = 4, name = "D" })
	playing.world.store("items", { id = 5, name = "E" })
	for index = 1, #played.tickers do
		played.tickers[index].callback()
	end
	fire_played("ZONE_CHANGED_NEW_AREA")
	check("collecting rows during play packs nothing", encodes == 0 and played.EverlookDB.world == nil)
	fire_played("PLAYER_LOGOUT")
	check("logging out packs the world once", encodes == 1 and played.EverlookDB.world == "1r.cbor")

	counted.world.reset()
	saved.EverlookDB = { world = "1r.keep", signature = "signed" }
	check("the signed world is not the row table", counted.world.load_saved() == false and counted.world.row_count() == 0 and saved.EverlookDB.world == "1r.keep" and saved.EverlookDB.signature == "signed")
	fire_saved("PLAYER_LOGOUT")
	check("a signed world without raw rows stays untouched", saved.EverlookDB.raw == nil and saved.EverlookDB.world == "1r.keep" and saved.EverlookDB.signature == "signed")
	counted.world.store("npcs", { id = 8, name = "Hogger", locations = { { mapId = 37, x = 500, y = 250, seen = 4, zone = "Elwynn" } }, sources = { "target", "loot" } })
	counted.world.store("drops", { npcId = 8, itemId = 5, drops = 4 })
	fire_saved("PLAYER_LOGOUT")
	check("logout keeps raw rows beside the signed world", saved.EverlookDB.raw.npcs[8].name == "Hogger" and saved.EverlookDB.raw.npcs[8].locations[1].seen == 4 and saved.EverlookDB.raw.npcs[8].locations[1].zone == "Elwynn" and saved.EverlookDB.raw.npcs[8].sources[1] == "target" and saved.EverlookDB.raw.drops["8:5"].drops == 4 and saved.EverlookDB.world == "1r.cbor")
	counted.world.reset()
	check("the next session continues from the raw rows", counted.world.load_saved() == true and counted.world.row("npcs", 8).name == "Hogger" and counted.world.row("drops", "8:5").drops == 4 and counted.world.session_new() == 0 and counted.world.load_message() == "Loaded. 2 rows.")
	fire_saved("PLAYER_LOGOUT")
	check("logging out before a new sighting keeps the signed world", saved.EverlookDB.world == "1r.cbor" and saved.EverlookDB.signature == "signed" and saved.EverlookDB.raw.npcs[8].name == "Hogger")
	counted.world.store("npcs", { id = 11, name = "Fresh", locations = { { mapId = 1, x = 2, y = 3 } } })
	counted.world.count("drops", { npcId = 8, itemId = 5, drops = 1 })
	check("a later sighting merges into the raw rows", counted.world.row("npcs", 8).name == "Hogger" and counted.world.row("npcs", 11).name == "Fresh" and counted.world.row("drops", "8:5").drops == 5)
	fire_saved("PLAYER_LOGOUT")
	check("the next logout packs the signed world from the raw rows", saved.EverlookDB.world == "1r.cbor" and saved.EverlookDB.raw.npcs[11].name == "Fresh" and saved.EverlookDB.raw.drops["8:5"].drops == 5)

	local survey, survey_env = load({ "world", "location", "sightings", "npcs", "items", "objects", "drops", "taxi", "factions", "scan", "links", "module", "site_links", "collected", "map_pins" })
	survey.world.store("maps", { id = 37, name = "Elwynn Forest" })
	survey.world.store("npcs", { id = 448, name = "Hogger", locations = { { mapId = 37, x = 500, y = 250, role = 1 } } })
	survey.world.store("npcs", { id = 69, name = "Wolf", classification = "normal", locations = { { mapId = 37, x = 100, y = 100 } } })
	survey.world.store("npcs", { id = 70, name = "Rare Wolf", classification = "rare", locations = { { mapId = 37, x = 200, y = 200 } } })
	survey.world.store("objects", { id = 1731, name = "Chest", locations = { { mapId = 37, x = 300, y = 300 } } })
	survey.world.store("quests", { id = 62, title = "Mine", locations = { { mapId = 37, x = 400, y = 400, role = 1 } } })
	local pins = survey.map_pins.for_map(37)
	local function pin_buckets()
		local names = {}
		for index = 1, #pins do
			names[pins[index].bucket] = (names[pins[index].bucket] or 0) + 1
		end
		return names
	end
	local buckets = pin_buckets()
	check("pins show quest givers, objects, and rares on this map", buckets.quests == 1 and buckets.objects == 1 and buckets.npcs == 1)
	check("ordinary creatures are not pinned", buckets.npcs == 1)
	local elsewhere = survey.map_pins.for_map(1)
	check("a giver pin stays off another map", #elsewhere == 0)
	local records = { { text = "Hogger", id = "448" }, { text = "Wolf", id = "69" } }
	local found = survey.collected.filter(records, "hog")
	check("the collected browser filters by text", #found == 1 and found[1].id == "448")
	check("an empty filter keeps every record", #survey.collected.filter(records, "") == 2)
	check("a selected record shows its map location", survey.collected.location_text("npcs", "448") == "Elwynn Forest 50.0, 25.0 giver")
	local chat
	survey_env.ChatFrame_OpenChat = function(text)
		chat = text
	end
	check("shift-click inserts an Everlook address", survey.collected.insert("npcs", "448") == true and chat == "everlook.ing/database/npcs/448")
	check("a joined row inserts nothing", survey.collected.insert("drops", "448:80") == false)

	survey_env.Enum = { FlightPathState = { Current = 0, Reachable = 1 } }
	survey_env.C_Map = { GetBestMapForUnit = function() return 37 end }
	survey_env.TaxiNodeCost = function(slot)
		if slot == 2 then
			return 50
		end
		return 0
	end
	survey_env.C_TaxiMap = {
		GetAllTaxiNodes = function()
			return {
				{ nodeID = 10, name = "Stormwind", position = { x = 0.1, y = 0.2 }, state = 0, slotIndex = 1 },
				{ nodeID = 20, name = "Ironforge", position = { x = 0.3, y = 0.4 }, state = 1, slotIndex = 2 },
			}
		end,
	}
	survey_env.UnitFactionGroup = function()
		return "Alliance"
	end
	survey.taxi.scan()
	local route = survey.world.row("taxiRoutes", "10:20")
	check("a taxi route uses flight master ids", route and route.fromNodeId == 10 and route.toNodeId == 20 and route.cost == 50)
	check("a window slot is not a route", survey.world.row("taxiRoutes", "1:2") == nil)
	survey.taxi.learn_duration("Stormwind", "Ironforge", 42.2)
	check("a unique completed flight records a duration", survey.world.row("taxiRoutes", "10:20").durationSeconds == 42)
	survey.world.store("taxiNodes", { id = 11, name = "Stormwind", mapId = 37, x = 1, y = 1 })
	survey.taxi.learn_duration("Stormwind", "Ironforge", 99)
	check("duplicate flight names do not change the duration", survey.world.row("taxiRoutes", "10:20").durationSeconds == 42)

	survey_env.UnitGUID = function()
		return "Creature-0-0-0-0-448-abc"
	end
	survey_env.GetNumTrainerServices = function()
		return 2
	end
	survey_env.GetTrainerServiceInfo = function(index)
		if index == 1 then
			return "Fireball", "Rank 2", "available", 1
		end
		return "Frostbolt", "", "available", 1
	end
	survey_env.C_TooltipInfo = {
		GetTrainerService = function(index)
			if index == 1 then
				return { type = 1, id = 133 }
			end
			return { type = 1, id = 116 }
		end,
	}
	survey_env.Enum = survey_env.Enum or {}
	survey_env.Enum.TooltipDataType = { Spell = 1 }
	local trainer_stores = 0
	local store_world = survey.world.store
	survey.world.store = function(bucket, row)
		if bucket == "npcs" and row.trainerSpells then
			trainer_stores = trainer_stores + 1
		end
		return store_world(bucket, row)
	end
	check("a trainer window records taught spells", survey.npcs.read_trainer() == true and trainer_stores == 1 and survey.world.row("npcs", 448).trainerSpells[1].spellId == 116 and survey.world.row("npcs", 448).trainerSpells[2].spellId == 133)
	check("the same trainer list does not store again", survey.npcs.read_trainer() == false and trainer_stores == 1)
	survey.world.store = store_world
	survey.world.store("objects", { id = 1731, name = "Chest", locations = { { mapId = 37, x = 310, y = 320 } } })
	survey.world.store("quests", { id = 63, title = "Boars", locations = { { mapId = 37, x = 10, y = 10, role = 4 } } })
	survey.world.store("quests", { id = 64, title = "Stood", locations = { { mapId = 37, x = 11, y = 11, role = 3 } } })
	survey.world.store("vendors", { npcId = 69, itemId = 20, price = 1 })
	survey.world.store("vendors", { npcId = 70, itemId = 20, price = 1 })
	pins = survey.map_pins.for_map(37)
	local tally = { quest = 0, object = 0, rare = 0, vendor = 0, flight = 0, objective = 0, trainer = 0, wolf = 0, rare_vendor = 0 }
	for index = 1, #pins do
		local pin = pins[index]
		tally[pin.kind] = (tally[pin.kind] or 0) + 1
		if pin.label == "objective" then
			tally.objective = tally.objective + 1
		end
		if pin.id == 448 and pin.label == "trainer" then
			tally.trainer = tally.trainer + 1
		end
		if pin.id == 69 and pin.label == "vendor" then
			tally.wolf = tally.wolf + 1
		end
		if pin.id == 70 and pin.kind == "vendor" then
			tally.rare_vendor = tally.rare_vendor + 1
		end
		if pin.id == 64 then
			tally.accepted = 1
		end
	end
	check("a chest keeps a pin for each place", tally.object == 2)
	check("quest objectives are pinned and accepted places are not", tally.objective == 1 and tally.quest == 2 and tally.accepted == nil)
	check("flight masters, trainers, and vendors are pinned", tally.flight == 3 and tally.trainer == 1 and tally.wolf == 1)
	check("a rare who sells goods stays one rare pin", tally.rare == 1 and tally.rare_vendor == 0)

	local currency_stores, skill_stores = 0, 0
	survey.world.store = function(bucket, row)
		if bucket == "currencies" then
			currency_stores = currency_stores + 1
		elseif bucket == "skillLines" then
			skill_stores = skill_stores + 1
		end
		return store_world(bucket, row)
	end
	survey_env.C_CurrencyInfo = {
		GetCurrencyListSize = function()
			return 2
		end,
		GetCurrencyListInfo = function(index)
			if index == 1 then
				return { currencyID = 1, name = "Token", iconFileID = 4 }
			end
			return { currencyID = 2, name = "Badge", iconFileID = 5 }
		end,
	}
	survey_env.GetProfessions = function()
		return 1, nil, nil, 4
	end
	survey_env.GetProfessionInfo = function(index)
		if index == 1 then
			return "Blacksmithing", nil, nil, nil, nil, nil, 164
		end
		return "Fishing", nil, nil, nil, nil, nil, 356
	end
	survey.scan.catalog()
	survey.scan.catalog()
	check("an eager catalog stores currencies and professions once", currency_stores == 2 and skill_stores == 2)
	survey.world.store = store_world

	survey_env.C_Reputation = {
		GetNumFactions = function()
			return 1
		end,
		GetFactionDataByIndex = function()
			return { factionID = 72, name = "Stormwind", parentFactionID = 469, isHeader = false, factionGroup = "Alliance" }
		end,
	}
	survey.factions.scan()
	check("a faction records its side", survey.world.row("factions", 72).side == 1)
	survey_env.C_CreatureInfo = {
		GetFactionInfo = function()
			return { factionID = 72, standing = 3000 }
		end,
	}
	survey.npcs.note_faction(448)
	local creature_faction = survey.world.row("npcFactions", "448:72")
	check("a creature can be tied to a faction without the player's standing", creature_faction and creature_faction.factionId == 72 and creature_faction.reputation == nil)

	survey_env.IsFishingLoot = function()
		return false
	end
	survey_env.GetNumLootItems = function()
		return 1
	end
	survey_env.GetLootSlotType = function()
		return 1
	end
	survey_env.GetLootSlotLink = function()
		return "|Hitem:80|h[Hide]|h"
	end
	survey_env.GetLootSlotInfo = function()
		return nil, "Hide", 1
	end
	survey_env.GetLootSourceInfo = function()
		return "Creature-0-0-0-0-448-abc", 1
	end
	survey_env.C_Item = {}
	survey.world.reset()
	survey.drops.scan()
	local plain_kill = survey.world.row("kills", 448)
	check("a normal corpse leaves skin and pickpocket counts at zero", plain_kill and plain_kill.skins == 0 and plain_kill.pickpockets == 0)
	survey_env.GetLootMethod = function()
		return "freeforall"
	end
	survey.drops.scan()
	check("the party loot rule does not count as skinning", survey.world.row("kills", 448).skins == 0 and survey.world.row("kills", 448).pickpockets == 0)

	survey.world.reset()
	survey_env.C_GossipInfo = {
		GetText = function()
			return "Hello"
		end,
		GetOptions = function()
			return { { name = "Browse" }, { name = "Goods" } }
		end,
	}
	check("gossip text is stored", survey.npcs.gossip() == true and survey.world.row("npcs", 448).gossip == "Hello\nBrowse\nGoods")
	check("the same gossip window does not store again", survey.npcs.gossip() == false)
	survey_env.issecretvalue = function(value)
		return value == "secret"
	end
	survey_env.C_GossipInfo.GetText = function()
		return "secret"
	end
	survey_env.UnitGUID = function()
		return "Creature-0-0-0-0-449-abc"
	end
	check("a secret greeting is not stored", survey.npcs.gossip() == false and survey.world.row("npcs", 449) == nil)
	survey_env.issecretvalue = nil

	survey.npcs.vignette("missing")
	check("a missing vignette API stores nothing", survey.world.row("npcs", 500) == nil)
	survey_env.C_VignetteInfo = {
		GetVignetteInfo = function()
			return { objectGUID = "Creature-0-0-0-0-500-abc", name = "Rare" }
		end,
	}
	check("a vignette sighting stores the creature", survey.npcs.vignette("guid") == true and survey.world.row("npcs", 500).name == "Rare")
	survey_env.C_Map = {
		GetBestMapForUnit = function()
			return 37
		end,
		GetPlayerMapPosition = function()
			return { x = 0.5, y = 0.5 }
		end,
	}
	survey_env.C_VignetteInfo.GetVignettePosition = function()
		return { x = 0.2, y = 0.3 }
	end
	check("a vignette pin uses the vignette point", survey.npcs.vignette("guid") == true and survey.world.row("npcs", 500).locations[1].x == 200 and survey.world.row("npcs", 500).locations[1].y == 300 and survey.world.row("npcs", 500).locations[1].mapId == 37)
	survey_env.C_VignetteInfo.GetVignettePosition = function()
		return {
			GetXY = function()
				return 0.4, 0.6
			end,
		}
	end
	check("a vignette point can come from GetXY", survey.npcs.vignette("guid") == true and survey.world.row("npcs", 500).locations[2].x == 400 and survey.world.row("npcs", 500).locations[2].y == 600)

	local area_before = survey.world.row("maps", 12)
	survey.location.note_area(12, 100, 200, "Nowhere")
	check("a subzone without an area API is not stored", survey.world.row("maps", 12) == area_before)
	survey_env.CreateVector2D = function(x, y)
		return { x = x, y = y }
	end
	survey_env.C_MapExplorationInfo = {
		GetExploredAreaIDsAtPosition = function(_, position)
			if type(position) ~= "table" or position.x ~= 0.1 or position.y ~= 0.2 then
				return nil
			end
			return { 87 }
		end,
	}
	survey_env.C_Map.GetAreaInfo = function()
		return "Northshire Valley"
	end
	survey.location.note_area(12, 100, 200, "Nowhere")
	check("a stable area id stores the subzone", survey.world.row("maps", 12).areas[1].id == 87 and survey.world.row("maps", 12).areas[1].name == "Northshire Valley")

	survey_env.C_GameObject = {
		GetGameObjectType = function()
			return "Mailbox"
		end,
	}
	survey.objects.record("GameObject-0-0-0-0-1731-abc", "mouseover", "Post")
	check("an object uses the game classification when it exists", survey.world.row("objects", 1731).objectType == "Mailbox")

	local addon, play, fire = load({
		"world", "links", "module", "useful_tooltips", "chat_tweaks", "coordinates", "quest_levels", "cinematic_skip", "camera", "mail", "gossip_continue", "map_pins",
	})
	play.TooltipDataProcessor = {
		AddTooltipPostCall = function(kind, callback)
			play.tooltip_calls = play.tooltip_calls or {}
			play.tooltip_calls[kind] = callback
		end,
	}
	play.Enum = { TooltipDataType = { Item = 0, Unit = 2 }, GossipOption = { Vendor = 1, Gossip = 2, Taxi = 3, Trainer = 4, Binder = 5 } }
	-- Tooltips install on enable, after the processor exists. Reload the module's apply by setting enabled.
	addon.world.store("npcs", { id = 10, name = "Hogger" })
	addon.world.store("items", { id = 20, name = "Cloth" })
	addon.world.store("vendors", { npcId = 10, itemId = 20 })
	addon.module.set("useful_tooltips", "enabled", true)
	local lines = {}
	local tooltip = {
		AddLine = function(_, text)
			lines[#lines + 1] = text
		end,
		HasScript = function()
			return true
		end,
		HookScript = function() end,
	}
	play.tooltip_calls[0](tooltip, { id = 20 })
	local joined = table.concat(lines, "|")
	check("the item tooltip shows the local vendor", joined:find("Vendor: Hogger", 1, true) ~= nil)
	lines = {}
	play.issecretvalue = function(value)
		return value == "secret"
	end
	play.tooltip_calls[0](tooltip, { id = "secret" })
	check("a secret tooltip id adds no lookup line", #lines == 0)
	play.issecretvalue = nil

	check("coordinates format a map position", addon.coordinates.format(0.5, 0.25) == "50.0, 25.0")
	check("coordinates stay blank without a position", addon.coordinates.format(nil, 0.2) == "")
	play.C_Map = {}
	check("coordinates stay blank without a map position", addon.coordinates.player_text() == "")
	play.C_Map = {
		GetBestMapForUnit = function() return 37 end,
		GetPlayerMapPosition = function()
			return { x = 0.5, y = 0.25 }
		end,
	}
	check("coordinates read a table position", addon.coordinates.player_text() == "50.0, 25.0")
	play.C_Map.GetPlayerMapPosition = function()
		return { GetXY = function() return 0.2, 0.4 end }
	end
	check("coordinates read a vector position", addon.coordinates.player_text() == "20.0, 40.0")
	play.C_Map = nil
	play.Minimap = {}
	addon.module.set("coordinates", "enabled", true)
	addon.module.set("coordinates", "enabled", false)
	check("turning coordinates off stops the ticker", play.tickers[#play.tickers].cancelled)

	local title = "Wolves"
	play.C_QuestLog = {
		GetTitleForQuestID = function()
			return title
		end,
		GetQuestDifficultyLevel = function()
			return 8
		end,
	}
	addon.module.set("quest_levels", "enabled", true)
	check("a quest title gains its level", play.C_QuestLog.GetTitleForQuestID(1) == "[8] Wolves")
	title = "secret"
	play.issecretvalue = function(value)
		return value == "secret"
	end
	check("a secret quest title is forwarded unchanged", play.C_QuestLog.GetTitleForQuestID(1) == "secret")
	play.issecretvalue = nil
	title = "Wolves"
	addon.module.set("quest_levels", "enabled", false)
	check("turning quest levels off restores the title", play.C_QuestLog.GetTitleForQuestID(1) == "Wolves")

	local cancels = 0
	play.CinematicFrame_CancelCinematic = function()
		cancels = cancels + 1
	end
	addon.module.set("cinematic_skip", "enabled", true)
	fire("CINEMATIC_START")
	check("a cinematic is cancelled", cancels == 1)
	play.IsShiftKeyDown = function()
		return true
	end
	fire("PLAY_MOVIE")
	check("Shift leaves the cinematic playing", cancels == 1)
	play.IsShiftKeyDown = function()
		return false
	end
	play.CinematicFrame_CancelCinematic = nil
	play.MovieFrame_StopMovie = nil
	play.CancelCinematic = nil
	fire("CINEMATIC_START")
	check("a missing cinematic cancel does nothing", cancels == 1)

	local distance = "1.0"
	play.GetCVar = function()
		return distance
	end
	play.SetCVar = function(_, value)
		distance = value
	end
	addon.module.set("camera", "enabled", true)
	check("camera distance uses the saved setting", distance == "2.6")
	addon.module.set("camera", "distance", 3)
	addon.module.set("camera", "enabled", false)
	check("turning the camera off restores the previous distance", distance == "1.0")

	local taken = {}
	local mails = {
		{ money = 5, cod = 0, items = 1 },
		{ money = 2, cod = 0, items = 0 },
	}
	local function compact()
		local kept = {}
		for index = 1, #mails do
			if not mails[index].taken then
				kept[#kept + 1] = mails[index]
			end
		end
		mails = kept
	end
	play.GetInboxNumItems = function()
		compact()
		return #mails
	end
	play.GetInboxHeaderInfo = function(index)
		local mail = mails[index]
		if not mail then
			return
		end
		return nil, nil, nil, nil, mail.money, mail.cod, 1, mail.items
	end
	play.TakeInboxMoney = function(index)
		taken[#taken + 1] = mails[index].money
		mails[index].money = 0
		if mails[index].items <= 0 then
			mails[index].taken = true
		end
	end
	play.TakeInboxItem = function(index)
		taken[#taken + 1] = "item"
		mails[index].items = mails[index].items - 1
		if mails[index].money <= 0 and mails[index].items <= 0 then
			mails[index].taken = true
		end
	end
	addon.module.set("mail", "enabled", true)
	fire("MAIL_SHOW")
	play.tickers[#play.tickers].callback()
	check("one tick takes the money and leaves the attached item", taken[1] == 5 and #taken == 1)
	play.tickers[#play.tickers].callback()
	check("the next tick takes the item that was still attached", taken[2] == "item" and #taken == 2)
	play.tickers[#play.tickers].callback()
	check("plain mail is taken again after the inbox compacts", taken[3] == 2 and #taken == 3)
	mails = { { money = 9, cod = 4, items = 0 }, { money = 3, cod = 0, items = 0 } }
	taken = {}
	play.tickers[#play.tickers].callback()
	check("cash on delivery stays in the mailbox", taken[1] == 3 and #taken == 1)
	play.IsShiftKeyDown = function()
		return true
	end
	local before_shift = #taken
	play.tickers[#play.tickers].callback()
	check("Shift stops taking mail", #taken == before_shift and play.tickers[#play.tickers].cancelled)
	play.IsShiftKeyDown = function()
		return false
	end
	taken = {}
	fire("MAIL_SHOW")
	fire("MAIL_CLOSED")
	play.tickers[#play.tickers].callback()
	check("closing the mailbox stops taking mail", #taken == 0)
	mails = { { money = 0, cod = 0, items = 2 } }
	taken = {}
	local slots = {}
	play.TakeInboxItem = function(index, slot)
		slots[#slots + 1] = slot
		mails[index].items = mails[index].items - 1
		if mails[index].items <= 0 then
			mails[index].taken = true
		end
	end
	fire("MAIL_SHOW")
	play.tickers[#play.tickers].callback()
	check("one attachment is taken per tick", #slots == 1 and slots[1] == 1 and mails[1].items == 1)
	play.tickers[#play.tickers].callback()
	check("the next tick takes the attachment that slid forward", #slots == 2 and slots[2] == 1)
	mails = { { money = 4, cod = 0, items = 0 } }
	taken = {}
	local pending = true
	local secret_pending = {}
	play.C_Mail = {
		IsCommandPending = function()
			return pending
		end,
	}
	fire("MAIL_SHOW")
	play.tickers[#play.tickers].callback()
	check("a pending mail command waits", #taken == 0 and not play.tickers[#play.tickers].cancelled)
	pending = false
	play.tickers[#play.tickers].callback()
	check("the money is taken once the command finishes", taken[1] == 4 and #taken == 1)
	mails = { { money = 7, cod = 0, items = 0 } }
	taken = {}
	play.issecretvalue = function(value)
		return rawequal(value, secret_pending)
	end
	play.C_Mail.IsCommandPending = function()
		return secret_pending
	end
	fire("MAIL_SHOW")
	play.tickers[#play.tickers].callback()
	check("a secret mail command state waits", #taken == 0 and not play.tickers[#play.tickers].cancelled)
	play.issecretvalue = nil
	play.C_Mail = nil

	local selected
	play.C_GossipInfo = {
		GetOptions = function()
			return play.gossip_options
		end,
		GetActiveQuests = function()
			return {}
		end,
		GetAvailableQuests = function()
			return {}
		end,
		SelectOption = function(option_id)
			selected = option_id
		end,
	}
	play.gossip_options = { { gossipOptionID = 9, gossipOptionType = 2 } }
	addon.module.set("gossip_continue", "enabled", true)
	fire("GOSSIP_SHOW")
	check("one ordinary gossip option is selected", selected == 9)
	selected = nil
	play.gossip_options = { { gossipOptionID = 3, gossipOptionType = 1 } }
	fire("GOSSIP_SHOW")
	check("a vendor option is not selected", selected == nil)
	play.gossip_options = { { gossipOptionID = 1, gossipOptionType = 2 }, { gossipOptionID = 2, gossipOptionType = 2 } }
	fire("GOSSIP_SHOW")
	check("two gossip options select nothing", selected == nil)
	play.IsShiftKeyDown = function()
		return true
	end
	play.gossip_options = { { gossipOptionID = 9, gossipOptionType = 2 } }
	fire("GOSSIP_SHOW")
	check("Shift selects no gossip option", selected == nil)

	play.GetGameTime = function()
		return 9, 5
	end
	local filters = {}
	play.ChatFrame_AddMessageEventFilter = function(event, callback)
		filters[event] = callback
	end
	play.ChatFrame_RemoveMessageEventFilter = function(event)
		filters[event] = nil
	end
	play.CHAT_FRAMES = {}
	addon.module.set("chat_tweaks", "enabled", true)
	addon.module.set("chat_tweaks", "timestamps", true)
	check("a plain chat line gains a timestamp", addon.chat_tweaks.stamp("Hello") == "09:05 Hello")
	-- Same rule as ChatFrameUtil.ProcessMessageEventFilters: a truthy first
	-- return drops the line, and a new message replaces the arguments that follow.
	local function shown_line(filter, message, author, extra)
		local discard, new_message, new_author, new_extra = filter(nil, "CHAT_MSG_SAY", message, author, extra)
		if discard then
			return nil
		end
		if new_message then
			return new_message, new_author, new_extra
		end
		return message, author, extra
	end
	local text, author, channel = shown_line(filters.CHAT_MSG_SAY, "Hello", "Thrall", "1")
	check("a timestamped line stays in chat with its sender", text == "09:05 Hello" and author == "Thrall" and channel == "1")
	play.issecretvalue = function(value)
		return value == "secret"
	end
	local secret_text, secret_author = shown_line(filters.CHAT_MSG_SAY, "secret", "Thrall")
	check("secret chat text stays in place", secret_text == "secret" and secret_author == "Thrall" and addon.chat_tweaks.stamp("secret") == "secret")
	play.issecretvalue = nil
	addon.module.set("chat_tweaks", "timestamps", false)
	check("turning timestamps off removes the prefix", addon.chat_tweaks.stamp("Hello") == "Hello" and filters.CHAT_MSG_SAY == nil)
	local util_filters = {}
	play.ChatFrameUtil = {
		AddMessageEventFilter = function(event, callback)
			util_filters[event] = callback
		end,
		RemoveMessageEventFilter = function(event)
			util_filters[event] = nil
		end,
	}
	addon.module.set("chat_tweaks", "timestamps", true)
	text, author = shown_line(util_filters.CHAT_MSG_SAY, "Hello", "Thrall", "1")
	check("timestamps register on ChatFrameUtil and keep the sender", text == "09:05 Hello" and author == "Thrall" and filters.CHAT_MSG_SAY == nil)
	addon.module.set("chat_tweaks", "timestamps", false)
	check("turning timestamps off removes the ChatFrameUtil filter", util_filters.CHAT_MSG_SAY == nil)
	play.ChatFrameUtil = nil

	play.MapCanvasDataProviderMixin = {}
	play.MapCanvasPinMixin = {}
	play.CreateFromMixins = function()
		return {}
	end
	local added, removed = 0, 0
	local map_provider
	local acquired = {}
	local map = {
		GetMapID = function()
			return 37
		end,
		RemoveAllPinsByTemplate = function(_, template)
			acquired.removed = template
		end,
		AcquirePin = function(_, template, info)
			local pin = {
				texture = {
					SetVertexColor = function(self, r, g, b)
						self.r, self.g, self.b = r, g, b
					end,
				},
				SetSize = function() end,
				SetPosition = function(self, x, y)
					self.x, self.y = x, y
				end,
				SetScript = function(self, name, callback)
					self.scripts = self.scripts or {}
					self.scripts[name] = callback
				end,
			}
			if play.EverlookMapPinMixin and play.EverlookMapPinMixin.OnAcquired then
				play.EverlookMapPinMixin.OnAcquired(pin, info)
			end
			acquired[#acquired + 1] = { template = template, pin = pin }
			return pin
		end,
	}
	play.WorldMapFrame = {
		AddDataProvider = function(_, provider)
			added = added + 1
			map_provider = provider
		end,
		RemoveDataProvider = function(_, provider)
			removed = removed + 1
			if provider and provider.RemoveAllData then
				provider:RemoveAllData()
			end
		end,
	}
	addon.world.store("npcs", { id = 69, name = "Wolf", classification = "normal", locations = { { mapId = 37, x = 100, y = 100 } } })
	addon.world.store("quests", { id = 62, title = "Mine", locations = { { mapId = 37, x = 400, y = 400, role = 1 } } })
	addon.module.set("map_pins", "enabled", true)
	map_provider.GetMap = function()
		return map
	end
	map_provider:RefreshAllData()
	check("map pins attach to the stock map", added == 1 and addon.map_pins.attached())
	check("the stock map acquires a pin at the quest giver", #acquired == 1 and acquired[1].template == "EverlookMapPinTemplate" and acquired[1].pin.x == 0.4 and acquired[1].pin.y == 0.4)
	check("a quest pin is tinted gold", acquired[1].pin.texture.r == 1 and acquired[1].pin.texture.g == 0.82 and acquired[1].pin.texture.b == 0.2)
	play.GameTooltip = {
		lines = {},
		AddLine = function(self, text)
			self.lines[#self.lines + 1] = text
		end,
		SetOwner = function() end,
		Show = function(self)
			self.shown = true
		end,
		Hide = function(self)
			self.shown = false
		end,
	}
	acquired[1].pin.scripts.OnEnter(acquired[1].pin)
	check("a pin tooltip names the row and its role", play.GameTooltip.lines[1] == "Mine" and play.GameTooltip.lines[2] == "giver" and play.GameTooltip.shown == true)
	local refreshes = 0
	local refresh_data = map_provider.RefreshAllData
	map_provider.RefreshAllData = function(self)
		refreshes = refreshes + 1
		return refresh_data(self)
	end
	addon.world.store("objects", { id = 8, name = "Box", locations = { { mapId = 37, x = 1, y = 1 } } })
	check("a new place refreshes pins while the map is attached", refreshes == 1)
	play.WorldMapFrame.GetMapID = function()
		return 37
	end
	addon.world.store("objects", { id = 11, name = "Far crate", locations = { { mapId = 1, x = 1, y = 1 } } })
	check("a place on another map does not redraw this one", refreshes == 1)
	addon.world.store("objects", { id = 12, name = "Near crate", locations = { { mapId = 37, x = 1, y = 1 } } })
	check("a place on this map does", refreshes == 2)
	refreshes = 1
	play.WorldMapFrame.GetMapID = nil
	local queued = {}
	play.C_Timer.After = function(_, callback)
		queued[#queued + 1] = callback
	end
	play.WorldMapFrame.IsShown = function()
		return true
	end
	local before = refreshes
	addon.world.store("objects", { id = 9, name = "Crate", locations = { { mapId = 37, x = 2, y = 2 } } })
	addon.world.store("npcs", { id = 70, name = "Timber Wolf", classification = "rare", locations = { { mapId = 37, x = 3, y = 3 } } })
	check("an open map gathers pin updates into one refresh", refreshes == before and #queued == 1)
	queued[1]()
	check("that refresh draws the whole burst", refreshes == before + 1)
	play.WorldMapFrame.IsShown = function()
		return false
	end
	addon.world.store("objects", { id = 10, name = "Herb", locations = { { mapId = 37, x = 4, y = 4 } } })
	check("a closed map does not rebuild pins", refreshes == before + 1 and #queued == 1)
	play.WorldMapFrame.IsShown = function()
		return true
	end
	map_provider:OnShow()
	check("opening the map draws places gathered while it was closed", refreshes == before + 2)
	acquired.removed = nil
	addon.module.set("map_pins", "enabled", false)
	check("turning map pins off releases the pin template", removed == 1 and not addon.map_pins.attached() and acquired.removed == "EverlookMapPinTemplate")
end
