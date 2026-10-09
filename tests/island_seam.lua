return function(root, check, island_world, quest_world, secret_stat)
	local source = dofile(root .. "/tests/suite.lua")(root)
	local function read_source(name)
		local handle = assert(io.open((source(name)), "r"))
		local text = handle:read("*a")
		handle:close()
		return text
	end

	local function notice_key(addon, key)
		for _, notice in ipairs(addon.smart_island.view().notices) do
			if notice.key == key then return notice end
		end
	end

	local function show_recap(addon, env)
		local buttons = {}
		env.CreateSettingsButtonInitializer = function(name, _, click)
			return { name = name, click = click }
		end
		local module
		for _, candidate in ipairs(addon.module.modules) do
			if candidate.id == "smart_island" then module = candidate end
		end
		local layout = { AddInitializer = function(_, row) buttons[row.name] = row end }
		for _, section in ipairs(addon.module.sections(module) or {}) do
			if section.after then section.after(layout) end
		end
		return buttons["Session recap"] and buttons["Session recap"].click()
	end

	check("repair uses one notice call", not read_source("auto_repair.lua"):find("confirm_money", 1, true))
	check("junk uses one notice call", not read_source("sell_junk.lua"):find("confirm_money", 1, true))
	do
		local named = false
		for _, feed in ipairs({ "island_share", "island_quest_notices", "island_loot", "island_hearth", "island_reputation", "island_professions",
			"island_mail", "island_invites", "island_buffs", "island_recap", "island_warnings" }) do
			named = named or read_source("smart_island.lua"):find(feed, 1, true) ~= nil
		end
		check("the island chunk does not name its feed addons", not named)
	end
	check("recap experience uses the shared bar advance",
		not read_source("island_recap.lua"):find("xp_level + 1", 1, true))
	check("the level cap stays behind the shared readings",
		not read_source("island_recap.lua"):find("GetMaxPlayerLevel", 1, true)
		and not read_source("island_experience.lua"):find("GetMaxPlayerLevel", 1, true))
	check("the island does not read the player map",
		not read_source("smart_island.lua"):find("GetPlayerMapPosition", 1, true)
		and not read_source("smart_island.lua"):find("GetBestMapForUnit", 1, true))
	check("quest direction reads the waypoint and leaves tracking alone",
		read_source("island_quests.lua"):find("GetNextWaypoint", 1, true) ~= nil
		and not read_source("island_quests.lua"):find("SetSuperTrackedQuestID", 1, true)
		and not read_source("island_quests.lua"):find("C_Navigation", 1, true))
	check("the island does not resolve item or spell icons",
		not read_source("smart_island.lua"):find("GetItemIconByID", 1, true)
		and not read_source("smart_island.lua"):find("GetSpellTexture", 1, true))
	check("activity thresholds stay out of the island chunk",
		not read_source("smart_island.lua"):find("free-slots", 1, true)
		and not read_source("smart_island.lua"):find("Paid from personal funds", 1, true)
		and not read_source("smart_island.lua"):find("The bags are full", 1, true))
	check("figure phrasing stays behind vitals",
		not read_source("smart_island.lua"):find("format_money", 1, true)
		and not read_source("smart_island.lua"):find("format_bags", 1, true)
		and not read_source("smart_island.lua"):find("format_percent", 1, true)
		and not read_source("island_vitals.lua"):find("format_bags", 1, true)
		and not read_source("island_vitals.lua"):find("format_percent", 1, true)
		and not read_source("island_vitals.lua"):find(".format_", 1, true))
	check("scan stays a call list", read_source("scan.lua"):find("function Everlook.scan.now", 1, true) ~= nil)
	do
		local addon = island_world()
		local advance = addon.island_vitals.advance
		check("a bar advance is the shared experience delta",
			advance({ level = 10, xp = 100, xp_max = 1000 }, { level = 10, xp = 250, xp_max = 1000 }) == 150
			and advance({ level = 10, xp = 400, xp_max = 1000 }, { level = 11, xp = 50, xp_max = 2000 }) == 650
			and advance({ level = 10, xp = 100, xp_max = 1000 }, { level = 10, xp = 50, xp_max = 1000 }) == nil
			and advance({ level = 10, xp = 100, xp_max = 1000 }, { level = 12, xp = 0, xp_max = 1000 }) == nil)
	end

	do
		local addon, env, event = quest_world()
		addon.module.set("smart_island", "source_quest_completion", true)
		addon.module.set("smart_island", "feed_recap", true)
		event("QUEST_TURNED_IN", 23, 10, 50)
		local completed = 0
		for _, notice in ipairs(addon.smart_island.view().notices) do
			if notice.text == "Quest completed" then completed = completed + 1 end
		end
		local completion = nil
		for _, notice in ipairs(addon.smart_island.view().notices) do
			if notice.text == "Quest completed" then completion = notice end
		end
		check("one turn-in publishes one completion notice", completed == 1 and completion.detail == "Ready to return" and completion.money == 50)
		local secret = secret_stat()
		env.issecretvalue = function(value) return rawequal(value, secret) end
		event("QUEST_TURNED_IN", secret, 10, 50)
		completed = 0
		for _, notice in ipairs(addon.smart_island.view().notices) do
			if notice.text == "Quest completed" then completed = completed + 1 end
		end
		check("a secret turn-in does not add a completion notice", completed == 1)
		check("show recap counts that turn-in once", show_recap(addon, env) == true
			and notice_key(addon, "session-recap").detail:find("Quests completed: 1", 1, true))
	end

	do
		local addon, env, event, state, _, tickers = island_world()
		addon.module.set("smart_island", "enabled", true)
		addon.module.set("smart_island", "feed_recap", true)
		state.level = 14
		tickers[1].callback()
		check("a missed level marks experience incomplete", show_recap(addon, env) == true
			and notice_key(addon, "session-recap").detail:find("XP incomplete", 1, true))
		local secret = secret_stat()
		env.issecretvalue = function(value) return rawequal(value, secret) end
		event("QUEST_TURNED_IN", secret)
		event("QUEST_TURNED_IN", 18)
		env.GetMoney = function() return secret end
		show_recap(addon, env)
		local recap = notice_key(addon, "session-recap")
		check("secret quests and money stay out of the recap", recap.detail:find("Quests completed: 1", 1, true)
			and recap.detail:find("Money unavailable", 1, true) and recap.money == nil)
	end

	do
		local addon, env, _, state = island_world()
		state.level, state.xp, state.xp_max = 90, 0, 0
		env.GetMaxPlayerLevel = function() return 90 end
		addon.module.set("smart_island", "enabled", true)
		addon.module.set("smart_island", "feed_recap", true)
		check("the level cap is one question", addon.island_vitals.at_cap(90) == true and addon.island_vitals.at_cap(12) == false)
		check("the level cap baseline stays quiet", #addon.smart_island.view().notices == 0)
		check("an empty bar at the level cap counts no experience", show_recap(addon, env) == true
			and notice_key(addon, "session-recap").detail:find("XP gained: 0", 1, true)
			and not notice_key(addon, "session-recap").detail:find("XP incomplete", 1, true))
		local addon2, env2, event2, state2 = island_world()
		state2.level, state2.xp, state2.xp_max = 89, 500, 1000
		env2.GetMaxPlayerLevel = function() return 90 end
		addon2.module.set("smart_island", "enabled", true)
		addon2.module.set("smart_island", "feed_recap", true)
		state2.level, state2.xp, state2.xp_max = 90, 0, 0
		event2("PLAYER_LEVEL_UP", 90)
		check("reaching the level cap keeps the last bar", show_recap(addon2, env2) == true
			and notice_key(addon2, "session-recap").detail:find("XP gained: 500", 1, true))
		local addon3, env3, _, state3 = island_world()
		state3.level, state3.xp, state3.xp_max = 12, 0, 0
		env3.GetMaxPlayerLevel = function() return 90 end
		addon3.module.set("smart_island", "enabled", true)
		addon3.module.set("smart_island", "feed_recap", true)
		check("a zero bar below the level cap stays incomplete", show_recap(addon3, env3) == true
			and notice_key(addon3, "session-recap").detail:find("XP incomplete", 1, true))
	end
	do
		local addon, env, event, state, _, tickers = island_world()
		local scans = 0
		env.C_Reputation = {
			GetNumFactions = function() scans = scans + 1; return 0 end,
			GetFactionDataByIndex = function() end,
		}
		addon.module.set("smart_island", "enabled", true)
		addon.module.set("smart_island", "feed_reputation", true)
		local baseline = scans
		for _ = 1, 5 do event("QUEST_LOG_UPDATE") end
		check("quest log bursts do not poll the reputation feed", scans == baseline)
		for _ = 1, 4 do state.time = state.time + 1; tickers[1].callback() end
		check("the timed poll keeps reputation on a slow beat", scans - baseline <= 1)
		state.time = state.time + 5
		tickers[1].callback()
		check("the slow beat still comes around", scans - baseline >= 1)
	end
	do
		local addon, env, event, state, afters = island_world()
		local scans = 0
		env.C_QuestLog = {
			GetNumQuestLogEntries = function() scans = scans + 1; return 0 end,
			GetNumQuestWatches = function() return 0 end,
			GetInfo = function() end,
		}
		addon.module.set("smart_island", "enabled", true)
		addon.module.set("smart_island", "quest_context", true)
		state.time = state.time + 10
		local baseline = scans
		for _ = 1, 6 do event("QUEST_LOG_UPDATE") end
		check("a quest event burst scans the log once at once", scans - baseline == 1)
		for _, after in ipairs(afters) do after.callback() end
		check("the rest of the burst scans once more when the window ends", scans - baseline == 2)
	end
	do
		local addon, _, _, state, _, tickers, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		local island_frame
		for _, candidate in ipairs(frames) do if candidate.name == "EverlookSmartIsland" then island_frame = candidate end end
		local placements = 0
		local place = island_frame.SetPoint
		island_frame.SetPoint = function(...) placements = placements + 1; return place(...) end
		for _ = 1, 3 do state.time = state.time + 1; tickers[1].callback() end
		check("an idle closed pill does not repaint on the timer", placements == 0)
	end
	do
		local addon = island_world()
		local age = addon.smart_island.age_text
		check("notice ages step from seconds to minutes to hours",
			age(5) == "Just now" and age(125) == "2m ago" and age(3600) == "1h ago" and age(3900) == "1h 5m ago")
	end
	do
		local addon, _, _, _, _, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		local function surface_alphas()
			local alphas = {}
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions or {}) do
					if region.color and region.color[1] == 13 / 255 then alphas[#alphas + 1] = region.color[4] end
				end
			end
			return alphas
		end
		local before = surface_alphas()
		check("the island surface starts at 96 percent", #before > 0 and before[1] == 0.96)
		addon.module.set("smart_island", "opacity", 60)
		local after = surface_alphas()
		check("the opacity option retints the surfaces already built", #after == #before and after[1] == 0.6)
	end
	do
		local addon = island_world()
		addon.module.set("smart_island", "enabled", true)
		addon.module.set("smart_island", "inbox_size", 20)
		addon.module.set("smart_island", "toast_count", 1)
		for index = 1, 15 do addon.island.notify({ source = "Test", key = "n" .. index, text = "Notice " .. index }) end
		local view = addon.smart_island.view()
		check("the inbox keeps as many notices as the option allows", #view.notices == 15)
		check("the toast count option caps the stack", #view.toasts == 1)
		addon.module.set("smart_island", "inbox_size", 10)
		check("lowering the inbox size trims the oldest notices", #addon.smart_island.view().notices == 10)
	end
	do
		local addon = island_world()
		addon.module.set("smart_island", "enabled", true)
		addon.module.set("smart_island", "do_not_disturb", true)
		addon.island.notify({ source = "Test", key = "quiet", text = "Routine", severity = "warning" })
		addon.island.notify({ source = "Test", key = "info", text = "Info" })
		local view = addon.smart_island.view()
		check("do not disturb sends warnings and routine notices to the inbox", #view.toasts == 0 and #view.notices == 2)
		addon.island.notify({ source = "Test", key = "bad", text = "Failure", severity = "error" })
		check("do not disturb still toasts an error", #addon.smart_island.view().toasts == 1)
	end
	do
		local addon = island_world()
		addon.module.set("smart_island", "enabled", true)
		addon.module.set("smart_island", "size", 120)
		check("an unknown preset changes nothing", addon.smart_island.apply_preset("Loud") == false)
		check("the Informative preset turns the feeds on", addon.smart_island.apply_preset("Informative") == true
			and addon.module.get("smart_island", "feed_loot") == true and addon.module.get("smart_island", "quest_context") == true)
		check("the Quiet preset turns them off and keeps the warnings", addon.smart_island.apply_preset("Quiet") == true
			and addon.module.get("smart_island", "feed_loot") == false and addon.module.get("smart_island", "source_bags") == true)
		check("presets leave placement and size alone", addon.module.get("smart_island", "size") == 120)
	end
	do
		local addon, env, _, state, _, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		local island_frame
		for _, candidate in ipairs(frames) do if candidate.name == "EverlookSmartIsland" then island_frame = candidate end end
		local shift, cursor = false, { 500, 500 }
		env.IsShiftKeyDown = function() return shift end
		env.GetCursorPosition = function() return cursor[1], cursor[2] end
		island_frame.scripts.OnDragStart(island_frame)
		cursor = { 600, 400 }
		island_frame.scripts.OnDragStop(island_frame)
		check("a drag without Shift leaves the placement alone",
			addon.module.get("smart_island", "position_x") == 0 and addon.module.get("smart_island", "position_top") == 12)
		shift, cursor = true, { 500, 500 }
		island_frame.scripts.OnDragStart(island_frame)
		cursor = { 600, 400 }
		island_frame.scripts.OnDragStop(island_frame)
		check("Shift and drag writes the placement options",
			addon.module.get("smart_island", "position_x") == 100 and addon.module.get("smart_island", "position_top") == 112)
		island_frame.scripts.OnClick(island_frame)
		check("the click that ends a drag does not pin the island", addon.smart_island.view().pinned == false)
		state.time = state.time + 1
		island_frame.scripts.OnClick(island_frame)
		check("a later click still pins it", addon.smart_island.view().pinned == true)
	end
	do
		local addon, _, _, state, afters, tickers, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		local island_frame
		for _, candidate in ipairs(frames) do if candidate.name == "EverlookSmartIsland" then island_frame = candidate end end
		addon.module.set("smart_island", "hide_when_idle", true)
		check("the pill stays through the first quiet seconds", island_frame.alpha ~= 0)
		state.time = state.time + 6
		for _, after in ipairs(afters) do after.callback() end
		check("an idle pill fades out", island_frame.alpha == 0)
		addon.island.notify({ source = "Test", key = "back", text = "Hello" })
		check("a notice brings the pill back", island_frame.alpha == 1)
		addon.module.set("smart_island", "hide_when_idle", false)
		check("turning the option off keeps it visible", island_frame.alpha == 1)
	end
	do
		local function with_character(env)
			env.UnitGUID = function() return "Player-1-00000001" end
			env.GetServerTime = function() return 1000000 end
		end
		local first, first_env, first_event, first_state = island_world()
		with_character(first_env)
		first.module.set("smart_island", "enabled", true)
		first.island.notify({ source = "Test", key = "kept", text = "Kept row", detail = "Some detail", money = 500 })
		first.island.notify({ source = "Test", key = "live", text = "Bags are full", severity = "warning", persist = true })
		first.island.notify({ source = "Test", key = "act", text = "Has action", actions = {
			{ id = "go", label = "Go", type = "callback", on_click = function() end } } })
		first_state.time = first_state.time + 120
		first_env.GetServerTime = function() return 1000120 end
		local saved = first_env.EverlookDB
		first_event("PLAYER_LOGOUT")
		check("history saves per character", saved.island_history["Player-1-00000001"] ~= nil)

		local second, second_env = island_world()
		with_character(second_env)
		second_env.GetServerTime = function() return 1000300 end
		second_env.EverlookDB = second_env.EverlookDB or {}
		second_env.EverlookDB.island_history = saved.island_history
		second.module.set("smart_island", "enabled", true)
		local notices = second.smart_island.view().notices
		local texts = {}
		for _, notice in ipairs(notices) do texts[#texts + 1] = notice.text end
		check("a reload brings back the plain history rows", table.concat(texts, ",") == "Kept row,Has action")
		check("a restored row keeps its detail, money and unread state",
			notices[1].detail == "Some detail" and notices[1].money == 500 and notices[1].unread == true)
		check("a restored row has no actions and no toast", #notices[2].actions == 0 and #second.smart_island.view().toasts == 0)
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		local island_frame
		local shown = true
		env.UIParent = env.UIParent or {}
		env.UIParent.GetTop = function() return 1080 end
		env.UIWidgetTopCenterContainerFrame = { IsShown = function() return shown end, GetBottom = function() return 1000 end }
		addon.module.set("smart_island", "enabled", true)
		for _, candidate in ipairs(frames) do if candidate.name == "EverlookSmartIsland" then island_frame = candidate end end
		check("the pill drops below a showing top widget", island_frame.point[5] == -88)
		addon.module.set("smart_island", "avoid_top_widgets", false)
		check("the option puts it back at its own distance", island_frame.point[5] == -12)
		addon.module.set("smart_island", "avoid_top_widgets", true)
		shown = false
		addon.module.set("smart_island", "position_top", 16)
		check("a hidden widget leaves the placement alone", island_frame.point[5] == -16)
	end
	do
		local addon, env = island_world()
		addon.module.set("smart_island", "enabled", true)
		check("dismiss with no toast does nothing", env.everlook_smart_island_dismiss() == nil and addon.smart_island.dismiss_top() == false)
		addon.island.notify({ source = "Test", key = "older", text = "Older" })
		addon.island.notify({ source = "Test", key = "newer", text = "Newer" })
		env.everlook_smart_island_dismiss()
		local remaining = {}
		for _, notice in ipairs(addon.smart_island.view().notices) do remaining[#remaining + 1] = notice.text end
		check("the dismiss key removes the newest toast first", table.concat(remaining, ",") == "Older")
		check("the binding file names the dismiss action", read_source("Everlook_Island/Bindings.xml"):find("EVERLOOK_SMART_ISLAND_DISMISS", 1, true) ~= nil)
	end
	do
		local addon, env, event = island_world()
		local waiting = false
		env.HasNewMail = function() return waiting end
		addon.module.set("smart_island", "enabled", true)
		addon.module.set("smart_island", "feed_mail", true)
		waiting = true
		event("UPDATE_PENDING_MAIL")
		check("new mail starts with the plain detail", notice_key(addon, "mail:new").detail == "Unread mail is waiting")
		local headers = { { money = 15000, has_item = 1 }, { money = 0, has_item = 0 }, { money = 0, has_item = 2 } }
		env.GetInboxNumItems = function() return #headers end
		env.GetInboxHeaderInfo = function(index)
			local row = headers[index]
			return nil, nil, "Sender", "Subject", row.money, 0, 30, row.has_item
		end
		event("MAIL_INBOX_UPDATE")
		local notice = notice_key(addon, "mail:new")
		check("opening the mailbox says what is waiting", notice.detail == "3 messages, 2 with attachments, 1g 50s")
		check("that update does not toast again", #addon.smart_island.view().toasts == 0 or notice.presentation == "inbox")
		env.GetInboxNumItems = function() return 0 end
		event("MAIL_INBOX_UPDATE")
		check("an empty mailbox keeps the last summary", notice_key(addon, "mail:new").detail == "3 messages, 2 with attachments, 1g 50s")
	end
	do
		local addon, _, event = island_world()
		addon.module.set("smart_island", "enabled", true)
		event("PARTY_INVITE_REQUEST", "Thrall", false, false, false)
		check("an invite stays quiet while the feed is off", notice_key(addon, "party-invite") == nil)
		addon.module.set("smart_island", "feed_invites", true)
		event("PARTY_INVITE_REQUEST", "Thrall", false, false, false)
		local notice = notice_key(addon, "party-invite")
		check("an invite shows the name and points to the popup", notice and notice.text == "Thrall invited you to a group"
			and notice.detail == "Answer in the invitation popup" and #notice.actions == 0)
		event("PARTY_INVITE_REQUEST", "Jaina", false, true, false)
		check("a finder invite names the role", notice_key(addon, "party-invite").detail == "Looking for a healer")
		event("PARTY_INVITE_CANCEL")
		check("a cancelled invite goes away", notice_key(addon, "party-invite") == nil)
		addon.smart_island.apply_preset("Quiet")
		check("the Quiet preset turns invites off", addon.module.get("smart_island", "feed_invites") == false)
	end
	do
		local addon, env, _, state, _, tickers = island_world()
		env.InCombatLockdown = function() return false end
		local auras = {
			{ spellId = 1, name = "Flask", duration = 3600, expirationTime = 100 + 40 },
			{ spellId = 2, name = "Short buff", duration = 30, expirationTime = 100 + 20 },
			{ spellId = 3, name = "Well Fed", duration = 900, expirationTime = 100 + 200 },
		}
		env.C_UnitAuras = { GetAuraDataByIndex = function(_, index) return auras[index] end }
		addon.module.set("smart_island", "enabled", true)
		addon.module.set("smart_island", "feed_buffs", true)
		check("a buff already inside the window stays quiet", #addon.smart_island.view().notices == 0)
		state.time = state.time + 150
		tickers[1].callback()
		local notice = notice_key(addon, "buff:3:300")
		check("a long buff warns once it is under a minute from the end",
			notice and notice.text == "Well Fed is about to run out" and notice.severity == "warning" and notice.spell_id == 3)
		check("a short buff never warns", notice_key(addon, "buff:2:120") == nil)
		local count = #addon.smart_island.view().notices
		state.time = state.time + 6
		tickers[1].callback()
		check("the same buff does not warn twice", #addon.smart_island.view().notices == count)
		auras[3] = nil
		state.time = state.time + 6
		tickers[1].callback()
		check("the warning goes away when the buff does", notice_key(addon, "buff:3:300") == nil)
		env.InCombatLockdown = function() return true end
		auras[1] = { spellId = 4, name = "Elixir", duration = 600, expirationTime = state.time + 10 }
		state.time = state.time + 6
		tickers[1].callback()
		check("combat skips the buff scan", notice_key(addon, "buff:4:" .. math.floor(state.time + 4)) == nil)
	end
	do
		local addon, env, _, state, _, _, frames = quest_world()
		local objectives = {}
		for index = 1, 6 do objectives[index] = { text = "Objective " .. index, numFulfilled = 0, numRequired = 3, finished = false } end
		state.quests[2].objectives = objectives
		addon.module.set("smart_island", "quest_context", true)
		env.everlook_smart_island_key("down")
		local texts = {}
		for _, frame in ipairs(frames) do
			for _, region in ipairs(frame.regions or {}) do
				if type(region.text) == "string" and region.shown ~= false then texts[#texts + 1] = region.text end
			end
		end
		local joined = "\n" .. table.concat(texts, "\n") .. "\n"
		check("the open quest lists four objectives", joined:find("Objective 4", 1, true) and not joined:find("Objective 5", 1, true))
		check("the rest fold into one line", joined:find("+2 more objectives", 1, true) ~= nil)
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		env.everlook_smart_island_key("down")
		local marks = {}
		for _, frame in ipairs(frames) do
			for _, region in ipairs(frame.regions or {}) do
				if region.shown ~= false and (region.path == "Interface\\Icons\\inv_misc_coin_01" or region.atlas == "SpellIcon-256x256-RepairAll") then
					marks[#marks + 1] = region
				end
			end
		end
		check("the open summary marks money and durability", #marks >= 2)
	end
	do
		local addon, _, event, state, _, tickers = island_world()
		local stats = addon.island_stats
		addon.module.set("smart_island", "enabled", true)
		local paints = stats.paint
		for _ = 1, 10 do state.time = state.time + 1; tickers[1].callback() end
		check("ten idle seconds repaint a closed pill zero times", stats.paint == paints)
		local scans = stats.quest_scan
		check("the counters are plain numbers for /dump", type(scans) == "number" and type(stats.aim) == "number" and type(stats.feed_tick) == "number")
	end
	do
		local addon = island_world()
		local read = addon.island_notice.read
		local record = read({ text = "Hello", kind = "mail", severity = "warning" }, 4)
		check("a plain payload reads into a record with defaults",
			record and record.source == "everlook" and record.duration == 4 and record.icon == "mail" and record.presentation == "toast")
		local bad, reason = read({ text = "  " }, 4)
		check("blank text is refused with its reason", bad == nil and reason == "invalid_text")
		bad, reason = read({ text = "x", progress = 2 }, 4)
		check("progress outside zero to one is refused", bad == nil and reason == "invalid_progress")
		bad, reason = read({ text = "x", presentation = "status" }, 4)
		check("a status needs a source", bad == nil and reason == "invalid_status_source")
		check("an unknown icon falls back to the kind then generic",
			addon.island_notice.icon_for("nope", "x") == "generic" and addon.island_notice.icon_for(nil, "durability") == "repair")
	end
	do
		local addon, env, event, state = island_world()
		local server = 1000000
		env.GetServerTime = function() return server end
		env.UnitGUID = function() return "Player-1-00000002" end
		addon.module.set("smart_island", "enabled", true)
		addon.module.set("smart_island", "feed_experience", true)
		local experience = addon.island_experience
		event("PLAYER_ENTERING_WORLD")
		local first = experience.report()
		check("the experience report is reused within a second", rawequal(first, experience.report()))
		state.xp = state.xp + 100
		event("PLAYER_XP_UPDATE")
		local second = experience.report()
		check("a new gain makes a new report", not rawequal(first, second) and second.hour.total == 100)
		server = server + 1
		check("the next second makes a new report", not rawequal(second, experience.report()))
	end
	do
		local addon, env, _, state, _, _, frames = island_world()
		env.C_Container.GetContainerNumSlots = function(bag) return bag <= 1 and 20 or 0 end
		addon.module.set("smart_island", "enabled", true)
		-- Their cells carry a ring that fills to the share.
		env.everlook_smart_island_key("down")
		local shares = {}
		for _, frame in ipairs(frames) do
			if frame.cooldown and frame.shown == true and frame.paused then
				shares[#shares + 1] = (env.GetTime() - frame.cooldown.start) / frame.cooldown.duration
			end
		end
		table.sort(shares)
		local function near(a, b) return a and math.abs(a - b) < 1e-9 end
		check("two rings show, one for gear and one for bags", #shares == 2)
		check("durability's ring fills to its percentage", near(shares[2], 0.5))
		check("the bags ring fills to the free share", near(shares[1], 8 / 40))
	end
	do
		local addon = island_world()
		local inbox, toasts = addon.island_inbox, addon.island_toasts
		local list = {
			{ id = 1, text = "old routine", unread = false, updated_at = 1 },
			{ id = 2, text = "warning", severity = "warning", unread = false, updated_at = 2 },
			{ id = 3, text = "decision", persist = true, unread = false, updated_at = 3 },
			{ id = 4, text = "new routine", unread = true, updated_at = 4 },
		}
		check("the inbox counts unread notices", inbox.unread(list) == 1)
		inbox.evict(list, 3)
		check("a full inbox drops the oldest routine notice first", #list == 3 and list[1].id == 2)
		inbox.evict(list, 2)
		check("then the unread routine one before warnings and decisions", #list == 2 and list[1].id == 2 and list[2].id == 3)
		local merged = inbox.restore({ { id = 5, key = "k", source = "S", updated_at = 9 } }, {
			{ id = 6, key = "k", source = "S", updated_at = 1 }, { id = 7, updated_at = 5 }, { id = 8, updated_at = 5 } })
		local ids = {}
		for _, entry in ipairs(merged) do ids[#ids + 1] = entry.id end
		check("a cleared notice replaced by its producer stays gone and the rest merge in time order",
			table.concat(ids, ",") == "7,8,5")
		local queue = { { severity = "info" }, { severity = "warning" }, { severity = "warning" }, { severity = "error" } }
		check("the highest priority waits at the front, ties to the earliest", toasts.next_index(queue) == 4)
		table.remove(queue, 4)
		check("a tie keeps the earlier notice", toasts.next_index(queue) == 2)
		check("a newcomer replaces the first lower-priority waiting notice", toasts.evict_index(queue, { severity = "error" }) == 1)
		check("an equal newcomer replaces nothing", toasts.evict_index({ { severity = "warning" } }, { severity = "warning" }) == nil)
	end
	do
		local addon, env = island_world()
		local applied, centers = 0, {}
		env.NineSliceUtil = {
			GetLayout = function(name) return name == "TooltipDefaultLayout" and {} or nil end,
			ApplyLayoutByName = function(container, name)
				applied = applied + 1
				container.Center = { SetVertexColor = function(self, ...) self.color = { ... } end }
				centers[#centers + 1] = container.Center
			end,
		}
		addon.module.set("smart_island", "enabled", true)
		check("the island borrows the game's tooltip border when it exists", applied >= 3 and centers[1].color ~= nil)
		addon.module.set("smart_island", "opacity", 70)
		check("the opacity option tints the native fill", centers[1].color[4] == 0.7)
	end
	do
		local addon = island_world()
		local rim = addon.island_rim
		check("bars keep clear of the corners on the open island", rim.length(100, 60) == 66)
		check("a small pill keeps its bars closer to the border", rim.length(100, 36) == 70)
		check("a bar too short to read is left out", rim.length(30, 60) == nil)
		check("a half full bar lights half its length", rim.lit(0.5, 66) == 33 and rim.lit(0, 66) == 0 and rim.lit(1, 66) == 66)
		check("a fraction outside the range is held to it", rim.lit(3, 66) == 66 and rim.lit(-1, 66) == 0)
	end
	do
		local addon, _, _, state, _, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		local function face() for _, f in ipairs(frames) do if f.name == "EverlookIslandFace" then return f end end end
		local function closed_text()
			for _, region in ipairs(face().regions or {}) do
				if type(region.text) == "string" and region.text:find("12", 1, true) and region.shown ~= false then return region.text end
			end
		end
		check("the closed pill is the level chip by default in these tests", face().width == 64)
		addon.module.set("smart_island", "closed_xp", true)
		check("the experience percent widens the pill", face().width > 64 and closed_text() and closed_text():find("45%", 1, true))
		check("on the level chip too the percent is purple and the level white", closed_text():find("|cffad76ef45%|r", 1, true) and closed_text():find("|cfff5f7fa12|r", 1, true))
		addon.module.set("smart_island", "closed_clock", true)
		check("the clock joins it", closed_text():find("14:05", 1, true) ~= nil)
		state.bags = { [0] = 1, [1] = 1 }
		addon.smart_island.pull()
		addon.module.set("smart_island", "low_slots", 5)
		check("low bags warn on the pill without a setting", closed_text():find("Bags 2", 1, true) ~= nil)
		addon.module.set("smart_island", "closed_xp", false)
		addon.module.set("smart_island", "closed_clock", false)
		state.bags = { [0] = 6, [1] = 8 }
		addon.smart_island.pull()
		addon.module.set("smart_island", "low_slots", 1)
		check("with every extra off and nothing wrong it is the level chip again", face().width == 64)
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		env.everlook_smart_island_key("down")
		local function label(text)
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions or {}) do
					if region.text == text and region.shown ~= false then return region end
				end
			end
		end
		local function cell(text) local found = label(text); return found and found.parent and found.parent.parent end
		check("the open summary has a Status heading", label("STATUS") ~= nil)
		local money, gear, bags = cell("Money"), cell("Gear"), cell("Bags")
		-- Worked from the scale by hand: edge 12, a 14 high level line, 16 to
		-- Status, 14 high Status, 8 to the cells. The XP rail is not drawn here,
		-- because the top edge bar already shows experience, so it takes no room.
		local status = label("STATUS")
		check("the Status heading is a section gap below the level line, with no room kept for a hidden rail",
			-status.point[5] == 12 + 14 + 16)
		-- With no quest the island is 440 wide and stacked: 416 inside the edges,
		-- one gap of 8, so two columns of 204. Money has the first row, and gear
		-- and bags share the second.
		check("the island is narrow with no quest, and its cells share one width and the summary's left edge",
			addon.smart_island.view().width == 440 and money.width == 204 and gear.width == 204 and bags.width == 204
			and money.point[4] == 12 and gear.point[4] == 12)
		check("gear and bags share the row below money, gear on the left",
			gear.point[5] == bags.point[5] and gear.point[5] == money.point[5] - 32 - 8 and bags.point[4] == 12 + 204 + 8)
		check("the cells begin one step below the Status heading", -money.point[5] == -status.point[5] + 14 + 8)
		local name, figure = label("Gear"), label("50%")
		check("a value sits under its name on the cell's left edge",
			name.point[4] == figure.point[4] and name.point[5] == 0 and figure.point[5] == -(14 + 4))
		check("the summary ends one edge below the last row",
			addon.smart_island.view().summary_height == -money.point[5] + 32 + 8 + 32 + 12)
		check("the clock moved to the header beside the percent", label("14:05    45%") ~= nil and cell("Time") == nil)
	end
	do
		local addon, env, _, state, _, _, frames = quest_world()
		state.quests[2].objectives = {
			{ text = "Collect things", numFulfilled = 1, numRequired = 6, finished = false },
			{ text = "Talk to someone", finished = false },
		}
		addon.module.set("smart_island", "quest_context", true)
		env.everlook_smart_island_key("down")
		local fills, bars = {}, 0
		for _, frame in ipairs(frames) do
			if frame.cooldown and frame.shown == true and frame.width == 16 then fills[#fills + 1] = (env.GetTime() - frame.cooldown.start) / frame.cooldown.duration end
			if frame.value and frame.shown == true and frame.height == 3 and frame.width and frame.width > 100 then bars = bars + 1 end
		end
		check("a countable objective gets a ring that fills to its progress, and no bar", #fills == 1 and math.abs(fills[1] - 1 / 6) < 1e-9 and bars == 0)
	end
	do
		local addon = island_world()
		local metrics = addon.island_scroll.metrics
		check("a list that fits has no scroll bar", metrics(100, 100, 0) == nil and metrics(100, 40, 0) == nil)
		local top, bottom = metrics(100, 300, 0), metrics(100, 300, 200)
		check("the thumb is a third of the track for a list three times as long", top.thumb == 33 and top.travel == 67 and top.at == 0)
		check("scrolled to the end the thumb rests at the bottom of the track", bottom.at == 67)
		check("a very long list keeps a thumb you can grab", metrics(100, 100000, 0).thumb == 24)
	end
	do
		local addon, env, _, state, _, _, frames = quest_world()
		state.quests[2].objectives = {
			{ text = "0/1 Stoneanvil's Rifle", numFulfilled = 0, numRequired = 1, finished = false },
			{ text = "Wolves slain", numFulfilled = 2, numRequired = 5, finished = false },
		}
		addon.module.set("smart_island", "quest_context", true)
		env.everlook_smart_island_key("down")
		local texts = {}
		for _, frame in ipairs(frames) do
			for _, region in ipairs(frame.regions or {}) do
				if type(region.text) == "string" and region.shown ~= false then texts[#texts + 1] = region.text end
			end
		end
		local joined = "\n" .. table.concat(texts, "\n") .. "\n"
		check("an objective that already shows its count does not repeat it", joined:find("\n0/1 Stoneanvil's Rifle\n", 1, true) ~= nil)
		check("one that does not gets the count added", joined:find("\nWolves slain  2/5\n", 1, true) ~= nil)
	end
	do
		local addon, env, _, _, _, _, frames = quest_world()
		local shown = {}
		env.GameTooltip = {
			SetOwner = function() end, Show = function() end, Hide = function() end,
			SetText = function(_, text) shown[#shown + 1] = text end,
		}
		addon.module.set("smart_island", "quest_context", true)
		addon.module.set("smart_island", "hover_preview", false)
		local island_frame
		for _, candidate in ipairs(frames) do if candidate.name == "EverlookSmartIsland" then island_frame = candidate end end
		island_frame.scripts.OnEnter(island_frame)
		local while_closed = #shown
		island_frame.scripts.OnLeave(island_frame)
		env.everlook_smart_island_key("down")
		island_frame.scripts.OnEnter(island_frame)
		check("the closed pill tooltips the quest and the open island does not", while_closed == 1 and #shown == 1)
	end
	do
		local addon, env, event, state = island_world()
		local server = 2000000
		env.GetServerTime = function() return server end
		env.UnitGUID = function() return "Player-1-00000003" end
		env.GetXPExhaustion = function() return 0 end
		addon.module.set("smart_island", "enabled", true)
		addon.module.set("smart_island", "feed_experience", true)
		local experience = addon.island_experience
		event("PLAYER_ENTERING_WORLD")
		state.xp = state.xp + 120
		event("PLAYER_XP_UPDATE")
		local data = experience.table()
		check("the experience table starts with a total row for hour and day", data and data.rows[1][1] == "Total"
			and data.rows[1][2] == "120" and data.rows[1][3] == "120")
		check("an unlabeled gain shows as Other", data.rows[2] and data.rows[2][1] == "Other" and data.rows[2][2] == "120")
		check("slices with nothing in them stay out", #data.rows == 2)
		check("the footer carries rested and pace", type(data.footer) == "string" and data.footer:find("rested", 1, true) ~= nil)
	end
	do
		local addon = island_world()
		check("the edges are top and bottom", table.concat(addon.island_rim.edges, ",") == "top,bottom")
	end
	do
		local addon, env, _, state, _, _, frames = quest_world()
		table.insert(state.quests, 1, { isHeader = true, title = "Elwynn Forest" })
		addon.module.set("smart_island", "quest_context", true)
		addon.module.set("smart_island", "quest_plan", true)
		env.everlook_smart_island_key("down")
		local texts = {}
		for _, frame in ipairs(frames) do
			for _, region in ipairs(frame.regions or {}) do
				if type(region.text) == "string" and region.shown ~= false then texts[#texts + 1] = region.text end
			end
		end
		local joined = "\n" .. table.concat(texts, "\n") .. "\n"
		check("the route lists three quests after the current one",
			joined:find("\n1. Suitable farther\n", 1, true) and joined:find("\n2. Nearby dangerous\n", 1, true)
			and joined:find("\n3. Across the sea\n", 1, true) and not joined:find("4. ", 1, true))
		check("each says where it is: the zone from the log and the distance", joined:find("\nElwynn Forest, ~800 yd\n", 1, true) ~= nil)
		check("a row stays at two lines and leaves its reasoning to the tooltip", joined:find("Why:", 1, true) == nil)
		local tips = {}
		env.GameTooltip = { SetOwner = function() end, SetText = function(_, text) tips[#tips + 1] = text end, Show = function() end, Hide = function() end }
		for _, frame in ipairs(frames) do
			if frame.scripts and frame.scripts.OnEnter then frame.scripts.OnEnter(frame) end
		end
		local tooltips = table.concat(tips, "\n")
		check("the tooltip says why it was chosen", tooltips:find("Why: closest to you; level 18, 6 above you", 1, true) ~= nil
			and tooltips:find("Why: level 12, close to yours", 1, true) ~= nil)
	end
	do
		local addon, _, _, _, _, _, frames = quest_world()
		addon.module.set("smart_island", "quest_context", true)
		local function label(text)
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions or {}) do
					if region.text == text and region.shown ~= false then return region end
				end
			end
		end
		check("the quest capsule carries the level as a badge, in white", label("|cfff5f7fa12|r") ~= nil)
		local plain_width = addon.smart_island.view().width
		addon.module.set("smart_island", "closed_xp", true)
		check("and the experience percent in the bar's purple when the pill shows it", label("|cfff5f7fa12|r  |cffad76ef45%|r") ~= nil)
		check("the capsule grows to make room", addon.smart_island.view().width > plain_width)
	end
	do
		local addon, _, _, _, _, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		local function accents()
			local found = {}
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions or {}) do
					if region.width == 3 and region.shown == true and region.color and region.color[4] == 1 and region.height and region.height >= 4 then
						found[#found + 1] = region.color
					end
				end
			end
			return found
		end
		addon.island.notify({ source = "Test", key = "plain", text = "Plain" })
		check("an info toast has no severity bar", #accents() == 0)
		addon.island.notify({ source = "Test", key = "careful", text = "Careful", severity = "warning" })
		local bars = accents()
		check("a warning toast has a bar in the warning colour", #bars == 1 and bars[1][1] == 1 and bars[1][2] == 0.83)
	end
	do
		local addon, env, event, state, _, _, frames = island_world()
		env.GetServerTime = function() return 3000000 end
		env.UnitGUID = function() return "Player-1-00000004" end
		addon.module.set("smart_island", "enabled", true)
		addon.module.set("smart_island", "feed_experience", true)
		event("PLAYER_ENTERING_WORLD")
		state.xp = state.xp + 90
		event("PLAYER_XP_UPDATE")
		env.everlook_smart_island_key("down")
		local function text_of(match)
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions or {}) do
					if type(region.text) == "string" and region.text:find(match, 1, true) and region.shown ~= false then return region.text end
				end
			end
		end
		check("experience starts folded to its Total row", text_of("> EXPERIENCE") and text_of("Total") and not text_of("Other"))
		check("a click on the heading opens the slices", addon.smart_island.toggle_experience() == true
			and text_of("v EXPERIENCE") and text_of("Other"))
		check("and another folds them again", addon.smart_island.toggle_experience() == false and not text_of("Other") and text_of("> EXPERIENCE"))
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		local function has(text)
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions or {}) do
					if region.text == text and region.shown ~= false then return true end
				end
			end
			return false
		end
		addon.island.notify({ source = "everlook.buffs", key = "own", text = "Own warning", severity = "warning" })
		check("an Everlook warning toast names its severity and not its source", has("Warning") and not has("Warning, Everlook"))
		addon.island.notify({ source = "OtherAddon", key = "foreign", text = "Their warning", severity = "warning" })
		check("another addon's toast names its source", has("Warning, OtherAddon"))
	end
	do
		local addon, _, _, _, _, _, frames = quest_world()
		addon.module.set("smart_island", "quest_context", true)
		addon.module.set("smart_island", "closed_xp", true)
		local function badge_point()
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions or {}) do
					if region.text == "|cfff5f7fa12|r  |cffad76ef45%|r" and region.shown ~= false then return region.point end
				end
			end
		end
		local quiet_offset = badge_point()[4]
		addon.island.notify({ source = "Test", key = "unread", text = "Something new" })
		check("an unread count moves the capsule badge left to clear it", badge_point()[4] < quiet_offset)
	end
	do
		local addon, env, _, state, afters, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		addon.island.notify({ source = "Test", key = "hovered", text = "Stay", duration = 4,
			actions = { { id = "go", label = "Go", type = "callback", on_click = function() end } } })
		local card
		for _, frame in ipairs(frames) do if frame.bound_entry and frame.scripts.OnMouseUp then card = frame end end
		check("a toast with buttons keeps its left clicks", card and card.pass_through ~= nil and #card.pass_through == 0)
		state.time = state.time + 3
		card.scripts.OnEnter(card)
		for _, after in ipairs(afters) do if not after.done then after.done = true; after.callback() end end
		check("a hovered toast does not close when its clock runs out", #addon.smart_island.view().toasts == 1)
		state.time = state.time + 60
		card.scripts.OnLeave(card)
		local restarted
		for _, after in ipairs(afters) do if not after.done then restarted = after.delay end end
		check("leaving it restarts the full time", restarted == 4)
	end
	do
		local addon, env, _, state = island_world()
		env.GetXPExhaustion = function() return 250 end
		env.C_Container.GetContainerNumSlots = function(bag) return bag <= 1 and 20 or 0 end
		addon.module.set("smart_island", "enabled", true)
		env.everlook_smart_island_key("down")
		local rim = addon.smart_island.view().rim
		check("the top bar tracks experience", rim.top == 0.45)
		check("the bottom bar has no quest to track yet", rim.bottom == nil)
		addon.module.set("smart_island", "rim_top", "rested")
		check("an edge can track rested experience instead", addon.smart_island.view().rim.top == 0.25)
		addon.module.set("smart_island", "rim_bottom", "bags")
		check("an edge can track free bag space", addon.smart_island.view().rim.bottom == 8 / 40)
		addon.module.set("smart_island", "rim_bottom", "durability")
		check("or gear durability", addon.smart_island.view().rim.bottom == 0.5)
		addon.module.set("smart_island", "rim_bottom", "none")
		check("an edge set to Nothing is empty", addon.smart_island.view().rim.bottom == nil)
		check("an unknown choice is refused", not pcall(addon.module.set, "smart_island", "rim_top", "mana"))
		check("the side bars are gone", not pcall(addon.module.set, "smart_island", "rim_left", "none"))
	end
	do
		local addon, env, _, state = quest_world()
		addon.module.set("smart_island", "quest_context", true)
		env.everlook_smart_island_key("down")
		check("the bottom bar tracks the current quest's objectives", addon.smart_island.view().rim.bottom == 1 / 6)
	end
	do
		local addon = island_world()
		addon.module.set("smart_island", "enabled", true)
		local closed = addon.smart_island.view()
		check("the closed pill has room for the top and bottom bars", addon.island_rim.length(closed.width, closed.height) ~= nil)
	end
	do
		local addon, env, event, state, _, _, frames = island_world()
		env.C_Container.GetContainerNumSlots = function(bag) return bag <= 1 and 20 or 0 end
		addon.module.set("smart_island", "enabled", true)
		env.everlook_smart_island_key("down")
		local function text_of(match)
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions or {}) do
					if type(region.text) == "string" and region.text:find(match, 1, true) and region.shown ~= false then return region.text end
				end
			end
		end
		local function swipes()
			local colors = {}
			for _, frame in ipairs(frames) do
				if frame.swipe_color and frame.shown == true then colors[#colors + 1] = frame.swipe_color end
			end
			return colors
		end
		check("a healthy figure is plain white, not green: colour is for attention",
			text_of("50%") == "50%" and not text_of("|cff80e6a6"))
		check("bags read as free of the total, with the total set back in the dimmer grey",
			text_of("8 free") == "8 free |cff8891a0of 40|r")
		for _, color in ipairs(swipes()) do check("a healthy ring is the neutral grey", color[1] < 0.75) end
		state.slots[1] = { 10, 50 }
		event("UPDATE_INVENTORY_DURABILITY")
		check("a low figure takes the warning yellow", text_of("|cffffd46620%|r") ~= nil)
		local warned = false
		for _, color in ipairs(swipes()) do if color[1] == 1 and color[2] > 0.8 and color[3] < 0.5 then warned = true end end
		check("and so does its ring", warned)
		state.slots[1] = { 2, 50 }
		event("UPDATE_INVENTORY_DURABILITY")
		check("a dire one takes the error red", text_of("|cffff80804%|r") ~= nil)
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		env.C_Container.GetContainerNumSlots = function(bag) return bag <= 1 and 20 or 0 end
		addon.module.set("smart_island", "enabled", true)
		env.everlook_smart_island_key("down")
		local function rings()
			local count = 0
			for _, frame in ipairs(frames) do
				if frame.cooldown and frame.shown == true then count = count + 1 end
			end
			return count
		end
		check("gear and bags each carry a ring", rings() == 2)
		addon.module.set("smart_island", "rim_bottom", "bags")
		check("a figure on an edge bar keeps its ring, since the cell is where its number is", rings() == 2)
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		addon.module.set("smart_island", "rim_top", "experience")
		local function marks()
			local found = 0
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions or {}) do
					if region.path == "Interface\\Icons\\XP_Icon" and region.shown == true then found = found + 1 end
				end
			end
			return found
		end
		check("the closed pill has no corner mark", marks() == 0)
		env.everlook_smart_island_key("down")
		check("the open island has none either, so nothing sits on the level text", marks() == 0)
	end
	do
		local addon, _, _, state, afters, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		local island_frame
		for _, candidate in ipairs(frames) do if candidate.name == "EverlookSmartIsland" then island_frame = candidate end end
		local over = true
		island_frame.IsMouseOver = function() return over end
		island_frame.scripts.OnEnter(island_frame)
		check("hovering opens the island", addon.smart_island.view().mode == "open")
		island_frame.scripts.OnLeave(island_frame)
		local function fire_pending()
			for _, after in ipairs(afters) do
				if not after.done and after.delay == 0.1 then after.done = true; after.callback(); return true end
			end
		end
		fire_pending()
		check("moving onto a control inside the island does not close it", addon.smart_island.view().mode == "open")
		fire_pending()
		check("and it keeps checking while the pointer stays inside", addon.smart_island.view().mode == "open")
		over = false
		fire_pending()
		check("it closes once the pointer is really outside", addon.smart_island.view().mode == "closed")
	end
	do
		local addon, env, event, state, _, _, frames = quest_world()
		env.QuestMapFrame_OpenToQuestDetails = function() end
		env.GetXPExhaustion = function() return 0 end
		env.GetServerTime = function() return 4000000 end
		env.UnitGUID = function() return "Player-1-00000005" end
		addon.module.set("smart_island", "quest_context", true)
		addon.module.set("smart_island", "quest_plan", true)
		addon.module.set("smart_island", "feed_quest_ready", true)
		addon.module.set("smart_island", "feed_experience", true)
		for index = 1, 4 do
			addon.island.notify({ source = "Test", key = "row" .. index, text = "Row " .. index, persist = index == 1,
				actions = { { id = "act", label = "Act", type = "callback", on_click = function() end } } })
		end
		state.xp = state.xp + 100
		event("PLAYER_XP_UPDATE")
		env.everlook_smart_island_key("down")
		local clicked, failed = 0, {}
		local list = {}
		for _, frame in ipairs(frames) do
			if frame.scripts.OnClick and frame.shown ~= false then list[#list + 1] = frame end
		end
		for _, frame in ipairs(list) do
			for _, button in ipairs({ "LeftButton", "RightButton" }) do
				local ok, err = pcall(frame.scripts.OnClick, frame, button)
				clicked = clicked + 1
				if not ok then failed[#failed + 1] = tostring(frame.name or "?") .. ": " .. tostring(err) end
			end
		end
		check("there are buttons to click in a full island", #list >= 8)
		check("every button in a full island answers both clicks without an error", #failed == 0)
		if #failed > 0 then print(table.concat(failed, "\n")) end
	end
	do
		local addon, _, _, state, _, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		local island_frame
		for _, candidate in ipairs(frames) do if candidate.name == "EverlookSmartIsland" then island_frame = candidate end end
		island_frame.scripts.OnClick(island_frame)
		check("a click pins the island open", addon.smart_island.view().pinned == true)
		local cell
		for _, frame in ipairs(frames) do
			for _, region in ipairs(frame.regions or {}) do
				if region.text == "Money" then cell = region.parent and region.parent.parent end
			end
		end
		state.time = state.time + 1
		cell.scripts.OnClick(cell)
		check("a click on a gauge cell does what a click beside it does", addon.smart_island.view().pinned == false)
	end
	do
		local addon, _, _, _, _, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		local api = addon.island
		local function button(label)
			for _, frame in ipairs(frames) do
				if frame.action_id and frame.label and frame.label.text == label and frame.shown ~= false then return frame end
			end
		end
		local handle = api.notify({ source = "Test", text = "Plain" })
		check("a notice made without a key can still be updated", api.update(handle, { text = "Changed", detail = "More" }) == handle)
		local view = addon.smart_island.view()
		check("an update changes the notice in place", #view.notices == 1 and view.notices[1].text == "Changed" and view.notices[1].detail == "More")
		local clicks = 0
		check("set_actions puts buttons on a showing notice", api.set_actions(handle, {
			{ id = "go", label = "Go", type = "callback", on_click = function() clicks = clicks + 1 end } }) == handle)
		check("the buttons appear and answer clicks", button("Go") ~= nil and (function()
			local go = button("Go"); go.scripts.OnClick(go, "LeftButton"); return clicks == 1 end)())
		check("a notice with buttons now defaults to the buttons interaction", addon.smart_island.view().notices[1].interaction == "buttons")
		check("set_action_enabled greys a button out", api.set_action_enabled(handle, "go", false) == true
			and addon.smart_island.view().notices[1].actions[1].enabled == false)
		local go = button("Go")
		go.scripts.OnClick(go, "LeftButton")
		check("a disabled button does not run", clicks == 1)
		check("and turning it on again lets it run", api.set_action_enabled(handle, "go", true) == true and (function()
			local again = button("Go"); again.scripts.OnClick(again, "LeftButton"); return clicks == 2 end)())
		check("setting the same state again reports no change", api.set_action_enabled(handle, "go", true) == false)
		check("an empty list clears the buttons", api.set_actions(handle, {}) == handle
			and #addon.smart_island.view().notices[1].actions == 0 and addon.smart_island.view().notices[1].interaction == nil)
		local _, reason = api.update(handle, { key = "other" })
		check("the key cannot be changed", reason == "invalid_update")
		_, reason = api.update(handle, { source = "Elsewhere" })
		check("nor the source", reason == "invalid_update")
		_, reason = api.update(9999, { text = "Nobody" })
		check("an unknown handle is named", reason == "unknown_handle")
		_, reason = api.update(handle, { text = "  " })
		check("an update goes through the same checks as a new notice", reason == "invalid_text")
		_, reason = api.set_action_enabled(handle, "missing", false)
		check("an unknown action is named", reason == "unknown_action")
		api.set_actions(handle, { { id = "go", label = "Go", type = "callback", on_click = function() end } })
		_, reason = api.set_action_enabled(handle, "go", "no")
		check("the enabled state must be a boolean", reason == "invalid_enabled")
	end
	do
		local addon, env, _, state = quest_world()
		local positions = { [21] = { 0.1, 0.1 }, [22] = { 0.9, 0.9 }, [23] = { 0.12, 0.1 }, [24] = { 0.5, 0.5 } }
		env.C_Map = env.C_Map or {}
		env.C_Map.GetBestMapForUnit = function() return 37 end
		env.C_Map.GetWorldPosFromMapPos = function(_, point) return 0, { x = point.x * 1000, y = point.y * 1000 } end
		env.C_QuestLog.GetNextWaypoint = function(quest_id)
			local at = positions[quest_id]
			return 37, at[1], at[2]
		end
		addon.module.set("smart_island", "quest_context", true)
		addon.module.set("smart_island", "quest_plan", true)
		local quests = addon.island_quests
		local view = quests.view()
		check("with no pin the island shows the best guess", view.reason == "Suggested" and view.current.id == 23)
		local route, from_pin = quests.route(view)
		check("with no pin the route follows the player's location", from_pin == false and #route == 3 and route[1].id == 22)
		addon.smart_island.pin_quest(22)
		view = quests.view()
		check("a pinned quest is always the one shown", view.reason == "Pinned" and view.current.id == 22)
		route, from_pin = quests.route(view)
		local ids = {}
		for _, record in ipairs(route) do ids[#ids + 1] = record.id end
		check("with a pin the route builds out from the pinned quest", from_pin == true and table.concat(ids, ",") == "24,23,21")
		check("each stop says how far it is from the pin", route[1].from_pin and math.floor(route[1].from_pin) == 565
			and quests.why(route[1]):find("yd from your pinned quest", 1, true) ~= nil)
		addon.smart_island.pin_quest(nil)
		_, from_pin = quests.route(quests.view())
		check("releasing the pin returns the route to the player's location", from_pin == false)
	end
	do
		local addon, env, event, state, _, _, frames = quest_world()
		addon.module.set("smart_island", "quest_context", true)
		addon.module.set("smart_island", "quest_plan", true)
		local function suggestion() return notice_key(addon, "pin-suggest") end
		local function button(label)
			for _, frame in ipairs(frames) do
				if frame.action_id and frame.label and frame.label.text == label and frame.shown ~= false then return frame end
			end
		end
		check("pin suggestions start on", addon.module.get("smart_island", "feed_pin_suggest") == true)
		check("nothing is suggested before anything happens", suggestion() == nil)
		table.insert(state.quests, { questID = 25, title = "A fresh errand", level = 12, distance = 40,
			objectives = { { text = "Fetch", numFulfilled = 0, numRequired = 3, finished = false } } })
		state.time = state.time + 100
		event("QUEST_ACCEPTED", 25)
		event("QUEST_LOG_UPDATE")
		check("accepting a quest offers to pin it", suggestion() and suggestion().text == "Pin A fresh errand?"
			and suggestion().detail:find("New quest", 1, true) ~= nil and #suggestion().actions == 2)
		button("Pin").scripts.OnClick(button("Pin"), "LeftButton")
		check("the Pin button pins that quest", addon.island_quests.pinned_id() == 25)
		check("and clears the offer", suggestion() == nil)
		state.quests[1].objectives[1].numFulfilled = 3
		state.time = state.time + 5
		event("QUEST_LOG_UPDATE")
		check("a second offer inside a minute waits", suggestion() == nil)
		state.time = state.time + 120
		state.quests[2].objectives[1].numFulfilled = 4
		event("QUEST_LOG_UPDATE")
		check("progress on a quest that is not pinned offers to pin it later",
			suggestion() and suggestion().detail:find("making progress", 1, true) ~= nil)
		state.time = state.time + 120
		table.remove(state.quests, #state.quests)
		event("QUEST_LOG_UPDATE")
		check("finishing the pinned quest offers the next best one",
			suggestion() and suggestion().detail:find("Your pinned quest is done", 1, true) ~= nil and addon.island_quests.pinned_id() == nil)
	end
end
