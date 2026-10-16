-- /everlook probe: it reads what exists, listens for deaths and keeps what an event carried by type only.
return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)
	local function load(extra)
		local said = {}
		local Everlook = { say = function(line) said[#said + 1] = line end }
		local env = setmetatable({ EverlookDB = {}, GetBuildInfo = function() return "1.60.1", "70374" end }, { __index = _G })
		env._G = env
		for key, value in pairs(extra or {}) do env[key] = value end
		local chunk = assert(loadfile(source("probe")))
		setfenv(chunk, env)
		chunk("Everlook", Everlook)
		return Everlook, env, said
	end

	local addon = load({ C_Map = { GetMapRectOnMap = function() end }, GetQuestLogRewardXP = function() return 40, 120 end,
		C_QuestLog = { IsQuestFlaggedCompleted = function() return false end } })
	local facts = table.concat(addon.probe.facts(), "\n")
	check("present functions are reported, absent ones too", facts:find("C_Map.GetMapRectOnMap: present", 1, true) and facts:find("CanLootUnit: missing", 1, true))
	check("a harmless call reports the types it returns", facts:find("IsQuestFlaggedCompleted(1): boolean false", 1, true) and facts:find("GetQuestLogRewardXP(1): number, number", 1, true))
	local plain = load({ issecretvalue = function(value) return value == "secret" end })
	check("an event is described by the type of what came with it, secret or not", plain.probe.describe("UNIT_DIED", "Creature-0-1") == "UNIT_DIED string"
		and plain.probe.describe("UNIT_DIED", "secret") == "UNIT_DIED secret" and plain.probe.describe("PARTY_KILL", nil) == "PARTY_KILL nil")

	local offered = load({ UnitLevel = function() return 12 end, C_GossipInfo = { GetAvailableQuests = function() return { { questID = 5, questLevel = 14 }, { questID = 6, questLevel = 9 } } end },
		C_QuestLog = { IsQuestFlaggedCompleted = function(id) return id == 6 end } })
	check("a giver's window is described by counts and levels, with no title or id", offered.probe.offers() == "offers: 2 available, highest level 14, player level 12, 1 of them flagged completed")
	check("a client with no offer list says so", load().probe.offers() == "offers: no list on this client")

	local handler, registered, unregistered, env_finish
	local running, env, said = load({
		CreateFrame = function() return {
			RegisterEvent = function(_, event) if event == "PARTY_KILL" then error("unknown event") end registered = (registered or 0) + 1 end,
			SetScript = function(_, _, fn) handler = fn end,
			UnregisterAllEvents = function() unregistered = true end,
		} end,
		C_Timer = { After = function(_, fn) env_finish = fn end },
	})
	running.probe.run()
	handler(nil, "UNIT_DIED", "Creature-0-1")
	handler(nil, "UNIT_DIED", "Creature-0-2")
	local report = table.concat(said, "\n")
	check("a refused event is said, an accepted one too", report:find("Register UNIT_DIED: accepted", 1, true) and report:find("Register PARTY_KILL: refused", 1, true))
	env_finish()
	check("the answer is saved with the types and counts, and the listener stops", unregistered and env.EverlookDB.probe.events[1] == "UNIT_DIED string x2" and env.EverlookDB.probe.build == "70374")
	check("the saved answer holds no GUID", not tostring(env.EverlookDB.probe.events[1]):find("Creature", 1, true))
	do
		-- What the game says about a corpse a second after the death, with the id kept out.
		local timers, death_handler = {}, nil
		local looked = {}
		local dying, death_env = load({
			CreateFrame = function() return { RegisterEvent = function() end, SetScript = function(_, _, fn) death_handler = fn end, UnregisterAllEvents = function() end } end,
			C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end },
			UnitGUID = function(unit) if unit == "target" then return "Creature-0-7" end end,
			CanLootUnit = function(guid) looked[#looked + 1] = guid; return false, true end,
			issecretvalue = function(value) return value == "hidden" end,
		})
		dying.probe.run()
		death_handler(nil, "UNIT_DIED", "Creature-0-7")
		death_handler(nil, "UNIT_DIED", "Creature-0-8")
		death_handler(nil, "UNIT_DIED", "hidden")
		check("each readable death is looked at once, a second later, and a hidden one not at all", #timers == 3 and timers[2].seconds == 1 and timers[3].seconds == 1 and #looked == 0)
		timers[2].fn(); timers[3].fn()
		timers[1].fn()
		local joined = table.concat(death_env.EverlookDB.probe.events, "\n")
		check("the answer says whether the creature was the target, and what CanLootUnit returned, with no id",
			joined:find("death: target at death true, CanLootUnit answered (hasLoot false, canLoot true) x1", 1, true)
			and joined:find("death: target at death false, CanLootUnit answered (hasLoot false, canLoot true) x1", 1, true)
			and not joined:find("Creature", 1, true))
	end

	do
		-- The checks done by touching something: each answers in lines and keeps them, and a subject it does not know is said.
		local function frame_with(overrides)
			local frame = { passes = 0 }
			function frame:SetPassThroughButtons() self.passes = self.passes + 1 end
			function frame:CreateFontString()
				local region = { max_lines = 0, text = "" }
				function region:SetMaxLines(value) self.max_lines = value end
				function region:SetText(value) self.text = value end
				function region:GetStringWidth() return (self.max_lines == 1 and overrides.blank) and 0 or #self.text * 6 end
				return region
			end
			return frame
		end
		local panel_closed = 0
		local combat, combat_env, said_combat = load({
			InCombatLockdown = function() return true end,
			SettingsPanel = { IsShown = function() return true end },
			HideUIPanel = function() panel_closed = panel_closed + 1; error("blocked") end,
			CreateFrame = function() return frame_with({}) end,
		})
		combat.probe.run("combat")
		local joined = table.concat(combat_env.EverlookDB.probe.combat.lines, "\n")
		check("the combat check says what the client allowed, and keeps it", panel_closed == 1 and joined:find("in combat: true", 1, true)
			and joined:find("close the settings panel: refused", 1, true) and joined:find("pass-through: allowed", 1, true) and #said_combat >= 3)

		local closed_first, first_env = load({ SettingsPanel = { IsShown = function() return false end }, CreateFrame = function() return frame_with({}) end })
		closed_first.probe.run("combat")
		check("with the panel closed it says to open it first and does not try", table.concat(first_env.EverlookDB.probe.combat.lines, "\n"):find("open it first", 1, true) ~= nil)

		local blank, blank_env = load({ CreateFrame = function() return frame_with({ blank = true }) end })
		blank.probe.run("lines")
		check("a one-line text with no width is called the bug", table.concat(blank_env.EverlookDB.probe.lines.lines, "\n"):find("left the text blank", 1, true) ~= nil)
		local fine, fine_env = load({ CreateFrame = function() return frame_with({}) end })
		fine.probe.run("lines")
		check("a one-line text with a width is called fine", table.concat(fine_env.EverlookDB.probe.lines.lines, "\n"):find("left the text with a width", 1, true) ~= nil)

		local function button(text) return { Text = { GetText = function() return text end } } end
		local list = { button("[12] Wolves"), button("Boars"), button("[3] Murlocs") }
		local quests, quest_env = load({
			QuestScrollFrame = { titleFramePool = { EnumerateActive = function()
				local index = 0
				return function() index = index + 1; return list[index], true end
			end } },
			GetCVar = function() return "0" end,
		})
		quests.module = { enabled = function() return false end }
		quests.probe.run("quests")
		local report = table.concat(quest_env.EverlookDB.probe.quests.lines, "\n")
		check("the quest log check counts titles that already start with a number in brackets", report:find("3 titles, 2 start with", 1, true) and report:find("the game's own", 1, true) and report:find("colorblind mode: 0", 1, true))
		local from_data, data_env = load({
			GetQuestTitlePrefix = function() end,
			C_QuestLog = { GetNumQuestLogEntries = function() return 3 end, GetInfo = function(index)
				return ({ { title = "Wolves" }, { title = "[9] Boars" }, { title = "Region", isHeader = true } })[index]
			end },
		})
		from_data.probe.run("quests")
		local from_report = table.concat(data_env.EverlookDB.probe.quests.lines, "\n")
		check("without the log open, the data still says whether the game has a prefix function and prefixes its titles", from_report:find("GetQuestTitlePrefix: present", 1, true)
			and from_report:find("quests in the log by the data: 2, 1 of their titles", 1, true) and from_report:find("not drawn yet", 1, true))
		local undrawn, undrawn_env, said_undrawn = load({})
		undrawn.probe.run("quests")
		check("an undrawn quest log is said, not guessed", table.concat(undrawn_env.EverlookDB.probe.quests.lines, "\n"):find("not drawn yet", 1, true) ~= nil)
		local lost, _, said_lost = load({})
		lost.probe.run("nonsense")
		check("a subject it does not know is said", said_lost[1]:find("Probe what?", 1, true) ~= nil)
	end

	do
		-- Whose GUID PARTY_KILL carries, told by the kind and by whether the same GUID died in UNIT_DIED.
		local handler, finish
		local party, party_env = load({
			CreateFrame = function() return { RegisterEvent = function() end, SetScript = function(_, _, fn) handler = fn end, UnregisterAllEvents = function() end } end,
			C_Timer = { After = function(seconds, fn) if seconds == 120 then finish = fn end end },
		})
		party.probe.run()
		handler(nil, "UNIT_DIED", "Creature-0-1-0-2-448-abc")
		handler(nil, "PARTY_KILL", "Creature-0-1-0-2-448-abc")
		handler(nil, "PARTY_KILL", "Player-1-0000")
		finish()
		local joined = table.concat(party_env.EverlookDB.probe.events, "\n")
		check("PARTY_KILL is told apart by kind and by whether its GUID died, with no id kept",
			joined:find("is a creature that also died in UNIT_DIED: 1 of 2 (kinds: Creature x1, Player x1)", 1, true) and not joined:find("448", 1, true))
	end

	do
		local maps, maps_env = load({
			C_Map = {
				GetBestMapForUnit = function() return 1415 end,
				GetMapInfo = function() return { mapType = 2 } end,
				GetMapArtID = function() return 1234 end,
				GetMapArtLayers = function() return { { layerWidth = 100, layerHeight = 50, tileWidth = 256 } } end,
				GetMapArtLayerTextures = function() return { 11, 12, 13 } end,
				GetMapChildrenInfo = function() return { { mapID = 1426 } } end,
				GetMapRectOnMap = function() return 0.4, 0.6, 0.2, 0.4 end,
			},
			C_MapExplorationInfo = { GetExploredMapTextures = function() return { { textureWidth = 10, offsetX = 1, fileDataIDs = { 5 } } } end },
		})
		maps.probe.run("maps")
		local joined = table.concat(maps_env.EverlookDB.probe.maps.lines, "\n")
		check("the map check names each function's fields and types, the rectangle of a child zone, and no file id", joined:find("GetMapArtID: number", 1, true)
			and joined:find("first art layer: {layerHeight:number, layerWidth:number, tileWidth:number}", 1, true) and joined:find("textures in layer 1: 3", 1, true)
			and joined:find("first explored entry: {fileDataIDs:table, offsetX:number, textureWidth:number}", 1, true) and joined:find("0.400 0.600 0.200 0.400", 1, true))
		local missing, missing_env = load({ C_Map = { GetBestMapForUnit = function() return 1415 end } })
		missing.probe.run("maps")
		check("a missing function is said as missing", table.concat(missing_env.EverlookDB.probe.maps.lines, "\n"):find("GetMapArtID: missing", 1, true) ~= nil)
	end

	do
		local names = { [14] = "Durotar", [15] = "Dustwallow Marsh", [4096] = "Hidden", [4097] = "" }
		local areas, areas_env = load({ C_Map = { GetAreaInfo = function(id) if id == 4096 then return "secret" end return names[id] end } })
		areas.probe.run("areas")
		local kept = areas_env.EverlookDB.probe.areas.lines
		check("the area probe keeps each area's id and name, and counts them on the first line", kept[1]:find("2 area names", 1, true) and kept[2] == "14|Durotar" and kept[3] == "15|Dustwallow Marsh")
		check("a name the client hides is left out", not table.concat(kept, "\n"):find("4096", 1, true))
		local bare, bare_env = load({})
		bare.probe.run("areas")
		check("a client with no area function says so", bare_env.EverlookDB.probe.areas.lines[1]:find("no C_Map.GetAreaInfo", 1, true) ~= nil)
	end
end
