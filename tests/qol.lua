return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)
	local function load_qol(left_out)
		left_out = left_out or {}
		local addon = { say = function() end }
		local frames, callbacks, hooks, tickers = {}, {}, {}, {}
		local env = setmetatable({}, { __index = _G })
		env._G = env
		-- world.lua shares the namespace as the global Everlook.
		env.Everlook = addon
		env.EverlookDB = {}
		env.IsShiftKeyDown = function() return false end
		env.CreateColor = function(red, green, blue, alpha) return { r = red, g = green, b = blue, a = alpha } end
		env.InCombatLockdown = function() return false end
		env.EventUtil = {
			ContinueOnAddOnLoaded = function(_, callback) callbacks[#callbacks + 1] = callback end,
			ContinueOnPlayerLogin = function() end,
		}
		env.C_Timer = {
			After = function(_, callback) callback() end,
			NewTicker = function(_, callback)
				local ticker = { callback = callback, Cancel = function(self) self.cancelled = true end }
				tickers[#tickers + 1] = ticker
				return ticker
			end,
		}
		env.hooksecurefunc = function(target, method, callback)
			if type(target) ~= "table" then hooks[target] = method; return end
			local original = target[method]
			target[method] = function(self, ...)
				original(self, ...)
				callback(self, ...)
			end
		end
		env.CreateFrame = function(_, name, parent, template)
			local frame = { events = {}, scripts = {}, shown = true, name = name, parent = parent, template = template, attributes = {}, regions = {} }
			function frame:SetAttribute(key, value) self.attributes[key] = value end
			function frame:GetAttribute(key) return self.attributes[key] end
			function frame:RegisterForClicks(...) self.clicks = { ... } end
			function frame:EnableMouse(enabled) self.mouse = enabled end
			function frame:SetPassThroughButtons(...) self.pass_through = { ... } end
			function frame:EnableMouseWheel(enabled) self.mouse_wheel = enabled end
			function frame:SetScrollChild(child) self.scroll_child = child end
			function frame:SetVerticalScroll(offset) self.scroll_offset = offset end
			function frame:SetEnabled(enabled) self.enabled = enabled end
			-- A ring is a cooldown held at a percentage: started that share of 100 seconds ago.
			function frame:SetCooldown(start, duration) self.cooldown = { start = start, duration = duration } end
			function frame:SetSwipeColor(...) self.swipe_color = { ... } end
			function frame:Pause() self.paused = true end
			function frame:SetAlpha(alpha) self.alpha = alpha end
			function frame:RegisterEvent(event) self.events[event] = true; return true end
			function frame:UnregisterEvent(event) self.events[event] = nil end
			function frame:SetScript(name, callback) self.scripts[name] = callback end
			function frame:SetSize(width, height) self.width, self.height = width, height end
			function frame:SetScale(scale) self.scale = scale end
			function frame:SetWidth(width) self.width = width end
			function frame:SetHeight(height) self.height = height end
			function frame:GetWidth() return self.width end
			function frame:GetHeight() return self.height end
			function frame:SetHitRectInsets(...) self.hit_insets = { ... } end
			function frame:SetPoint(...) self.point = { ... } end
			function frame:ClearAllPoints() self.point = nil end
			function frame:SetFrameStrata() end
			function frame:SetFrameLevel() end
			function frame:SetClampedToScreen() end
			function frame:SetClipsChildren(enabled) self.clips = enabled and true or false end
			function frame:SetAllPoints(target) self.all_points = target or true end
			function frame:SetMinMaxValues(min_value, max_value) self.min, self.max = min_value, max_value end
			function frame:SetValue(value) self.value = value end
			function frame:SetStatusBarColor() end
			function frame:SetStatusBarTexture(texture) self.status_texture = texture end
			function frame:Hide() self.shown = false end
			function frame:Show() self.shown = true end
			function frame:CreateTexture()
				local texture = {
					SetAllPoints = function() end, SetColorTexture = function(self, ...) self.color = { ... } end,
					SetTexture = function(self, path) self.path = path end, SetTexCoord = function() end,
					SetAtlas = function(self, atlas) self.atlas = atlas end,
					SetVertexColor = function(self, ...) self.color = { ... } end,
					SetGradient = function(self, orientation, low, high) self.gradient = { orientation = orientation, low = low, high = high } end,
					SetPoint = function(self, ...) self.point = { ... } end, ClearAllPoints = function() end,
					SetSize = function(self, width, height) self.width, self.height = width, height end,
					SetRotation = function(self, radians) self.rotation = radians end,
					Show = function(self) self.shown = true end, Hide = function(self) self.shown = false end,
				}
				self.regions[#self.regions + 1] = texture
				return texture
			end
			function frame:CreateAnimationGroup()
				local group = { animations = {}, scripts = {} }
				self.animation_groups = self.animation_groups or {}
				self.animation_groups[#self.animation_groups + 1] = group
				function group:SetScript(name, callback) self.scripts[name] = callback end
				function group:SetToFinalAlpha() end
				function group:Stop() self.playing = false end
				function group:Play()
					self.playing = true
					for _, animation in ipairs(self.animations) do animation.progress = 0 end
				end
				function group:CreateAnimation(kind)
					local animation = { kind = kind, progress = 0 }
					function animation:SetOffset(x, y) self.x, self.y = x, y end
					function animation:SetFromAlpha(value) self.from = value end
					function animation:SetToAlpha(value) self.to = value end
					function animation:SetDuration(value) self.duration = value end
					function animation:SetSmoothing(value) self.smoothing = value end
					function animation:SetTarget(target) self.target = target end
					function animation:GetSmoothProgress() return self.progress end
					self.animations[#self.animations + 1] = animation
					return animation
				end
				return group
			end
			function frame:CreateFontString(_, _, font)
				local label = {
					font = font, parent = self,
					SetPoint = function(self, ...) self.point = { ... } end, ClearAllPoints = function() end,
					SetJustifyH = function() end, SetWordWrap = function(self, enabled) self.wrap = enabled end,
					SetText = function(self, text) self.text = text end,
					SetWidth = function(self, width) self.width = width end, SetHeight = function(self, height) self.height = height end,
					SetTextColor = function(self, ...) self.color = { ... } end, SetSpacing = function(self, spacing) self.spacing = spacing end,
					SetMaxLines = function(self, lines) self.max_lines = lines end, GetLineHeight = function() return 14 end,
					GetStringWidth = function(self) return #(self.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "OO") * 7 end,
					SetNonSpaceWrap = function() end,
					GetStringHeight = function(self)
						local lines = self.wrap and math.max(1, math.ceil(#(self.text or "") / math.max(1, math.floor((self.width and self.width > 0 and self.width or 300) / 7)))) or 1
						if self.max_lines and self.max_lines > 0 then lines = math.min(lines, self.max_lines) end
						return lines * 14 + (lines - 1) * (self.spacing or 0)
					end,
					Hide = function(self) self.shown = false end, Show = function(self) self.shown = true end,
					SetShown = function(self, value) self.shown = value end,
				}
				self.regions[#self.regions + 1] = label
				return label
			end
			function frame:SetParent(next_parent) self.parent = next_parent end
			local guarded_methods = { "SetAttribute", "SetPoint", "ClearAllPoints", "SetScale", "SetSize", "Hide", "Show", "SetParent", "SetScript" }
			for method_index = 1, #guarded_methods do
				local method = guarded_methods[method_index]
				local original = frame[method]
				frame[method] = function(self, ...)
					if type(self.template) == "string" and self.template:find("Secure", 1, true) and env.InCombatLockdown() then
						error("protected " .. method .. " during combat")
					end
					if original then return original(self, ...) end
				end
			end
			frames[#frames + 1] = frame
			return frame
		end
		for _, file in ipairs({ "links", "module", "quest_interface", "flight_time", "friend_conveniences", "useful_tooltips", "faster_loot", "quest_automation", "auto_repair", "sell_junk", "open_containers", "fonts", "site_links", "hide_clutter", "auto_responses", "chat_tweaks", "map_pins", "coordinates", "quest_levels", "cinematic_skip", "camera", "swing_timers", "unit_names", "npc_titles", "quest_tracker", "mail", "gossip_continue", "tooltip_cursor", "chat_format", "radial_wheel", "radial_menu", "island_quests", "island_actions", "island_capsule", "island_vitals", "island_history", "island_surface", "island_scroll", "island_notice", "island_inbox", "island_toasts", "smart_island", "island_feed_kit", "island_share", "island_quest_notices", "island_loot", "island_hearth", "island_reputation", "island_professions", "island_mail", "island_invites", "island_buffs", "island_recap", "island_experience", "island_warnings", "action_shortcuts" }) do
			if not left_out[file] then
				local chunk = assert(loadfile(source(file)))
				setfenv(chunk, env)
				chunk("Everlook", addon)
			end
		end
		for _, callback in ipairs(callbacks) do callback() end
		local function event(name, ...)
			for _, frame in ipairs(frames) do
				if frame.events[name] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, name, ...) end
			end
		end
		return addon, env, event, hooks, tickers, frames
	end
	local addon, env, event = load_qol()
	check("QoL has thirty independent modules", #addon.module.modules == 30)
	for _, module in ipairs(addon.module.modules) do
		check(module.id .. " starts disabled", not addon.module.enabled(module.id))
	end
	for _, module in ipairs(addon.module.modules) do
		for key, option in pairs(module.options) do
			if option.min then
				local name = module.id .. "." .. key
				local steps = (option.max - option.min) / (option.step or 1)
				check(name .. " has a whole number of steps from its minimum to its maximum", math.abs(steps - math.floor(steps + 0.5)) < 1e-9)
				addon.module.set(module.id, key, option.default)
				check(name .. " has a default on one of its steps", addon.module.get(module.id, key) == option.default)
				for _, preset in pairs(option.presets or {}) do
					addon.module.set(module.id, key, preset)
					check(name .. " has presets on its steps", addon.module.get(module.id, key) == preset)
				end
			end
		end
	end
	do
		local function action_button(text)
			local button = { binding_text = text, HotKey = { text = text } }
			function button.HotKey:GetText() return self.text end
			function button.HotKey:SetText(value) self.text = value end
			function button:UpdateHotkeys() self.HotKey:SetText(self.binding_text) end
			return button
		end
		local shift_button, alt_button = action_button("s-4"), action_button("a-4")
		local manager = { frames = { shift_button, alt_button } }
		function manager:ForEachFrame(callback)
			for _, button in ipairs(self.frames) do callback(button) end
		end
		function manager:RegisterFrame(button) self.frames[#self.frames + 1] = button end
		env.ActionBarButtonEventsFrame = manager
		check("action shortcuts keep Blizzard labels while disabled", shift_button.HotKey.text == "s-4" and alt_button.HotKey.text == "a-4")
		addon.module.set("action_shortcuts", "enabled", true)
		check("action shortcuts show Shift and Alt without a dash", shift_button.HotKey.text == "S4" and alt_button.HotKey.text == "A4")
		event("PLAYER_ENTERING_WORLD")
		shift_button.binding_text = "a-7"
		shift_button:UpdateHotkeys()
		check("native binding refreshes keep compact shortcuts", shift_button.HotKey.text == "A7")
		local combined_button = action_button("s-a-4")
		manager:RegisterFrame(combined_button)
		combined_button:UpdateHotkeys()
		check("new action buttons get combined modifier shortcuts", combined_button.HotKey.text == "SA4")
		for _, pair in ipairs({ { "4", "4" }, { "F4", "F4" }, { "s-F4", "SF4" }, { "a--", "A-" }, { "a-s-4", "AS4" }, { "c-4", "c-4" }, { "", "" }, { "•", "•" } }) do
			alt_button.binding_text = pair[1]
			alt_button:UpdateHotkeys()
			check("action shortcuts preserve the key in " .. pair[1], alt_button.HotKey.text == pair[2])
		end
		env.issecretvalue = function(value) return value == "s-9" end
		alt_button.binding_text = "s-9"
		alt_button:UpdateHotkeys()
		check("secret shortcut labels stay unchanged", alt_button.HotKey.text == "s-9")
		env.issecretvalue = nil
		combined_button.HotKey:SetText("Other addon")
		addon.module.set("action_shortcuts", "enabled", false)
		check("disabling restores the latest native label", shift_button.HotKey.text == "a-7")
		check("disabling preserves a later external label", combined_button.HotKey.text == "Other addon")
		shift_button.binding_text = "s-5"
		shift_button:UpdateHotkeys()
		check("disabled hooks leave native shortcut refreshes alone", shift_button.HotKey.text == "s-5")
		local late_addon, late_env, late_event = load_qol()
		late_addon.module.set("action_shortcuts", "enabled", true)
		local late_button = action_button("a-4")
		late_env.ActionBarButtonEventsFrame = { ForEachFrame = function(_, callback) callback(late_button) end, RegisterFrame = function() end }
		late_event("ADDON_LOADED", "Blizzard_ActionBar")
		check("action bars loaded after Everlook get compact shortcuts", late_button.HotKey.text == "A4")
	end
	local scale_setting = 7
	env.Enum = env.Enum or {}
	env.Enum.EditModeSwingTimerSetting = { Scale = scale_setting }
	local function swing_bar(percent)
		local frame = {
			percent = percent, scale = percent / 100, initialized = true,
			systemInfo = { settings = { { setting = scale_setting, value = (percent - 50) / 10 } } },
			settingMap = { [scale_setting] = { value = (percent - 50) / 10, displayValue = percent } },
		}
		function frame:IsInitialized() return self.initialized end
		function frame:HasSetting(setting) return setting == scale_setting end
		function frame:UpdateSystem(value)
			self.initialized = true
			self.percent = value
			self.systemInfo.settings[1].value = (value - 50) / 10
			self.settingMap[scale_setting] = { value = (value - 50) / 10, displayValue = value }
			self:UpdateSystemSettingScale()
		end
		function frame:GetSettingValue(setting)
			if setting == scale_setting then return self.settingMap[setting].displayValue end
			return 0
		end
		function frame:UpdateSystemSettingValue(setting, value)
			self.dirtied = true
			if setting ~= scale_setting then return end
			self.percent = value
			self.systemInfo.settings[1].value = (value - 50) / 10
			self.settingMap[scale_setting] = { value = (value - 50) / 10, displayValue = value }
			self:UpdateSystemSettingScale()
		end
		function frame:UpdateSystemSettingScale()
			self:SetScale(self:GetSettingValue(scale_setting) / 100)
		end
		function frame:SetScale(value) self.scale = value end
		function frame:GetScale() return self.scale end
		return frame
	end
	env.SwingTimerMainHandFrame = swing_bar(100)
	env.SwingTimerOffHandFrame = swing_bar(80)
	env.SwingTimerRangedFrame = swing_bar(120)
	check("swing timers keep their edit mode scale while the module is off",
		env.SwingTimerMainHandFrame.scale == 1 and env.SwingTimerOffHandFrame.scale == 0.8 and env.SwingTimerRangedFrame.scale == 1.2
		and env.SwingTimerMainHandFrame.percent == 100 and addon.module.get("swing_timers", "scale") == 0.5)
	addon.module.set("swing_timers", "scale", 0.6)
	check("the scale does nothing while the module is off", env.SwingTimerMainHandFrame.percent == 100 and env.SwingTimerMainHandFrame.scale == 1)
	addon.module.set("swing_timers", "enabled", true)
	check("enabling swing timers changes the rendered scale without changing Edit Mode",
		env.SwingTimerMainHandFrame.percent == 100 and env.SwingTimerMainHandFrame.scale == 0.6
		and env.SwingTimerOffHandFrame.percent == 80 and env.SwingTimerRangedFrame.scale == 0.6
		and not env.SwingTimerMainHandFrame.dirtied)
	check("swing scaling leaves the shared layout and display setting map untouched",
		env.SwingTimerMainHandFrame.systemInfo.settings[1].value == 5
		and env.SwingTimerMainHandFrame.settingMap[scale_setting].displayValue == 100
		and env.SwingTimerOffHandFrame.systemInfo.settings[1].value == 3)
	addon.module.set("swing_timers", "scale", 0.7)
	check("the scale slider updates the rendered scale", env.SwingTimerRangedFrame.percent == 120 and env.SwingTimerRangedFrame.scale == 0.7)
	env.SwingTimerMainHandFrame:UpdateSystemSettingScale()
	check("an edit mode refresh keeps the saved swing timer scale", env.SwingTimerMainHandFrame.percent == 100 and env.SwingTimerMainHandFrame.scale == 0.7)
	addon.module.set("swing_timers", "scale", 4)
	check("swing timer scale stays inside the slider", addon.module.get("swing_timers", "scale") == 1 and env.SwingTimerOffHandFrame.percent == 80 and env.SwingTimerOffHandFrame.scale == 1)
	addon.module.set("swing_timers", "enabled", false)
	check("turning swing timers off restores each edit mode scale",
		env.SwingTimerMainHandFrame.percent == 100 and env.SwingTimerMainHandFrame.scale == 1
		and env.SwingTimerOffHandFrame.percent == 80 and env.SwingTimerOffHandFrame.scale == 0.8
		and env.SwingTimerRangedFrame.percent == 120 and env.SwingTimerRangedFrame.scale == 1.2)
	env.SwingTimerMainHandFrame:UpdateSystem(90)
	check("edit mode owns the scale while swing timers are off", env.SwingTimerMainHandFrame.scale == 0.9)
	env.SwingTimerOffHandFrame = nil
	addon.module.set("swing_timers", "enabled", true)
	check("a missing swing timer is skipped",
		env.SwingTimerMainHandFrame.percent == 90 and env.SwingTimerMainHandFrame.scale == 1
		and env.SwingTimerRangedFrame.percent == 120 and env.SwingTimerRangedFrame.scale == 1)
	env.SwingTimerMainHandFrame:UpdateSystem(150)
	check("a layout refresh reapplies the enabled swing scale", env.SwingTimerMainHandFrame.percent == 150 and env.SwingTimerMainHandFrame.scale == 1)
	addon.module.set("swing_timers", "enabled", false)
	check("disabling swing scaling restores the new layout rather than the old one", env.SwingTimerMainHandFrame.percent == 150 and env.SwingTimerMainHandFrame.scale == 1.5)
	env.SwingTimerRangedFrame.initialized = false
	addon.module.set("swing_timers", "enabled", true)
	check("an uninitialized swing timer is left alone", env.SwingTimerRangedFrame.percent == 120)
	env.SwingTimerRangedFrame:UpdateSystem(90)
	check("a swing timer that initializes after the addon receives the enabled scale", env.SwingTimerRangedFrame.percent == 90 and env.SwingTimerRangedFrame.scale == 1)
	env.InCombatLockdown = function() return true end
	addon.module.set("swing_timers", "enabled", false)
	check("swing timer restoration waits until combat ends", env.SwingTimerRangedFrame.scale == 1)
	env.InCombatLockdown = function() return false end
	event("PLAYER_REGEN_ENABLED")
	check("swing timers restore after combat", env.SwingTimerRangedFrame.percent == 90 and env.SwingTimerRangedFrame.scale == 0.9)
	addon.module.set("swing_timers", "enabled", true)
	env.SwingTimerRangedFrame:SetScale(0.85)
	addon.module.set("swing_timers", "enabled", false)
	check("disabling swing scaling preserves a later external scale", env.SwingTimerRangedFrame.scale == 0.85)
	function env.SwingTimerRangedFrame:SetScale(value)
		self.scale = value == 0.7 and 0.69999998807907 or value
	end
	addon.module.set("swing_timers", "scale", 0.7)
	addon.module.set("swing_timers", "enabled", true)
	addon.module.set("swing_timers", "enabled", false)
	check("native scale rounding does not prevent restoration", env.SwingTimerRangedFrame.scale == 0.85)
	local accepted, rewards = 0, {}
	env.AcceptQuest = function() accepted = accepted + 1 end
	-- Only names that appear in Blizzard's own code: the quest frame asks
	-- GetQuestMoneyToGet and C_QuestLog.IsRepeatableQuest(GetQuestID()).
	env.GetQuestID = function() return 1 end
	env.GetQuestMoneyToGet = function() return 0 end
	env.C_QuestLog = { IsRepeatableQuest = function() return false end }
	env.GetNumQuestChoices = function() return 2 end
	env.GetQuestReward = function(choice) rewards[#rewards + 1] = choice end
	event("QUEST_DETAIL")
	check("disabled quest automation does nothing", accepted == 0)
	addon.module.set("quest_automation", "enabled", true)
	event("QUEST_DETAIL")
	event("QUEST_COMPLETE")
	check("quest automation accepts quests", accepted == 1)
	check("quest automation preserves reward choice", #rewards == 0)
	env.GetNumQuestChoices = function() return 1 end
	event("QUEST_COMPLETE")
	check("quest automation takes a sole reward", rewards[1] == 1)
	env.IsShiftKeyDown = function() return true end
	event("QUEST_DETAIL")
	check("Shift pauses automation", accepted == 1)
	env.IsShiftKeyDown = function() return false end
	env.GetQuestMoneyToGet = function() return 100 end
	event("QUEST_COMPLETE")
	check("paid quest turn-ins remain manual", #rewards == 1)
	env.GetQuestMoneyToGet = nil
	event("QUEST_COMPLETE")
	check("a quest whose cost is unknown stays manual", #rewards == 1)
	env.GetQuestMoneyToGet = function() return 0 end
	event("QUEST_COMPLETE")
	check("a free quest is turned in again once the cost is known", #rewards == 2)

	env.C_QuestLog.IsRepeatableQuest = function() return true end
	event("QUEST_DETAIL")
	check("repeatable quests require opt-in", accepted == 1)
	addon.module.set("quest_automation", "repeatable", true)
	event("QUEST_DETAIL")
	check("repeatable quests are accepted with the opt-in", accepted == 2)
	addon.module.set("quest_automation", "repeatable", false)
	env.C_QuestLog = nil
	event("QUEST_DETAIL")
	check("a quest that cannot be classified stays manual", accepted == 2)
	env.C_QuestLog = { IsRepeatableQuest = function() return false end }

	local looted = {}
	env.GetNumLootItems = function() return 3 end
	env.GetLootSlotInfo = function(slot) return nil, nil, nil, nil, nil, slot == 2 end
	env.LootSlot = function(slot) looted[#looted + 1] = slot end
	addon.module.set("faster_loot", "enabled", true)
	event("LOOT_OPENED", false)
	check("fast looting respects manual loot", #looted == 0)
	event("LOOT_OPENED", true)
	check("fast looting skips locked slots", #looted == 2 and looted[1] == 3 and looted[2] == 1)

	local invited = 0
	env.GetNormalizedRealmName = function() return "Home" end
	env.C_FriendList = { GetNumFriends = function() return 1 end, GetFriendInfoByIndex = function() return { name = "Alice" } end }
	env.AcceptGroup = function() invited = invited + 1 end
	addon.module.set("friend_conveniences", "enabled", true)
	event("PARTY_INVITE_REQUEST", "Alice-Other")
	event("PARTY_INVITE_REQUEST", "Stranger")
	check("invites from strangers and other realms stay manual", invited == 0)
	event("PARTY_INVITE_REQUEST", "Alice-Home")
	check("friend invites accepted", invited == 1)
	local declined, hidden_popups = 0, {}
	env.DeclineGroup = function() declined = declined + 1 end
	env.StaticPopup_Hide = function(which) hidden_popups[#hidden_popups + 1] = which end
	event("PARTY_INVITE_REQUEST", "Stranger")
	check("other invites are left alone unless declining is on", declined == 0)
	addon.module.set("friend_conveniences", "decline_others", true)
	event("PARTY_INVITE_REQUEST", "Stranger")
	check("other invites are declined and the popup closes", declined == 1 and hidden_popups[#hidden_popups] == "PARTY_INVITE")
	event("PARTY_INVITE_REQUEST", "Alice-Home")
	check("a friend is accepted, not declined", declined == 1 and invited == 2)
	env.IsShiftKeyDown = function() return true end
	event("PARTY_INVITE_REQUEST", "Stranger")
	check("Shift pauses declining", declined == 1)
	env.IsShiftKeyDown = function() return false end
	addon.module.set("friend_conveniences", "decline_others", false)

	;(function()
		local real_type = env.type or type
		local secret_name = {}
		env.type = function(value)
			if rawequal(value, secret_name) then return "string" end
			return real_type(value)
		end
		env.issecretvalue = function(value) return rawequal(value, secret_name) end
		local secret_invite = pcall(event, "PARTY_INVITE_REQUEST", secret_name)
		check("a secret invite name does not error or accept", secret_invite and invited == 2)
		env.C_FriendList = {
			GetNumFriends = function() return 2 end,
			GetFriendInfoByIndex = function(index)
				if index == 1 then return { name = secret_name } end
				return { name = "Alice" }
			end,
		}
		local secret_roster = pcall(event, "PARTY_INVITE_REQUEST", "Alice-Home")
		check("a secret friend name does not stop a later friend from matching", secret_roster and invited == 3)
		env.type = nil
		env.issecretvalue = nil
		env.C_FriendList = { GetNumFriends = function() return 1 end, GetFriendInfoByIndex = function() return { name = "Alice" } end }
	end)()

	local repairs = {}
	env.CanMerchantRepair = function() return true end
	env.GetRepairAllCost = function() return 100, true end
	env.GetMoney = function() return 99 end
	env.RepairAllItems = function(guild) repairs[#repairs + 1] = guild end
	addon.module.set("auto_repair", "enabled", true)
	event("MERCHANT_SHOW")
	check("repair requires sufficient funds", #repairs == 0)
	env.GetMoney = function() return 100 end
	event("MERCHANT_SHOW")
	check("personal repair uses available gold", #repairs == 1 and repairs[1] == false)
	env.CanGuildBankRepair = function() return true end
	env.GetGuildBankWithdrawMoney = function() return 50 end
	env.GetGuildBankMoney = function() return 1000 end
	addon.module.set("auto_repair", "guild_funds", true)
	event("MERCHANT_SHOW")
	check("insufficient guild allowance falls back to personal gold", repairs[2] == false)
	env.GetGuildBankWithdrawMoney = function() return -1 end
	event("MERCHANT_SHOW")
	check("unlimited guild allowance permits repair", repairs[3] == true)

	local addon2, env2, event2, hooks, tickers, frames = load_qol()
	local bags = {
		{ itemID = 1, quality = 0, stackCount = 2 },
		{ itemID = 2, quality = 0, stackCount = 1 },
		{ itemID = 3, quality = 1, stackCount = 1 },
		{ itemID = 4, quality = 0, stackCount = 1, isLocked = true },
	}
	local sold, report = {}, nil
	env2.NUM_BAG_SLOTS = 0
	env2.C_Item = {
		GetItemInfo = function()
			return "Junk", nil, 0, 1, 0, "Miscellaneous", "Junk", 20, "", 1, 10, 15, 0, 0, 0, nil, false
		end,
	}
	env2.C_Container = {
		GetContainerNumSlots = function() return 4 end,
		GetContainerItemInfo = function(_, slot) return bags[slot] end,
		UseContainerItem = function(_, slot) sold[#sold + 1] = slot; bags[slot] = nil end,
	}
	addon2.say = function(text) report = text end
	addon2.module.set("sell_junk", "enabled", true)
	event2("MERCHANT_SHOW")
	tickers[1].callback(); tickers[1].callback(); tickers[1].callback()
	check("junk sale skips locked and non-junk items", #sold == 2 and sold[1] == 1 and sold[2] == 2)
	check("junk sale reports confirmed stack proceeds", report and report:find("30 copper", 1, true) and tickers[1].cancelled)
	check("junk selling has no command and no protection list",
		env2.SLASH_EVERLOOKJUNK1 == nil and addon2.sell_junk == nil and env2.EverlookDB.qol.sell_junk.protected == nil)
	bags[1] = { itemID = 5, quality = 0, stackCount = 1 }
	event2("MERCHANT_SHOW")
	event2("MERCHANT_CLOSED")
	tickers[2].callback()
	check("closing vendor cancels queued sales", #sold == 2 and tickers[2].cancelled)

	local addon3, env3, event3, _, tickers3 = load_qol()
	local item_rows = {
		[1] = { name = "Plain Junk", isCraftingReagent = false, classId = 15 },
		[2] = { name = "Letter", startsQuestId = 42, isCraftingReagent = false, classId = 15 },
		[3] = { name = "Thread", isCraftingReagent = true, classId = 7 },
		[4] = { name = "Scroll", teachesSpellId = 99, isCraftingReagent = false, classId = 15 },
		[10] = { id = 10 },
	}
	addon3.world = {
		row = function(bucket, item_id)
			if bucket == "items" then return item_rows[item_id] end
		end,
	}
	local bags3 = {
		{ itemID = 1, quality = 0, stackCount = 1 },
		{ itemID = 2, quality = 0, stackCount = 1 },
		{ itemID = 3, quality = 0, stackCount = 1 },
		{ itemID = 4, quality = 0, stackCount = 1 },
		{ itemID = 5, quality = 0, stackCount = 1 },
		{ itemID = 6, quality = 0, stackCount = 1 },
		{ itemID = 7, quality = 0, stackCount = 1 },
		{ itemID = 8, quality = 0, stackCount = 1 },
		{ itemID = 9, quality = 0, stackCount = 1, questID = 15, isActive = false },
		{ itemID = 10, quality = 0, stackCount = 1 },
	}
	local sold3 = {}
	env3.NUM_BAG_SLOTS = 0
	env3.C_Item = {
		GetItemInfo = function(item_id)
			if item_id == 7 then return nil end
			if item_id == 5 then
				return "Ore", nil, 0, 1, 0, "Tradeskill", "Parts", 20, "", 1, 10, 7, 0, 0, 0, nil, true
			end
			if item_id == 8 then
				return "Recipe", nil, 0, 1, 0, "Recipe", "Book", 1, "", 1, 10, 9, 0, 0, 0, nil, false
			end
			return "Junk", nil, 0, 1, 0, "Miscellaneous", "Junk", 20, "", 1, 10, 15, 0, 0, 0, nil, false
		end,
	}
	env3.C_Container = {
		GetContainerNumSlots = function() return #bags3 end,
		GetContainerItemInfo = function(_, slot) return bags3[slot] end,
		UseContainerItem = function(_, slot)
			sold3[#sold3 + 1] = slot
			bags3[slot] = nil
		end,
	}
	addon3.module.set("sell_junk", "enabled", true)
	event3("MERCHANT_SHOW")
	tickers3[1].callback()
	tickers3[1].callback()
	tickers3[1].callback()
	tickers3[1].callback()
	check("junk sale keeps quest items, recipes, and reagents", sold3[1] == 1 and sold3[2] == 6 and sold3[3] == 10 and #sold3 == 3)

	do
		local function container_world()
			local module, world, event, _, timers = load_qol()
			local bags = {
				{ itemID = 11, stackCount = 2, hasLoot = true },
				{ itemID = 12, stackCount = 1 },
				{ itemID = 13, stackCount = 1, hasLoot = true, isLocked = true },
				{ itemID = 14, stackCount = 1, hasLoot = true },
			}
			local state = { bags = bags, opened = {}, looted = {}, slots = 0, source = "Item-1-0-1", shown = false }
			world.NUM_BAG_SLOTS = 0
			world.C_Container = {
				GetContainerNumSlots = function() return 4 end,
				GetContainerItemInfo = function(_, slot) return bags[slot] end,
				UseContainerItem = function(_, slot) state.opened[#state.opened + 1] = slot end,
			}
			world.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
			world.C_Item = {
				DoesItemExist = function(location) return bags[location.slot] ~= nil end,
				GetItemGUID = function(location)
					assert(bags[location.slot], "an empty slot has no item GUID")
					return "Item-1-0-" .. location.slot
				end,
			}
			world.CursorHasItem = function() return false end
			world.GetCursorInfo = function() end
			world.SpellCanTargetItem = function() return false end
			world.SpellCanTargetItemID = function() return false end
			world.LootFrame = { IsShown = function() return state.shown end }
			world.GetNumLootItems = function() return state.slots end
			world.GetLootSourceInfo = function() return state.source, 1 end
			world.GetLootSlotInfo = function(slot)
				if slot < 1 or slot > state.slots then return end
				return "tex", "Clam", 1, nil, 1, slot == 2
			end
			world.LootSlot = function(slot) state.looted[#state.looted + 1] = slot end
			return module, world, event, timers, state
		end
		local opener, open_env, open_event, open_tickers, container = container_world()
		open_event("BAG_UPDATE_DELAYED")
		check("containers stay closed while the module is off", #container.opened == 0)
		opener.module.set("open_containers", "enabled", true)
		check("a lootable container is opened and a plain item stays closed", container.opened[1] == 1 and #container.opened == 1)
		container.slots = 2
		open_event("LOOT_OPENED", false, true)
		check("the container's loot is taken and a locked slot stays", container.looted[1] == 1 and #container.looted == 1)
		open_event("LOOT_OPENED", false, true)
		check("a loot window the module did not open stays as it is", #container.looted == 1)
		container.slots = 0
		open_env.MerchantFrame = { IsShown = function() return true end }
		open_event("LOOT_CLOSED")
		open_event("BAG_UPDATE_DELAYED")
		check("a merchant does not get the container sold", #container.opened == 1)
		open_env.MerchantFrame.IsShown = function() return false end
		open_env.IsShiftKeyDown = function() return true end
		open_event("MERCHANT_CLOSED")
		check("Shift pauses opening containers", #container.opened == 1)
		open_env.IsShiftKeyDown = function() return false end
		open_env.InCombatLockdown = function() return true end
		open_event("BAG_UPDATE_DELAYED")
		check("combat waits to open a container", #container.opened == 1)
		open_env.InCombatLockdown = function() return false end
		open_event("PLAYER_REGEN_ENABLED")
		check("leaving combat skips the unchanged opened container", container.opened[2] == 4)
		for _ = 1, 3 do open_tickers[#open_tickers].callback() end
		check("a container that does not open is left alone", #container.opened == 2)
		opener.module.set("open_containers", "enabled", false)
		open_event("BAG_UPDATE_DELAYED")
		check("turning container opening off stops it", #container.opened == 2 and open_tickers[#open_tickers].cancelled)

		local foreign, foreign_env, foreign_event, foreign_timers, foreign_state = container_world()
		foreign.module.set("open_containers", "enabled", true)
		foreign_state.slots = 1
		foreign_state.source = "Creature-0-0-0-0-11-1"
		foreign_event("LOOT_OPENED", false, false)
		foreign_timers[1].callback()
		check("a corpse window arriving during an open stays manual", #foreign_state.looted == 0)
		foreign_state.slots = 0
		foreign_event("LOOT_CLOSED")
		foreign_state.slots = 1
		foreign_state.source = "Item-1-0-99"
		foreign_event("LOOT_OPENED", false, true)
		check("a different item's loot is not attributed to the pending container", #foreign_state.looted == 0)

		for _, guard in ipairs({ "IsShiftKeyDown", "InCombatLockdown", "CursorHasItem", "SpellCanTargetItem", "SpellCanTargetItemID" }) do
			local paused, paused_env, paused_event, paused_timers, paused_state = container_world()
			paused.module.set("open_containers", "enabled", true)
			paused_env[guard] = function() return true end
			paused_state.slots = 1
			paused_event("LOOT_OPENED", false, true)
			paused_env[guard] = function() return false end
			paused_timers[1].callback()
			check(guard .. " after opening leaves the loot manual", #paused_state.looted == 0)
		end
		local merchant, merchant_env, merchant_event, _, merchant_state = container_world()
		merchant.module.set("open_containers", "enabled", true)
		merchant_env.MerchantFrame = { IsShown = function() return true end }
		merchant_state.slots = 1
		merchant_event("LOOT_OPENED", false, true)
		check("a merchant opening before the loot arrives pauses taking it", #merchant_state.looted == 0)

		for _, api in ipairs({ "IsShiftKeyDown", "InCombatLockdown", "CursorHasItem", "GetCursorInfo", "SpellCanTargetItem", "SpellCanTargetItemID", "GetNumLootItems", "GetLootSlotInfo", "GetLootSourceInfo", "LootSlot", "ItemLocation", "C_Item", "LootFrame" }) do
			local missing, missing_env, _, _, missing_state = container_world()
			missing_env[api] = false
			missing.module.set("open_containers", "enabled", true)
			check("container opening fails closed without " .. api, #missing_state.opened == 0)
		end
		local unknown, unknown_env, unknown_event, _, unknown_state = container_world()
		unknown.module.set("open_containers", "enabled", true)
		unknown_env.GetLootSourceInfo = function() end
		unknown_state.slots = 1
		unknown_event("LOOT_OPENED", false, true)
		check("loot with no source GUID stays manual", #unknown_state.looted == 0)
		local secret, secret_env, secret_event, _, secret_state = container_world()
		secret.module.set("open_containers", "enabled", true)
		secret_env.issecretvalue = function(value) return value == secret_state.source end
		secret_state.slots = 1
		secret_event("LOOT_OPENED", false, true)
		check("a secret loot source stays manual", #secret_state.looted == 0)
		local unannounced, _, _, unannounced_timers, unannounced_state = container_world()
		unannounced.module.set("open_containers", "enabled", true)
		unannounced_state.slots = 1
		unannounced_timers[1].callback()
		check("the polling timer does not claim an unannounced loot window", #unannounced_state.looted == 0)
		local identical, _, _, identical_timers, identical_state = container_world()
		identical_state.bags[4].itemID = 11
		identical_state.bags[4].stackCount = 2
		identical.module.set("open_containers", "enabled", true)
		for _ = 1, 3 do identical_timers[1].callback() end
		check("an unopened box does not suppress a different stack of the same item", identical_state.opened[2] == 4)
		local removed, _, _, removed_timers, removed_state = container_world()
		removed.module.set("open_containers", "enabled", true)
		removed_state.bags[1] = nil
		removed_timers[1].callback()
		check("an item removed while opening is not queried for a GUID", removed_state.opened[2] == 4)
		local empty, empty_env, _, _, empty_state = container_world()
		empty_state.shown = true
		empty.module.set("open_containers", "enabled", true)
		check("an existing empty loot window prevents opening a container", #empty_state.opened == 0)
		empty_state.shown = false
		empty_env.GetNumLootItems = function() end
		empty.module.set("open_containers", "enabled", true)
		check("an unknown loot count prevents opening a container", #empty_state.opened == 0)
		local money, money_env, _, _, money_state = container_world()
		money_env.GetCursorInfo = function() return "money", 10 end
		money.module.set("open_containers", "enabled", true)
		check("holding money on the cursor pauses container opening", #money_state.opened == 0)
		local mixed, mixed_env, mixed_event, _, mixed_state = container_world()
		mixed.module.set("open_containers", "enabled", true)
		mixed_env.GetLootSourceInfo = function() return mixed_state.source, 1, "Item-1-0-99", 1 end
		mixed_state.slots = 1
		mixed_event("LOOT_OPENED", false, true)
		check("a slot with mixed loot sources stays manual", #mixed_state.looted == 0)
		local closing, closing_env, closing_event, closing_timers, closing_state = container_world()
		closing.module.set("open_containers", "enabled", true)
		closing_env.LootSlot = function(slot)
			closing_state.looted[#closing_state.looted + 1] = slot
			closing_state.slots = 0
			closing_event("LOOT_CLOSED")
		end
		closing_state.slots = 1
		closing_event("LOOT_OPENED", false, true)
		check("loot closing inside LootSlot does not reenter container use", #closing_state.opened == 1 and #closing_state.looted == 1)
		closing_timers[1].callback()
		check("the next container opens after the previous loot call returns", closing_state.opened[2] == 4)
		local interrupted, interrupted_env, interrupted_event, _, interrupted_state = container_world()
		interrupted.module.set("open_containers", "enabled", true)
		interrupted_env.LootSlot = function(slot)
			interrupted_state.looted[#interrupted_state.looted + 1] = slot
			interrupted_env.IsShiftKeyDown = function() return true end
		end
		interrupted_state.slots = 3
		interrupted_event("LOOT_OPENED", false, true)
		check("Shift interrupts taking the remaining loot slots", #interrupted_state.looted == 1 and interrupted_state.looted[1] == 3)
	end

	do
		local titles, title_env, title_event = load_qol()
		local function fontstring()
			local line = { shown = false, points = {} }
			function line:SetFont(path, size, flags) self.path, self.size, self.flags = path, size, flags end
			function line:SetTextColor(r, g, b) self.color = { r, g, b } end
			function line:ClearAllPoints() self.points = {} end
			function line:SetPoint(...) self.points[#self.points + 1] = { ... } end
			function line:SetText(text) self.text = text end
			function line:Show() self.shown = true end
			function line:Hide() self.shown = false end
			return line
		end
		local function plate()
			local name = { points = {} }
			function name:GetFont() return "Fonts\\Plate.ttf", 16, "OUTLINE" end
			function name:GetTextColor() return 0.1, 0.9, 0.2 end
			local created = {}
			local frame = { name = name, CreateFontString = function() local line = fontstring(); created[#created + 1] = line; return line end }
			return { UnitFrame = frame }, created
		end
		local plates, created = {}, {}
		for _, unit in ipairs({ "nameplate1", "nameplate2", "nameplate3", "nameplate4" }) do plates[unit], created[unit] = plate() end
		local tooltips = {
			nameplate1 = { lines = { { leftText = "Thorgrum Borrelson" }, { leftText = "<Gryphon Master>" } } },
			nameplate2 = { lines = { { leftText = "A Player" }, { leftText = "<Some Guild>" } } },
			nameplate3 = { lines = { { leftText = "A Guard" }, { leftText = "<Defender>" } } },
			nameplate4 = { lines = { { leftText = "Plain Villager" }, { leftText = "Level 3 Human (NPC)" } } },
		}
		title_env.C_NamePlate = { GetNamePlateForUnit = function(unit) return plates[unit] end, GetNamePlates = function() return {} end }
		title_env.C_TooltipInfo = { GetUnit = function(unit) return tooltips[unit] end }
		title_env.UnitExists = function() return true end
		title_env.UnitIsPlayer = function(unit) return unit == "nameplate2" end
		title_env.UnitCanAttack = function(_, unit) return unit == "nameplate3" end
		local cvars, set_calls = { nameplateShowFriendlyNpcs = "0", UnitNameNPC = "1", UnitNameFriendlySpecialNPCName = "1" }, {}
		title_env.GetCVar = function(name) return cvars[name] end
		title_env.SetCVar = function(name, value) cvars[name] = value; set_calls[#set_calls + 1] = name end
		title_env.InCombatLockdown = function() return false end
		titles.module.set("npc_titles", "use_nameplates", false)
		titles.module.set("npc_titles", "enabled", true)
		check("turning the module on without the setting leaves the game's settings alone", #set_calls == 0)
		title_event("NAME_PLATE_UNIT_ADDED", "nameplate1")
		local line = created.nameplate1[1]
		check("a friendly NPC's title goes under its name", line and line.shown and line.text == "<Gryphon Master>"
			and line.points[1][1] == "TOP" and line.points[1][2] == plates.nameplate1.UnitFrame.name and line.points[1][3] == "BOTTOM")
		check("in the name's face and outline, a little smaller", line.path == "Fonts\\Plate.ttf" and line.size == 13 and line.flags == "OUTLINE")
		check("and in the name's colour", line.color[1] == 0.1 and line.color[2] == 0.9 and line.color[3] == 0.2)
		title_event("NAME_PLATE_UNIT_ADDED", "nameplate2")
		title_event("NAME_PLATE_UNIT_ADDED", "nameplate3")
		title_event("NAME_PLATE_UNIT_ADDED", "nameplate4")
		check("players, hostile NPCs and NPCs without a title get no line",
			#created.nameplate2 == 0 and #created.nameplate3 == 0 and #created.nameplate4 == 0)
		title_event("NAME_PLATE_UNIT_REMOVED", "nameplate1")
		check("the line goes when the nameplate does", line.shown == false)
		title_event("NAME_PLATE_UNIT_ADDED", "nameplate1")
		check("the same line is reused when the nameplate returns", #created.nameplate1 == 1 and line.shown == true)
		local secret = {}
		title_env.issecretvalue = function(value) return rawequal(value, secret) end
		tooltips.nameplate1 = { lines = { { leftText = "x" }, { leftText = secret } } }
		title_event("NAME_PLATE_UNIT_ADDED", "nameplate1")
		check("a secret title is skipped", line.shown == false)
		title_env.issecretvalue = nil
		titles.module.set("npc_titles", "use_nameplates", true)
		check("the setting turns friendly NPC nameplates on and the game's NPC names off",
			cvars.nameplateShowFriendlyNpcs == "1" and cvars.UnitNameNPC == "0" and cvars.UnitNameFriendlySpecialNPCName == "0")
		titles.module.set("npc_titles", "enabled", false)
		check("turning the module off puts the game's settings back",
			cvars.nameplateShowFriendlyNpcs == "0" and cvars.UnitNameNPC == "1" and cvars.UnitNameFriendlySpecialNPCName == "1")
		title_env.InCombatLockdown = function() return true end
		titles.module.set("npc_titles", "enabled", true)
		check("combat leaves the game's settings alone", cvars.UnitNameNPC == "1")
	end

	local names, name_env, name_event = load_qol()
	local function name_font(size, height)
		local font = { path = "Fonts\\FRIZQT__.TTF", size = size, flags = "", height = height }
		function font:GetFont() return self.path, self.size, self.flags end
		function font:SetFont(path, size, flags) self.path, self.size, self.flags = path, size, flags end
		function font:GetHeight() return self.height end
		function font:SetHeight(height) self.height = height end
		return font
	end
	local player_name = name_font(10, 12)
	local target_name = name_font(10, 12)
	local tot_name = name_font(10, 12)
	name_env.PlayerName = player_name
	name_env.TargetFrame = {
		TargetFrameContent = { TargetFrameContentMain = { Name = target_name } },
		totFrame = { Name = tot_name },
	}
	name_event("PLAYER_ENTERING_WORLD")
	check("unit names stay at the stock size while the module is off", player_name.size == 10 and target_name.size == 10 and tot_name.size == 10)
	name_env.InCombatLockdown = function() return true end
	names.module.set("unit_names", "enabled", true)
	check("combat leaves the unit names alone", player_name.size == 10 and target_name.height == 12)
	name_env.InCombatLockdown = function() return false end
	name_event("PLAYER_REGEN_ENABLED")
	check("leaving combat enlarges the player and target names",
		player_name.size == 14 and player_name.height == 14 and target_name.size == 14 and target_name.height == 14 and tot_name.size == 10)
	names.module.set("unit_names", "extra", 8)
	check("the name size slider updates both names", player_name.size == 18 and target_name.size == 18 and target_name.height == 18)
	names.module.set("unit_names", "extra", 40)
	check("extra name size stays inside the slider", names.module.get("unit_names", "extra") == 12 and player_name.size == 22)
	player_name:SetFont("Fonts\\Expressway.ttf", 11, "")
	names.module.set("unit_names", "extra", 4)
	check("a font change from elsewhere stays, with the extra size added",
		player_name.path == "Fonts\\Expressway.ttf" and player_name.size == 15 and target_name.size == 14 and target_name.height == 14)
	names.module.set("unit_names", "enabled", false)
	check("turning unit names off restores the sizes and heights",
		player_name.size == 11 and player_name.height == 12 and target_name.size == 10 and target_name.height == 12 and tot_name.size == 10)
	name_env.PlayerName = nil
	names.module.set("unit_names", "enabled", true)
	check("a missing player name is skipped", target_name.size == 14 and target_name.height == 14)
	target_name:SetFont("external.ttf", 17, "OUTLINE")
	target_name:SetHeight(30)
	names.module.set("unit_names", "enabled", false)
	check("disabling unit names preserves later font and height changes", target_name.size == 17 and target_name.height == 30 and target_name.path == "external.ttf")
	names.module.set("unit_names", "enabled", true)
	target_name:SetHeight(36)
	name_event("PLAYER_ENTERING_WORLD")
	names.module.set("unit_names", "enabled", false)
	check("unit names restore the latest external region height", target_name.size == 17 and target_name.height == 36)
	names.module.set("unit_names", "enabled", true)
	name_env.TargetFrame.TargetFrameContent.TargetFrameContentMain.Name = name_font(10, 12)
	names.module.set("unit_names", "enabled", false)
	check("a replaced unit name still has its owned size restored", target_name.size == 17 and target_name.height == 36)

	-- The default tooltip anchor is Blizzard's own call, so one hook on it moves
	-- every tooltip the game places, unit and item tooltips alike.
	local cursor, cursor_env, _, cursor_hooks = load_qol()
	local owned = {}
	cursor_env.GameTooltip = { SetOwner = function(self, owner, anchor, x, y) owned[#owned + 1] = { self = self, owner = owner, anchor = anchor, x = x, y = y } end }
	cursor_env.GameTooltip_SetDefaultAnchor = function() end
	cursor.module.set("tooltip_cursor", "enabled", true)
	local default_anchor = cursor_hooks.GameTooltip_SetDefaultAnchor
	check("the cursor module hooks the default tooltip anchor", type(default_anchor) == "function")
	local parent = {}
	default_anchor(cursor_env.GameTooltip, parent)
	check("an enabled module follows the tooltip to the cursor", #owned == 1 and owned[1].owner == parent and owned[1].anchor == "ANCHOR_CURSOR" and owned[1].x == 16 and owned[1].y == 16)
	default_anchor({ SetOwner = function() error("another tooltip must stay where the game put it") end }, parent)
	cursor.module.set("tooltip_cursor", "enabled", true)
	check("enabling twice hooks the anchor once", cursor_hooks.GameTooltip_SetDefaultAnchor == default_anchor)
	cursor.module.set("tooltip_cursor", "enabled", false)
	default_anchor(cursor_env.GameTooltip, parent)
	check("a disabled module leaves the tooltip where the game put it", #owned == 1)
	local bare, bare_env, _, bare_hooks = load_qol()
	bare_env.hooksecurefunc = nil
	bare_env.GameTooltip = { SetOwner = function() error("without the hook there is nothing to move") end }
	bare.module.set("tooltip_cursor", "enabled", true)
	check("without hooksecurefunc the module does nothing", next(bare_hooks) == nil)
	local missing, missing_env, _, missing_hooks = load_qol()
	missing_env.GameTooltip_SetDefaultAnchor = nil
	missing.module.set("tooltip_cursor", "enabled", true)
	check("without the default anchor call the module does nothing", missing_hooks.GameTooltip_SetDefaultAnchor == nil)

	-- Blizzard builds a chat line as format(CHAT_<TYPE>_GET .. message, name).
	-- Replacing those format strings sets the prefix and the message color
	-- without touching message text, which can be secret in restricted content.
	local function chat_world()
		local chat, chat_env, chat_event = load_qol()
		local added = {}
		local function frame()
			local window = {}
			function window:AddMessage(text, ...) added[#added + 1] = { text = text, extra = { ... } } end
			return window
		end
		chat_env.CHAT_FRAMES = { "ChatFrame1", "ChatFrame2" }
		chat_env.ChatFrame1, chat_env.ChatFrame2 = frame(), frame()
		chat_env.ChatTypeInfo = { GUILD = { r = 0.25, g = 1, b = 0.25 }, SAY = { r = 1, g = 1, b = 1 }, CHANNEL1 = { r = 1, g = 0.75, b = 0.75 } }
		chat_env.CHAT_GUILD_GET = "|Hchannel:Guild|h[Guild]|h %s: "
		chat_env.CHAT_SAY_GET = "%s says: "
		chat_env.CHAT_CHANNEL_GET = "%s: "
		return chat, chat_env, chat_event, added
	end
	local chat, chat_env, chat_event, chat_lines = chat_world()
	chat.module.set("chat_format", "enabled", true)
	local guild_line = chat_env.CHAT_GUILD_GET:format("NAME") .. "hello there"
	check("a guild line reads abbreviation, name, then the message in its own color", guild_line:find("|cff40ff40G|r NAME hello there", 1, true) ~= nil)
	check("the line no longer says Guild or ends the name with a colon", not guild_line:find("Guild", 1, true) and not guild_line:find(":", 1, true))
	check("a say line gets its own abbreviation", chat_env.CHAT_SAY_GET:format("NAME"):find("|cffffffffS|r NAME", 1, true) ~= nil)
	check("the message is left in the color the game gives the line", guild_line:match("hello there$") ~= nil and guild_line:find("|cffffffffhello", 1, true) == nil and chat_env.CHAT_SAY_GET:match("NAME |c") == nil and chat_env.CHAT_SAY_GET:format("N"):match("|r N $") ~= nil)
	chat.module.set("chat_format", "enabled", false)
	check("disabling puts the game's own formats back", chat_env.CHAT_GUILD_GET == "|Hchannel:Guild|h[Guild]|h %s: " and chat_env.CHAT_SAY_GET == "%s says: " and chat_env.CHAT_CHANNEL_GET == "%s: ")
	chat.module.set("chat_format", "enabled", true)
	chat_env.ChatTypeInfo.GUILD = { r = 1, g = 0, b = 0 }
	chat_event("UPDATE_CHAT_COLOR")
	check("changing the chat color recolors the abbreviation", chat_env.CHAT_GUILD_GET:format("N"):find("|cffff0000G|r", 1, true) ~= nil)
	chat_env.ChatTypeInfo.GUILD = nil
	chat_event("UPDATE_CHAT_COLOR")
	check("a type with no chat color falls back to white", chat_env.CHAT_GUILD_GET:format("N"):find("|cffffffffG|r", 1, true) ~= nil)

	local mark = chat_env.CHAT_SAY_GET:match("^(|cff%x%x%x%x%x%x|r)")
	local say = chat_env.CHAT_SAY_GET:format("|Hplayer:Thrall:1:SAY|h[|cffc79c6eThrall|r]|h") .. "for the Horde"
	chat_env.ChatFrame1:AddMessage(say, 1, 1, 1, 7)
	check("the brackets around the sender go and its class color stays", chat_lines[1].text:find("|Hplayer:Thrall:1:SAY|h|cffc79c6eThrall|r|h", 1, true) ~= nil)
	check("no bracket is left in the line", chat_lines[1].text:find("[", 1, true) == nil)
	check("the invisible marker is removed before the line shows", chat_lines[1].text:find(mark, 1, true) == nil and chat_lines[1].text:find("for the Horde", 1, true) ~= nil)
	check("the other AddMessage arguments pass through", chat_lines[1].extra[1] == 1 and chat_lines[1].extra[4] == 7)
	local system = "|Hplayer:Jaina:2|h[Jaina]|h has come online."
	chat_env.ChatFrame2:AddMessage(system)
	check("a line the module did not format keeps its brackets", chat_lines[2].text == system)
	chat_env.issecretvalue = function(value) return value == "secret line" end
	chat_env.ChatFrame1:AddMessage("secret line")
	check("secret text passes through untouched", chat_lines[3].text == "secret line")
	chat_env.issecretvalue = nil
	chat_env.ChatFrame1:AddMessage(42)
	check("a value that is not text passes through", chat_lines[4].text == 42)
	local channel = "|Hchannel:channel:1|h[1. General]|h " .. chat_env.CHAT_CHANNEL_GET:format("|Hplayer:Thrall:1|h[Thrall]|h") .. "anyone around?"
	chat_env.ChatFrame1:AddMessage(channel)
	check("a numbered channel shrinks to its number in the channel's color", chat_lines[5].text:find("|cffffbfbf1|r Thrall", 1, true) == nil and chat_lines[5].text:find("|Hchannel:channel:1|h|cffffbfbf1|r|h ", 1, true) ~= nil)
	check("the channel line keeps sender and message after it", chat_lines[5].text:find("|Hplayer:Thrall:1|hThrall|h anyone around?", 1, true) ~= nil)
	chat.module.set("chat_format", "enabled", false)
	check("a disabled module leaves the game's timestamps alone", chat_env.ChatFrameUtil == nil)
	chat_env.timestamps = "%H:%M "
	chat_env.GetCVar = function(name)
		if name == "showTimestamps" then return chat_env.timestamps end
	end
	chat_env.SetCVar = function(name, value)
		if name == "showTimestamps" then chat_env.timestamps = value end
	end
	chat_env.ChatFrameUtil = { GetTimestampFormat = function()
		if chat_env.timestamps ~= "none" then return chat_env.timestamps end
	end }
	local game_timestamps = chat_env.ChatFrameUtil.GetTimestampFormat
	chat.module.set("chat_format", "enabled", true)
	check("the game's timestamps are hidden by default", chat_env.timestamps == "none" and game_timestamps() == nil and chat_env.ChatFrameUtil.GetTimestampFormat == game_timestamps)
	chat.module.set("chat_format", "hide_timestamps", false)
	check("clearing the option brings the timestamps back", chat_env.timestamps == "%H:%M " and game_timestamps() == "%H:%M ")
	chat.module.set("chat_format", "hide_timestamps", true)
	check("setting the option hides them again", chat_env.timestamps == "none" and game_timestamps() == nil)
	chat.module.set("chat_format", "enabled", false)
	check("turning the module off restores the previous timestamp choice", chat_env.timestamps == "%H:%M " and game_timestamps() == "%H:%M ")
	chat_env.timestamps = "|cffff9900%H:%M|r "
	chat.module.set("chat_format", "enabled", true)
	check("enabling again hides the timestamp choice the player has now", chat_env.timestamps == "none")
	chat.module.set("chat_format", "enabled", false)
	check("turning it off restores that later choice", chat_env.timestamps == "|cffff9900%H:%M|r ")
	chat_env.timestamp_untouched = true
	chat_env.GetCVar = function() return nil end
	chat_env.SetCVar = function() chat_env.timestamp_untouched = false end
	chat_env.ChatFrameUtil = {}
	chat.module.set("chat_format", "enabled", true)
	check("a client with no timestamp value is left alone", chat_env.timestamp_untouched and next(chat_env.ChatFrameUtil) == nil)
	chat.module.set("chat_format", "enabled", false)
	chat_env.ChatFrame1:AddMessage(say)
	check("a disabled module leaves lines alone", chat_lines[6].text == say)
	local plain, plain_env = load_qol()
	plain.module.set("chat_format", "enabled", true)
	check("a client with none of the chat globals is left alone", plain_env.CHAT_GUILD_GET == nil)

	local time, flying = 0, false
	env2.GetTime = function() return time end
	env2.UnitOnTaxi = function() return flying end
	env2.TakeTaxiNode = function() end
	env2.NumTaxiNodes = function() return 2 end
	env2.TaxiNodeGetType = function(i) return i == 1 and "CURRENT" or "REACHABLE" end
	env2.TaxiNodeName = function(i) return i == 1 and "Origin" or "Destination" end
	addon2.module.set("flight_time", "enabled", true)
	local ground_poller
	for _, frame in ipairs(frames) do
		if frame.name == "EverlookFlightPoller" then ground_poller = frame end
	end
	check("flight time stays idle until a flight is taken", ground_poller and ground_poller.scripts.OnUpdate == nil)
	hooks.TakeTaxiNode(2)
	check("taking a flight starts the poller", ground_poller.scripts.OnUpdate ~= nil)
	local function update()
		for _, frame in ipairs(frames) do
			if frame.shown and frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, 0.25) end
		end
	end
	update(); time = 1; flying = true; update(); time = 61; flying = false; update()
	local route = env2.EverlookDB.qol.flight_time.routes["::Origin>Destination"]
	check("flight duration learns while display starts hidden", route and route.seconds == 60 and route.samples == 1)
	check("landing stops the flight poller", ground_poller.scripts.OnUpdate == nil)

	-- The quest interface checks below reuse this font.
	local font
	do
		local expressway = "Interface\\AddOns\\Everlook_Fonts\\assets\\expressway.ttf"
		local manrope = "Interface\\AddOns\\Everlook_Fonts\\assets\\manrope.ttf"
		local function font_object(path, size, flags)
			local object = { path = path, size = size, flags = flags or "" }
			function object:GetObjectType() return "Font" end
			function object:GetFont() return self.path, self.size, self.flags end
			function object:SetFont(next_path, next_size, next_flags) self.path, self.size, self.flags = next_path, next_size, next_flags end
			return object
		end
		-- A text region that inherits a font object reports that object's font
		-- until SetFont gives it one of its own.
		local function following_text(parent)
			local text = { parent = parent }
			function text:GetObjectType() return "FontString" end
			function text:GetFontObject() return self.parent end
			function text:GetFont()
				if self.path then return self.path, self.size, self.flags end
				return self.parent:GetFont()
			end
			function text:SetFont(path, size, flags) self.path, self.size, self.flags = path, size, flags end
			return text
		end
		font = font_object("original.ttf", 12, "OUTLINE")
		local region = { path = "chat.ttf", size = 10 }
		region.GetFont, region.SetFont = font.GetFont, font.SetFont
		function region:GetObjectType() return "FontString" end
		local protected_region = { path = "protected.ttf", size = 10 }
		protected_region.GetFont, protected_region.SetFont = font.GetFont, font.SetFont
		function protected_region:GetObjectType() return "FontString" end
		function protected_region:IsForbidden() return true end
		-- A chat window copies ChatFontNormal into a font of its own the first time
		-- SetFont runs, and CreateFont lists that copy among the globals.
		local chat_font = font_object("Fonts\\ARIALN.TTF", 14)
		local chat_frame = { fontObject = chat_font }
		function chat_frame:GetFontObject() return self.fontObject end
		function chat_frame:GetFont() return self.fontObject:GetFont() end
		function chat_frame:SetFont(path, size, flags)
			if self.fontObject == chat_font then
				self.fontObject = font_object(chat_font:GetFont())
				env2["table: chat frame"] = self.fontObject
			end
			self.fontObject:SetFont(path, size, flags)
		end
		chat_frame:SetFont("Fonts\\ARIALN.TTF", 16, "")
		local chat_line = following_text(chat_frame:GetFontObject())
		local nameplate_font = font_object("Fonts\\FRIZQT__.TTF", 9)
		local nameplate_name = following_text(nameplate_font)
		local unit_font = font_object("Fonts\\FRIZQT__.TTF", 10)
		local player_name = following_text(unit_font)
		local level_text = following_text(unit_font)
		local party_member = { Name = following_text(unit_font), PetFrame = { Name = following_text(unit_font) } }
		local compact_frame = { name = following_text(font_object("Fonts\\FRIZQT__.TTF", 10)) }
		local regions = { region, protected_region, chat_line, nameplate_name, player_name, level_text }
		local font_frame = { GetRegions = function() return unpack(regions) end }
		env2.EnumerateFrames = function(previous) if not previous then return font_frame end end
		env2.TestFont = font
		env2.ChatFontNormal = chat_font
		env2.ChatFrame1 = chat_frame
		env2.CHAT_FRAMES = { "ChatFrame1" }
		env2.SystemFont_NamePlate = nameplate_font
		env2.GameFontNormalSmall = unit_font
		env2.PlayerName = player_name
		env2.PartyFrame = {
			active = {},
			PartyMemberFramePool = { EnumerateActive = function() return pairs(env2.PartyFrame.active) end },
			InitializePartyMemberFrames = function(self) self.active[party_member] = true end,
		}
		env2.DefaultCompactUnitFrameSetup = function() end
		env2.STANDARD_TEXT_FONT = "original.ttf"
		env2.DAMAGE_TEXT_FONT = "original.ttf"
		env2.UNIT_NAME_FONT = "Fonts\\FRIZQT__.TTF"
		env2.UNIT_NAME_FONT_ROMAN = "Fonts\\FRIZQT__.TTF"
		env2.NAMEPLATE_FONT = "GameFontWhite"
		addon2.module.set("fonts", "enabled", true)
		check("Expressway sets interface text and skips forbidden regions", region.path == expressway and protected_region.path == "protected.ttf")
		check("Expressway replaces the interface fonts and their globals",
			font.path == expressway and unit_font.path == expressway and env2.STANDARD_TEXT_FONT == expressway and env2.DAMAGE_TEXT_FONT == expressway)
		check("chat windows and the chat font use Manrope at the window's size",
			select(1, chat_frame:GetFont()) == manrope and select(2, chat_frame:GetFont()) == 16 and chat_font.path == manrope)
		check("nameplates and names on unit frames use Manrope", nameplate_font.path == manrope and player_name.path == manrope)
		check("names drawn in the world use Manrope", env2.UNIT_NAME_FONT == manrope and env2.UNIT_NAME_FONT_ROMAN == manrope)
		check("NAMEPLATE_FONT names a font object, so it stays", env2.NAMEPLATE_FONT == "GameFontWhite")
		check("chat lines and nameplate text keep following their fonts", chat_line.path == nil and nameplate_name.path == nil)
		addon2.module.set("fonts", "size_offset", 2)
		check("font size adjustment avoids compounding", font.size == 14)
		check("text that follows a replaced font gets the adjustment once", player_name.size == 12 and level_text.size == 12)
		check("chat windows keep the size set on their tab", select(2, chat_frame:GetFont()) == 16)
		event2("ADDON_LOADED")
		check("font refresh preserves configured size", font.size == 14 and player_name.size == 12 and select(2, chat_frame:GetFont()) == 16)
		local late_text = following_text(unit_font)
		regions[#regions + 1] = late_text
		event2("ADDON_LOADED")
		check("text that appears later gets Expressway with the adjustment once", late_text.path == expressway and late_text.size == 12)
		env2.PartyFrame:InitializePartyMemberFrames()
		check("a party member's name uses Manrope", party_member.Name.path == manrope and party_member.PetFrame.Name.path == manrope)
		hooks.DefaultCompactUnitFrameSetup(compact_frame)
		check("a raid-style frame's name uses Manrope", compact_frame.name.path == manrope and compact_frame.name.size == 12)
		env2.InCombatLockdown = function() return true end
		addon2.module.set("fonts", "enabled", false)
		check("font restoration waits for combat to end", font.path ~= "original.ttf")
		env2.InCombatLockdown = function() return false end
		event2("PLAYER_REGEN_ENABLED")
		check("font restoration restores anonymous text regions", region.path == "chat.ttf" and region.size == 10)
		check("font restoration restores size and path after combat",
			font.path == "original.ttf" and font.size == 12 and env2.STANDARD_TEXT_FONT == "original.ttf" and env2.DAMAGE_TEXT_FONT == "original.ttf")
		check("font restoration puts chat back at the window's size",
			select(1, chat_frame:GetFont()) == "Fonts\\ARIALN.TTF" and select(2, chat_frame:GetFont()) == 16 and chat_font.path == "Fonts\\ARIALN.TTF" and chat_font.size == 14)
		local function game_font(text)
			local path, size = text:GetFont()
			return path == "Fonts\\FRIZQT__.TTF" and size == 10
		end
		check("font restoration puts the game's font back on names and later text",
			game_font(player_name) and game_font(level_text) and game_font(late_text) and game_font(party_member.Name) and game_font(compact_frame.name)
			and nameplate_font.path == "Fonts\\FRIZQT__.TTF" and env2.UNIT_NAME_FONT == "Fonts\\FRIZQT__.TTF" and env2.UNIT_NAME_FONT_ROMAN == "Fonts\\FRIZQT__.TTF")
		env2.GetLocale = function() return "koKR" end
		addon2.module.set("fonts", "enabled", true)
		check("Fonts leaves a Korean or Chinese client's fonts, which neither font can draw",
			font.path == "original.ttf" and env2.STANDARD_TEXT_FONT == "original.ttf" and select(1, chat_frame:GetFont()) == "Fonts\\ARIALN.TTF")
		addon2.module.set("fonts", "enabled", false)
		env2.GetLocale = nil
		env2.PartyFrame, env2.DefaultCompactUnitFrameSetup = nil, nil
	end

	do
		local typography, typography_env, typography_event = load_qol()
		local function inherited_font(parent, size, kind)
			local object = { parent = parent, size = size, path = size and "original.ttf" or nil }
			function object:GetObjectType() return kind or "Font" end
			function object:GetFontObject() return self.parent end
			function object:GetFont()
				if self.path then return self.path, self.size, "" end
				return self.parent:GetFont()
			end
			function object:SetFont(path, size) self.path, self.size = path, size end
			function object:SetFontObject(parent)
				self.parent, self.path, self.size = parent, nil, nil
			end
			return object
		end
		local line_base = inherited_font(nil, 12)
		local header_base = inherited_font(nil, 14)
		local line_large = inherited_font(nil, 18)
		local header_large = inherited_font(nil, 20)
		typography_env.ObjectiveTrackerFont12 = line_base
		typography_env.ObjectiveTrackerFont14 = header_base
		typography_env.ObjectiveTrackerFont18 = line_large
		typography_env.ObjectiveTrackerFont20 = header_large
		local line_font = inherited_font(line_base)
		local header_font = inherited_font(header_base)
		typography_env.ObjectiveTrackerLineFont = line_font
		typography_env.ObjectiveTrackerHeaderFont = header_font
		local line_text = inherited_font(line_font, nil, "FontString")
		local header_text = inherited_font(header_font, nil, "FontString")
		local tracker = {
			IsInitialized = function() return true end,
			HasSetting = function() return true end,
			UpdateSystem = function() end,
			UpdateSystemSettingTextSize = function() end,
			GetRegions = function() return line_text, header_text end,
		}
		typography_env.Enum = { EditModeObjectiveTrackerSetting = { TextSize = 4 } }
		typography_env.ObjectiveTrackerFrame = tracker
		typography_env.EnumerateFrames = function(previous) if not previous then return tracker end end
		typography_env.ObjectiveTrackerManager = { SetTextSize = function(_, size)
			line_font:SetFontObject(typography_env["ObjectiveTrackerFont" .. size])
			header_font:SetFontObject(typography_env["ObjectiveTrackerFont" .. (size + 2)])
		end }
		typography.module.set("fonts", "enabled", true)
		typography.module.set("quest_tracker", "text_size", 18)
		typography.module.set("quest_tracker", "enabled", true)
		local path, line_size = line_text:GetFont()
		local _, header_size = header_text:GetFont()
		check("Expressway tracker text follows the chosen objective and header sizes", line_size == 18 and header_size == 20 and path:find("expressway.ttf", 1, true))
		typography_event("PLAYER_ENTERING_WORLD")
		local _, refreshed = line_text:GetFont()
		check("Expressway refresh keeps tracker font inheritance", refreshed == 18 and line_text.path == nil)
		typography.module.set("quest_tracker", "enabled", false)
		local _, restored = line_text:GetFont()
		check("tracker restoration reaches Expressway text regions", restored == 12)
	end

	env2.QuestInfoDescriptionText = font
	local cvar_calls = 0
	env2.C_CVar = {
		GetCVar = function() cvar_calls = cvar_calls + 1 end,
		SetCVar = function() cvar_calls = cvar_calls + 1 end,
	}
	addon2.module.set("quest_interface", "enabled", true)
	check("quest interface enlarges quest text without a console variable", font.size == 16 and cvar_calls == 0)
	addon2.module.set("quest_interface", "enabled", false)
	check("quest interface restores the previous text size", font.size == 12 and cvar_calls == 0)

	local tracker_addon, tracker_env, tracker_event = load_qol()
	local text_setting = 4
	tracker_env.Enum = { EditModeObjectiveTrackerSetting = { TextSize = text_setting } }
	local tracker = { text_size = 12, line = 12, header = 14 }
	tracker_env.ObjectiveTrackerLineFont = newproxy(true)
	getmetatable(tracker_env.ObjectiveTrackerLineFont).__index = {
		GetFont = function() return "tracker.ttf", tracker.line, "" end,
	}
	tracker_env.ObjectiveTrackerManager = { SetTextSize = function(_, size)
		if size < 12 or size > 20 then return end
		tracker.line = size
		tracker.header = size + 2
	end }
	function tracker:IsInitialized() return self.initialized ~= false end
	function tracker:HasSetting(setting) return setting == text_setting end
	function tracker:UpdateSystem(value)
		self.initialized = true
		self.text_size = value
		self:UpdateSystemSettingTextSize()
	end
	function tracker:GetSettingValue(setting)
		if setting == text_setting then return self.text_size end
		return 0
	end
	function tracker:UpdateSystemSettingValue(setting, value)
		self.dirtied = true
		if setting ~= text_setting then return end
		self.text_size = value
		self:UpdateSystemSettingTextSize()
	end
	function tracker:UpdateSystemSettingTextSize()
		local size = self:GetSettingValue(text_setting)
		if size < 12 or size > 20 then return end
		tracker_env.ObjectiveTrackerManager:SetTextSize(size)
	end
	tracker_env.ObjectiveTrackerFrame = tracker
	check("the quest tracker keeps its text size while the module is off",
		tracker.line == 12 and tracker.header == 14 and tracker.text_size == 12 and tracker_addon.module.get("quest_tracker", "text_size") == 16)
	tracker_addon.module.set("quest_tracker", "text_size", 18)
	check("the tracker size does nothing while the module is off", tracker.line == 12 and tracker.header == 14)
	tracker_addon.module.set("quest_tracker", "enabled", true)
	check("enabling the quest tracker enlarges text without changing Edit Mode", tracker.text_size == 12 and tracker.line == 18 and tracker.header == 20 and not tracker.dirtied)
	tracker_addon.module.set("quest_tracker", "text_size", 30)
	check("quest tracker text size stays inside the tracker range", tracker_addon.module.get("quest_tracker", "text_size") == 20 and tracker.line == 20 and tracker.header == 22)
	tracker_addon.module.set("quest_tracker", "enabled", false)
	check("turning the quest tracker off restores the previous text size", tracker.text_size == 12 and tracker.line == 12 and tracker.header == 14)
	tracker.text_size = 13
	tracker:UpdateSystemSettingTextSize()
	check("edit mode owns the tracker size while the module is off", tracker.line == 13 and tracker.header == 15)
	tracker_env.ObjectiveTrackerFrame = nil
	tracker_addon.module.set("quest_tracker", "enabled", true)
	check("a missing quest tracker is skipped", tracker.line == 13)
	tracker_env.ObjectiveTrackerFrame = tracker
	tracker.initialized = false
	tracker_addon.module.set("quest_tracker", "enabled", true)
	check("an uninitialized quest tracker is left alone", tracker.line == 13)
	tracker:UpdateSystem(14)
	check("the quest tracker applies its size after late initialization", tracker.line == 20 and tracker.header == 22)
	tracker:UpdateSystem(15)
	check("a tracker layout refresh preserves the enabled objective size", tracker.line == 20)
	tracker_env.InCombatLockdown = function() return true end
	tracker_addon.module.set("quest_tracker", "enabled", false)
	check("tracker restoration waits until combat ends", tracker.line == 20)
	tracker_env.InCombatLockdown = function() return false end
	tracker_event("PLAYER_REGEN_ENABLED")
	check("disabling the tracker restores the current layout size after combat", tracker.line == 15 and tracker.header == 17)
	tracker_addon.module.set("quest_tracker", "enabled", true)
	tracker_env.ObjectiveTrackerManager:SetTextSize(17)
	tracker_addon.module.set("quest_tracker", "enabled", false)
	check("disabling tracker sizing preserves a later external text size", tracker.line == 17 and tracker.header == 19 and tracker.text_size == 15 and not tracker.dirtied)
	tracker.line, tracker.header = 24, 26
	tracker_addon.module.set("quest_tracker", "enabled", true)
	check("an external tracker size that cannot be restored is left alone", tracker.line == 24 and tracker.header == 26)
	tracker_addon.module.set("quest_tracker", "enabled", false)

	local posts, lines = {}, {}
	env2.Enum = { TooltipDataType = { Item = 1, Unit = 2, Spell = 3 } }
	env2.TooltipDataProcessor = { AddTooltipPostCall = function(kind, callback) posts[kind] = callback end }
	env2.GetCoinTextureString = tostring
	env2.C_Item.GetItemCount = function() return 3 end
	local clear
	local tip = { AddLine = function(_, line) lines[#lines + 1] = line end,
		HasScript = function() return true end, HookScript = function(_, _, callback) clear = callback end }
	addon2.module.set("useful_tooltips", "enabled", true)
	posts[1](tip, { id = 1 }); posts[1](tip, { id = 1 })
	check("item tooltip adds IDs and vendor totals without duplicates", #lines == 3 and lines[3]:find("30", 1, true))
	clear(tip); posts[1](tip, { id = 1 })
	check("tooltip clear permits rendering same item again", #lines == 6)
	addon2.module.set("useful_tooltips", "enabled", false)
	clear(tip); posts[1](tip, { id = 1 })
	check("disabled tooltip hooks add no lines", #lines == 6)

	local addon4, env4 = load_qol()
	addon4.npcs = { creature_id = function(guid) return guid == "Creature-0-0-0-0-448-0" and 448 or nil end }
	addon4.items = { id_from_link = function(link) return link == "item:6948" and 6948 or nil end }
	local url = addon4.links.url
	check("item links point at the item page", url("item", 6948) == "https://everlook.ing/database/items/6948")
	check("spell, creature, object and quest links use the site routes",
		url("spell", 133) == "https://everlook.ing/database/spells/133"
		and url("npc", 448) == "https://everlook.ing/database/npcs/448"
		and url("object", 2) == "https://everlook.ing/database/objects/2"
		and url("quest", 783) == "https://everlook.ing/quests/783")
	check("an unknown kind has no link", url("zone", 1) == nil)
	check("a bad id has no link", url("item", 0) == nil and url("item", -4) == nil and url("item", 1.5) == nil and url("item", "6948") == nil and url("item", nil) == nil)

	local posts4, lines4, clear4 = {}, {}, nil
	env4.Enum = { TooltipDataType = { Item = 0, Spell = 1, Unit = 2 } }
	env4.TooltipDataProcessor = { AddTooltipPostCall = function(kind, callback) posts4[kind] = callback end }
	env4.UnitGUID = function() return "Creature-0-0-0-0-448-0" end
	local tip4 = { AddLine = function(_, line) lines4[#lines4 + 1] = line end,
		HasScript = function() return true end, HookScript = function(_, _, callback) clear4 = callback end,
		GetUnit = function() return "Hogger", "mouseover" end }
	check("disabled links install no tooltip hooks", posts4[0] == nil)

	addon4.module.set("site_links", "enabled", true)
	posts4[0](tip4, { id = 6948 })
	check("an item tooltip gets its Everlook page", #lines4 == 1 and lines4[1]:find("everlook.ing/database/items/6948", 1, true) and not lines4[1]:find("https", 1, true))
	posts4[0](tip4, { id = 6948 })
	check("the same item adds the line once", #lines4 == 1)
	clear4(tip4)
	posts4[1](tip4, { id = 133 })
	check("a spell tooltip links the spell page", lines4[2] and lines4[2]:find("database/spells/133", 1, true))
	clear4(tip4)
	posts4[2](tip4)
	check("a creature tooltip links the creature page", lines4[3] and lines4[3]:find("database/npcs/448", 1, true))
	clear4(tip4)
	env4.issecretvalue = function() return true end
	posts4[0](tip4, { id = 7 })
	check("a secret id is not linked", #lines4 == 3)
	env4.issecretvalue = nil
	addon4.module.set("site_links", "enabled", false)
	clear4(tip4)
	posts4[0](tip4, { id = 6948 })
	check("turning the module off adds nothing", #lines4 == 3)
	check("the module has no command of its own",
		env4.SLASH_EVERLOOKLINK1 == nil and (env4.SlashCmdList == nil or env4.SlashCmdList.EVERLOOKLINK == nil) and addon4.site_links == nil)

	local addon5, env5, event5 = load_qol()
	local function listening(names)
		local frame = { events = {} }
		for _, name in ipairs(names) do frame.events[name] = true end
		function frame:UnregisterEvent(name) self.events[name] = nil end
		function frame:RegisterEvent(name) self.events[name] = true end
		return frame
	end
	env5.TalkingHeadFrame = listening({ "TALKINGHEAD_REQUESTED", "TALKINGHEAD_CLOSE" })
	env5.ZoneTextFrame = listening({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" })
	env5.UIErrorsFrame = listening({ "SYSMSG", "UI_INFO_MESSAGE", "UI_ERROR_MESSAGE" })
	env5.RaidWarningFrame = listening({ "CHAT_MSG_RAID_WARNING" })
	local stance = { shown = true, hooks = {} }
	function stance:Hide() self.shown = false; self.insecure_hides = (self.insecure_hides or 0) + 1 end
	local function drive_stance()
		if stance.driver == "hide" then stance.shown = false; stance.statehidden = true end
		if stance.driver == "show" then stance.shown = true; stance.statehidden = nil end
	end
	env5.RegisterStateDriver = function(frame, state, value)
		check("stance uses the secure visibility driver", frame == stance and state == "visibility")
		frame.driver = value
		drive_stance()
	end
	env5.UnregisterStateDriver = function(frame, state)
		check("stance unregisters only its visibility driver", frame == stance and state == "visibility")
		frame.driver = nil
	end
	env5.securecallfunction = function(callback, frame) callback(frame) end
	function stance:Show()
		if self.shown then return end
		self.shown = true
		local hooks = self.hooks.OnShow
		if not hooks then return end
		for index = 1, #hooks do hooks[index](self) end
	end
	function stance:HookScript(name, callback)
		self.hooks[name] = self.hooks[name] or {}
		local list = self.hooks[name]
		list[#list + 1] = callback
	end
	function stance:Update()
		self.updates = (self.updates or 0) + 1
		self:Show()
	end
	env5.StanceBar = stance
	local function all_events_back()
		return env5.TalkingHeadFrame.events.TALKINGHEAD_REQUESTED and env5.ZoneTextFrame.events.ZONE_CHANGED
			and env5.ZoneTextFrame.events.ZONE_CHANGED_INDOORS and env5.ZoneTextFrame.events.ZONE_CHANGED_NEW_AREA
			and env5.UIErrorsFrame.events.UI_ERROR_MESSAGE and env5.RaidWarningFrame.events.CHAT_MSG_RAID_WARNING
	end
	check("clutter hiding changes nothing while the module is off", all_events_back())
	check("the stance bar stays up while its option is off", env5.StanceBar.shown and addon5.module.get("hide_clutter", "stance_bar") == false)
	addon5.module.set("hide_clutter", "stance_bar", true)
	check("the stance option does nothing while the module is off", env5.StanceBar.shown and env5.StanceBar.updates == nil)
	addon5.module.set("hide_clutter", "stance_bar", false)
	addon5.module.set("hide_clutter", "error_messages", true)
	check("an option set while the module is off changes nothing", env5.UIErrorsFrame.events.UI_ERROR_MESSAGE)
	addon5.module.set("hide_clutter", "error_messages", false)

	addon5.module.set("hide_clutter", "enabled", true)
	check("the talking head stops listening for requests, and still closes",
		not env5.TalkingHeadFrame.events.TALKINGHEAD_REQUESTED and env5.TalkingHeadFrame.events.TALKINGHEAD_CLOSE)
	check("zone text stops listening for zone changes",
		not env5.ZoneTextFrame.events.ZONE_CHANGED and not env5.ZoneTextFrame.events.ZONE_CHANGED_INDOORS and not env5.ZoneTextFrame.events.ZONE_CHANGED_NEW_AREA)
	check("error messages and raid warnings stay on by default",
		env5.UIErrorsFrame.events.UI_ERROR_MESSAGE and env5.RaidWarningFrame.events.CHAT_MSG_RAID_WARNING)

	addon5.module.set("hide_clutter", "error_messages", true)
	check("hiding error messages leaves info messages and system messages",
		not env5.UIErrorsFrame.events.UI_ERROR_MESSAGE and env5.UIErrorsFrame.events.UI_INFO_MESSAGE and env5.UIErrorsFrame.events.SYSMSG)
	addon5.module.set("hide_clutter", "raid_warnings", true)
	check("hiding raid warnings stops the raid warning frame", not env5.RaidWarningFrame.events.CHAT_MSG_RAID_WARNING)
	addon5.module.set("hide_clutter", "zone_text", false)
	check("clearing one option brings that element back and leaves the others hidden",
		env5.ZoneTextFrame.events.ZONE_CHANGED_NEW_AREA and not env5.TalkingHeadFrame.events.TALKINGHEAD_REQUESTED and not env5.RaidWarningFrame.events.CHAT_MSG_RAID_WARNING)
	addon5.module.set("hide_clutter", "enabled", false)
	check("turning the module off restores every element", all_events_back())
	env5.TalkingHeadFrame = nil
	addon5.module.set("hide_clutter", "enabled", true)
	check("a frame this client does not have is skipped and the rest still apply", not env5.RaidWarningFrame.events.CHAT_MSG_RAID_WARNING)
	check("enabling hide clutter leaves the stance bar up", env5.StanceBar.shown and env5.StanceBar.updates == nil)
	addon5.module.set("hide_clutter", "stance_bar", true)
	check("the stance bar hides when its option is on", not env5.StanceBar.shown)
	check("stance hiding avoids protected Hide calls from addon code", stance.insecure_hides == nil and stance.driver == "hide")
	env5.StanceBar:Show()
	drive_stance()
	check("the secure driver hides the stance bar after the game shows it", not env5.StanceBar.shown)
	addon5.module.set("hide_clutter", "stance_bar", false)
	check("clearing the option lets the bar decide and a show stays up", env5.StanceBar.updates == 1 and env5.StanceBar.shown)
	check("clearing the stance option removes the driver and secure hidden state", stance.driver == nil and stance.statehidden == nil)
	env5.InCombatLockdown = function() return true end
	addon5.module.set("hide_clutter", "stance_bar", true)
	check("combat leaves the stance bar on screen", env5.StanceBar.shown)
	env5.StanceBar:Hide()
	env5.StanceBar:Show()
	check("a show during combat stays up", env5.StanceBar.shown)
	env5.InCombatLockdown = function() return false end
	event5("PLAYER_REGEN_ENABLED")
	check("leaving combat hides the stance bar", not env5.StanceBar.shown)
	env5.InCombatLockdown = function() return true end
	addon5.module.set("hide_clutter", "stance_bar", false)
	check("disabling stance hiding waits to remove the driver during combat", stance.driver == "hide")
	env5.InCombatLockdown = function() return false end
	event5("PLAYER_REGEN_ENABLED")
	check("disabling stance hiding restores the bar after combat", stance.driver == nil and stance.shown)
	env5.RegisterStateDriver = nil
	addon5.module.set("hide_clutter", "stance_bar", true)
	check("a missing secure driver leaves the stance bar alone", stance.driver == nil and stance.shown)
	env5.StanceBar = nil
	addon5.module.set("hide_clutter", "stance_bar", false)
	check("a missing stance bar is skipped", not env5.RaidWarningFrame.events.CHAT_MSG_RAID_WARNING)

	local addon6, env6, event6 = load_qol()
	local confirmed, accepted_res, popups_hidden = 0, 0, {}
	env6.Enum = { SummonReason = { Scenario = 2 } }
	env6.C_SummonInfo = { ConfirmSummon = function() confirmed = confirmed + 1 end }
	env6.AcceptResurrect = function() accepted_res = accepted_res + 1 end
	env6.StaticPopup_Hide = function(which) popups_hidden[#popups_hidden + 1] = which end
	env6.DELETE_ITEM_CONFIRM_STRING = "DELETE"
	event6("CONFIRM_SUMMON", 0, false)
	event6("RESURRECT_REQUEST", "Healer")
	check("auto responses do nothing while the module is off", confirmed == 0 and accepted_res == 0)

	addon6.module.set("auto_responses", "enabled", true)
	event6("CONFIRM_SUMMON", 0, false)
	check("a summon is accepted and its popup closes", confirmed == 1 and popups_hidden[#popups_hidden] == "CONFIRM_SUMMON")
	event6("CONFIRM_SUMMON", 0, true)
	event6("CONFIRM_SUMMON", 2, false)
	check("starting area and scenario summons stay manual", confirmed == 1)
	env6.IsShiftKeyDown = function() return true end
	event6("CONFIRM_SUMMON", 0, false)
	event6("RESURRECT_REQUEST", "Healer")
	check("Shift pauses summons and resurrections", confirmed == 1 and accepted_res == 0)
	env6.IsShiftKeyDown = function() return false end
	env6.InCombatLockdown = function() return true end
	event6("CONFIRM_SUMMON", 0, false)
	check("summons are not accepted in combat", confirmed == 1)
	event6("RESURRECT_REQUEST", "Healer")
	check("a combat resurrection is accepted and its popups close",
		accepted_res == 1 and popups_hidden[#popups_hidden] == "RESURRECT_NO_TIMER"
		and popups_hidden[#popups_hidden - 1] == "RESURRECT_NO_SICKNESS" and popups_hidden[#popups_hidden - 2] == "RESURRECT")
	env6.InCombatLockdown = function() return false end
	addon6.module.set("auto_responses", "accept_summons", false)
	addon6.module.set("auto_responses", "accept_resurrections", false)
	event6("CONFIRM_SUMMON", 0, false)
	event6("RESURRECT_REQUEST", "Healer")
	check("each response has its own option", confirmed == 1 and accepted_res == 1)

	local typed
	local box = { SetText = function(_, text) typed = text end }
	local dialog = { GetEditBox = function() return box end }
	local shown = 0
	env6.StaticPopupDialogs = { DELETE_GOOD_ITEM = { OnShow = function() shown = shown + 1 end } }
	env6.hooksecurefunc = function(target, name, callback)
		local original = target[name]
		target[name] = function(...) original(...); callback(...) end
	end
	addon6.module.set("auto_responses", "enabled", false)
	addon6.module.set("auto_responses", "enabled", true)
	env6.StaticPopupDialogs.DELETE_GOOD_ITEM.OnShow(dialog)
	check("the delete popup keeps its own behavior and stays empty by default", shown == 1 and typed == nil)
	addon6.module.set("auto_responses", "easy_delete", true)
	env6.StaticPopupDialogs.DELETE_GOOD_ITEM.OnShow(dialog)
	check("easy delete types the confirmation word", typed == "DELETE" and shown == 2)
	typed = nil
	env6.IsShiftKeyDown = function() return true end
	env6.StaticPopupDialogs.DELETE_GOOD_ITEM.OnShow(dialog)
	check("Shift leaves the confirmation to be typed", typed == nil)
	env6.IsShiftKeyDown = function() return false end
	addon6.module.set("auto_responses", "enabled", false)
	env6.StaticPopupDialogs.DELETE_GOOD_ITEM.OnShow(dialog)
	check("turning the module off stops easy delete", typed == nil)
	addon6.module.set("auto_responses", "enabled", true)
	local hooked_twice = shown
	env6.StaticPopupDialogs.DELETE_GOOD_ITEM.OnShow(dialog)
	check("the delete popup is hooked once, not once per enable", shown == hooked_twice + 1 and typed == "DELETE")

	local addon7, env7, event7 = load_qol()
	local function chat_frame(time_visible)
		local box = { points = { { "TOPLEFT", "frame", "BOTTOMLEFT", -5, -2 }, { "RIGHT", "bar", "RIGHT", 8, 0 } } }
		function box:GetNumPoints() return #self.points end
		function box:GetPoint(index) return unpack(self.points[index]) end
		function box:ClearAllPoints() self.points = {} end
		function box:SetPoint(...) self.points[#self.points + 1] = { ... } end
		local frame = { editBox = box, ScrollBar = { name = "bar" }, time = time_visible }
		function frame:GetTimeVisible() return self.time end
		function frame:SetTimeVisible(seconds) self.time = seconds end
		return frame
	end
	local function chat_button(shown)
		local button = { shown = shown }
		function button:IsShown() return self.shown end
		function button:Hide() self.shown = false end
		function button:Show() self.shown = true; if self.on_show then self.on_show(self) end end
		function button:HookScript(_, callback) self.on_show = callback end
		return button
	end
	env7.CHAT_FRAMES = { "ChatFrame1", "ChatFrame2" }
	env7.ChatFrame1, env7.ChatFrame2 = chat_frame(120), chat_frame(60)
	env7.ChatFrame1Tab = { name = "tab" }
	env7.ChatFrameMenuButton, env7.ChatFrameChannelButton = chat_button(true), chat_button(true)
	env7.ChatFrameToggleVoiceMuteButton = chat_button(false)
	local function anchors(box)
		local list = {}
		for _, point in ipairs(box.points) do list[#list + 1] = table.concat({ point[1], type(point[2]) == "table" and point[2].name or point[2], point[3], point[4], point[5] }, ",") end
		return table.concat(list, ";")
	end
	check("chat tweaks change nothing while off", anchors(env7.ChatFrame1.editBox) == "TOPLEFT,frame,BOTTOMLEFT,-5,-2;RIGHT,bar,RIGHT,8,0" and env7.ChatFrameMenuButton.shown)

	addon7.module.set("chat_tweaks", "enabled", true)
	check("the edit box moves above the chat tab", anchors(env7.ChatFrame1.editBox) == "BOTTOMLEFT,tab,TOPLEFT,-5,2;RIGHT,bar,RIGHT,8,0")
	check("a chat window with no tab uses the window itself",
		env7.ChatFrame2.editBox.points[1][2] == env7.ChatFrame2 and env7.ChatFrame2.editBox.points[1][3] == "TOPLEFT")
	check("the chat buttons are hidden", not env7.ChatFrameMenuButton.shown and not env7.ChatFrameChannelButton.shown)
	check("the fade time starts at the game default", env7.ChatFrame1.time == 120 and env7.ChatFrame2.time == 120)
	addon7.module.set("chat_tweaks", "fade_seconds", 30)
	check("the fade slider sets how long chat stays", env7.ChatFrame1.time == 30 and env7.ChatFrame2.time == 30)
	env7.ChatFrameMenuButton:Show()
	check("a button the game shows again is hidden again", not env7.ChatFrameMenuButton.shown)

	env7.ChatFrame1.editBox.points = { { "TOPLEFT", "frame", "BOTTOMLEFT", -5, -2 } }
	event7("UPDATE_CHAT_WINDOWS")
	check("a chat window refresh puts the edit box back on top", env7.ChatFrame1.editBox.points[1][1] == "BOTTOMLEFT")

	addon7.module.set("chat_tweaks", "editbox_top", false)
	check("clearing the edit box option restores its anchors", anchors(env7.ChatFrame1.editBox) == "TOPLEFT,frame,BOTTOMLEFT,-5,-2;RIGHT,bar,RIGHT,8,0")
	addon7.module.set("chat_tweaks", "hide_buttons", false)
	check("clearing the button option brings back the buttons that were shown", env7.ChatFrameMenuButton.shown and env7.ChatFrameChannelButton.shown and not env7.ChatFrameToggleVoiceMuteButton.shown)
	addon7.module.set("chat_tweaks", "editbox_top", true)
	addon7.module.set("chat_tweaks", "hide_buttons", true)
	addon7.module.set("chat_tweaks", "enabled", false)
	check("turning the module off restores anchors, fade time and buttons",
		anchors(env7.ChatFrame1.editBox) == "TOPLEFT,frame,BOTTOMLEFT,-5,-2;RIGHT,bar,RIGHT,8,0"
		and env7.ChatFrame1.time == 120 and env7.ChatFrame2.time == 60
		and env7.ChatFrameMenuButton.shown and env7.ChatFrameChannelButton.shown and not env7.ChatFrameToggleVoiceMuteButton.shown)
	env7.ChatFrameChannelButton = nil
	env7.CHAT_FRAMES = { "ChatFrame1", "ChatFrame3" }
	addon7.module.set("chat_tweaks", "enabled", true)
	check("a button or window this client does not have is skipped", not env7.ChatFrameMenuButton.shown and env7.ChatFrame1.time == 30)

	local minimap_scripts, toggles, tooltip_lines = {}, 0, {}
	local env9 = setmetatable({}, { __index = _G })
	env9._G = env9
	local function widget()
		return setmetatable({}, { __index = function(_, key)
			if key == "SetScript" then return function(_, name, callback) minimap_scripts[name] = callback end end
			if key == "CreateTexture" then return function() return widget() end end
			if key == "GetParent" then return function() return env9.Minimap end end
			return function() end
		end })
	end
	env9.Minimap = { GetWidth = function() return 140 end, GetHeight = function() return 140 end }
	env9.CreateFrame = function() return widget() end
	env9.GameTooltip = { SetOwner = function() end, Show = function() end, Hide = function() end,
		AddLine = function(_, line) tooltip_lines[#tooltip_lines + 1] = line end }
	env9.MenuUtil = { CreateButtonContextMenu = function() error("the minimap icon must not open a menu") end }
	local minimap_load
	env9.EventUtil = { ContinueOnAddOnLoaded = function(_, callback) minimap_load = callback end, ContinueOnPlayerLogin = function() end }
	local minimap_addon = { settings = { toggle = function() toggles = toggles + 1 end } }
	local minimap_chunk = assert(loadfile(source("minimap"))); setfenv(minimap_chunk, env9); minimap_chunk("Everlook", minimap_addon)
	minimap_load()
	local minimap_button = widget()
	minimap_scripts.OnClick(minimap_button, "LeftButton")
	minimap_scripts.OnClick(minimap_button, "RightButton")
	check("clicking the minimap icon toggles the settings page, with either button", toggles == 2)
	minimap_scripts.OnEnter(minimap_button)
	check("the minimap tooltip says what a click does", tooltip_lines[1] == "Everlook" and tooltip_lines[#tooltip_lines]:find("settings", 1, true))

	local registered, pages, headers, rows = {}, 0, {}, {}
	local root_category = { GetID = function() return 42 end }
	local layout = { AddInitializer = function(_, row) rows[#rows + 1] = row end }
	local subpages, canvas_pages, page_of_variable = {}, {}, {}
	local children, settings_buttons, sliders = {}, {}, {}
	local function control()
		return { SetParentInitializer = function(self, parent, predicate)
			self.parent, self.predicate = parent, predicate; children[#children + 1] = self
		end }
	end
	local canvas = {}
	local canvas_requests, opened = 0, nil
	addon2.collected = { page = function() canvas_requests = canvas_requests + 1; return canvas end }
	local scanned = 0
	addon2.scan = { now = function() scanned = scanned + 1 end }
	env2.Settings = {
		RegisterVerticalLayoutCategory = function(name)
			assert(name == "Everlook"); pages = pages + 1; return root_category, layout
		end,
		RegisterVerticalLayoutSubcategory = function(parent, name)
			assert(parent == root_category, "a subpage must hang under the Everlook page")
			local page = { GetID = function() return 100 + #subpages end, name = name }
			subpages[#subpages + 1] = page
			return page, { AddInitializer = function(_, row) headers[#headers + 1] = row.name; if row.click then settings_buttons[row.name] = row end end }
		end,
		RegisterCanvasLayoutSubcategory = function(parent, frame, name)
			assert(parent == root_category, "a canvas subpage must hang under the Everlook page")
			local page = { GetID = function() return 200 + #canvas_pages end, name = name, frame = frame }
			canvas_pages[#canvas_pages + 1] = page
			return page, {}
		end,
		RegisterAddOnCategory = function(page) assert(page == root_category) end,
		RegisterProxySetting = function(page, variable, _, _, default, get, set)
			assert(page ~= root_category, "module settings belong on a subpage, not the Everlook page")
			assert(not registered[variable], "duplicate setting variable")
			registered[variable] = { get = get, set = set, default = default }; page_of_variable[variable] = page.name; return { variable = variable }
		end,
		CreateCheckbox = control,
		CreateControlTextContainer = function()
			local data = {}
			return { Add = function(_, value, label) data[#data + 1] = { value = value, label = label } end, GetData = function() return data end }
		end,
		CreateDropdown = control,
		CreateSliderOptions = function(minimum, maximum, step)
			local options = { minimum = minimum, maximum = maximum, step = step }
			function options:SetLabelFormatter(_, format) self.format = format end
			return options
		end,
		CreateSlider = function(_, proxy, options) sliders[proxy.variable] = options; return control() end,
		OpenToCategory = function(id) opened = id end,
	}
	env2.CreateSettingsListSectionHeaderInitializer = function(name)
		return { name = name }
	end
	env2.CreateSettingsButtonInitializer = function(name, _, click, _, search)
		assert(search ~= nil); return { name = name, click = click }
	end
	env2.EventUtil.ContinueOnAddOnLoaded = function(_, callback) callback() end
	env2.EventUtil.ContinueOnPlayerLogin = function(callback) callback() end
	env2.MinimalSliderWithSteppersMixin = { Label = { Right = "right" } }
	local settings = assert(loadfile(source("settings"))); setfenv(settings, env2); settings("Everlook", addon2)
	check("native settings register one Everlook page", pages == 1)
	check("modules can add native settings buttons after their options", settings_buttons["Preview notifications"] and settings_buttons["Reset Island position"])
	check("preview has no effect when the module is off", settings_buttons["Preview notifications"].click() == false and #addon2.smart_island.view().notices == 0)
	addon2.module.set("smart_island", "enabled", true)
	settings_buttons["Preview notifications"].click()
	local preview_notices = addon2.smart_island.view().notices
	check("native preview adds warning, coins and longer local examples", #preview_notices == 3 and preview_notices[1].severity == "warning" and preview_notices[2].money == 12345 and preview_notices[3].detail)
	addon2.module.set("smart_island", "position_x", 103)
	addon2.module.set("smart_island", "position_top", 13)
	check("dragging the Island lands on the pixel it was dropped on", addon2.module.get("smart_island", "position_x") == 103 and addon2.module.get("smart_island", "position_top") == 13)
	settings_buttons["Reset Island position"].click()
	check("native reset restores the position preferences", addon2.module.get("smart_island", "position_x") == 0 and addon2.module.get("smart_island", "position_top") == 12)
	addon2.module.set("smart_island", "enabled", false)
	local subpage_names = {}
	for index = 1, #subpages do subpage_names[index] = subpages[index].name end
	check("each subject gets its own subpage on the left", table.concat(subpage_names, ",") == "Quests,Vendors,Loot and mail,Social,Chat,Tooltips,Map,Interface,Smart island,Radial menu")
	check("collected data is a subpage that hosts the browser frame", #canvas_pages == 1 and canvas_pages[1].name == "Collected data" and canvas_pages[1].frame == canvas and canvas_requests == 1)
	local count, expected = 0, 0
	for _ in pairs(registered) do count = count + 1 end
	for _, module in ipairs(addon2.module.modules) do
		for _ in pairs(module.options) do expected = expected + 1 end
	end
	check("the subpages include each module option exactly once", count == expected)
	check("an option sits on its subject's page",
		page_of_variable.Everlook_QoL_map_pins_enabled == "Map" and page_of_variable.Everlook_QoL_useful_tooltips_enabled == "Tooltips"
		and page_of_variable.Everlook_QoL_sell_junk_enabled == "Vendors" and page_of_variable.Everlook_QoL_fonts_size_offset == "Interface"
		and page_of_variable.Everlook_QoL_quest_automation_enabled == "Quests" and page_of_variable.Everlook_QoL_smart_island_enabled == "Smart island"
		and page_of_variable.Everlook_QoL_mail_enabled == "Loot and mail")
	local module_count = #addon2.module.modules
	local last = addon2.module.modules[module_count]
	local function has_header(name)
		for index = 1, #headers do
			if headers[index] == name then return index end
		end
	end
	check("a subpage titles each module with a section heading", has_header("Map pins") and has_header("Useful tooltips") and has_header(last.name))
	check("island sections keep placement, notices and their buttons in order",
		(has_header("Reset Island position") or 0) > (has_header("Placement") or 0)
		and (has_header("Opening") or 0) > (has_header("Placement") or 0)
		and (has_header("Quest display") or 0) > (has_header("Opening") or 0)
		and (has_header("Notices") or 0) > (has_header("Quest display") or 0)
		and (has_header("Preview notifications") or 0) > (has_header("Notices") or 0)
		and (has_header("Session recap") or 0) > (has_header("Preview notifications") or 0)
		and (has_header("Activity") or 0) > (has_header("Session recap") or 0))
	count = 0
	for _, module in ipairs(addon2.module.modules) do
		if page_of_variable["Everlook_QoL_" .. module.id .. "_enabled"] then count = count + 1 end
	end
	check("every module appears on exactly one page", count == module_count)
	check("module options are grouped under their enable toggle", #children == expected - module_count)
	local sample = children[1]
	registered.Everlook_QoL_quest_interface_enabled.set(false)
	check("disabled module options cannot be changed in the UI", not sample.predicate())
	registered.Everlook_QoL_quest_interface_enabled.set(true)
	check("enabling a module makes its options available", sample.predicate())
	check("subpage toggles retain saved preferences", registered.Everlook_QoL_quest_interface_enabled.get())
	registered.Everlook_QoL_fonts_size_offset.set(100)
	check("settings clamp font size to supported range", addon2.module.get("fonts", "size_offset") == 8)
	check("a slider that counts things shows its number", sliders.Everlook_QoL_smart_island_toast_count.format(3) == "3")
	check("every text size is in points", sliders.Everlook_QoL_fonts_size_offset.format(3) == "3 pt" and sliders.Everlook_QoL_unit_names_extra.format(4) == "4 pt"
		and sliders.Everlook_QoL_quest_interface_text_size.format(16) == "16 pt" and sliders.Everlook_QoL_quest_tracker_text_size.format(16) == "16 pt")
	check("the Island's position is in pixels", sliders.Everlook_QoL_smart_island_position_x.format(-103) == "-103 px" and sliders.Everlook_QoL_smart_island_position_top.format(12) == "12 px")
	check("a slider with a unit shows it after the number", sliders.Everlook_QoL_smart_island_size.format(105) == "105%" and sliders.Everlook_QoL_chat_tweaks_fade_seconds.format(120) == "120 s")
	check("a label shows the step the value will be stored on", sliders.Everlook_QoL_smart_island_size.format(97) == "95%" and sliders.Everlook_QoL_smart_island_size.format(98) == "100%")
	local scale = sliders.Everlook_QoL_swing_timers_scale
	check("a percentage label shows the step too", scale.format(83) == "80%" and scale.format(87) == "90%")
	check("a fraction shown as a percentage runs in whole percents", scale.minimum == 50 and scale.maximum == 100 and scale.step == 10 and scale.format(80) == "80%")
	check("a percentage slider starts from the stored fraction", registered.Everlook_QoL_swing_timers_scale.default == 50 and registered.Everlook_QoL_swing_timers_scale.get() == 50)
	registered.Everlook_QoL_swing_timers_scale.set(80)
	check("a percentage slider stores the fraction", addon2.module.get("swing_timers", "scale") == 0.8 and registered.Everlook_QoL_swing_timers_scale.get() == 80)
	registered.Everlook_QoL_smart_island_quest_distance_weight.set(150)
	check("a quarter step shows as a whole percentage", addon2.module.get("smart_island", "quest_distance_weight") == 1.5 and registered.Everlook_QoL_smart_island_quest_distance_weight.get() == 150)
	addon2.settings.toggle()
	check("the toggle opens the Everlook page", opened == 42)
	local hidden_panels = 0
	env2.SettingsPanel = { shown = true, IsShown = function(self) return self.shown end, GetCurrentCategory = function() return root_category end }
	env2.HideUIPanel = function(panel) hidden_panels = hidden_panels + 1; panel.shown = false end
	opened = nil
	addon2.settings.toggle()
	check("the toggle closes the page while it is showing", hidden_panels == 1 and opened == nil)
	env2.SettingsPanel.shown = true
	env2.SettingsPanel.GetCurrentCategory = function() return subpages[2] end
	addon2.settings.toggle()
	check("the toggle closes the window from any Everlook subpage", hidden_panels == 2 and opened == nil)
	env2.SettingsPanel.shown = true
	env2.SettingsPanel.GetCurrentCategory = function() return canvas_pages[1] end
	addon2.settings.toggle()
	check("the toggle closes the window from the collected data subpage", hidden_panels == 3 and opened == nil)
	env2.SettingsPanel.shown = true
	env2.SettingsPanel.GetCurrentCategory = function() return {} end
	addon2.settings.toggle()
	check("the toggle switches to Everlook from another settings page", opened == 42 and hidden_panels == 3)
	env2.SettingsPanel.shown = false
	opened = nil
	addon2.settings.toggle()
	check("the toggle opens the page when the panel is closed", opened == 42 and hidden_panels == 3)
	check("/everlook is the only command and it toggles the page",
		env2.SLASH_EVERLOOK1 == "/everlook" and env2.SLASH_EVERLOOK2 == nil and env2.SLASH_EVERLOOKQOL1 == nil
		and env2.SlashCmdList.EVERLOOK == addon2.settings.toggle and env2.SlashCmdList.EVERLOOKQOL == nil)
	check("the Everlook page keeps only the eager scan, with no data button", rows[1].name == "Eager scan" and rows[2] == nil)
	rows[1].click()
	check("the eager scan button scans", scanned == 1)
	local addon3, env3, _, _, _, frames3 = load_qol()
	local base_create = env3.CreateFrame
	env3.UISpecialFrames = {}
	env3.UIParent = {}
	env3.Settings = { RegisterCanvasLayoutCategory = function() error("collected browser must not register a settings page") end }
	local function label()
		return {
			SetPoint = function() end, SetText = function(self, text) self.text = text end,
			Hide = function(self) self.shown = false end, SetShown = function(self, value) self.shown = value end,
		}
	end
	local function list_button()
		local button = { scripts = {} }
		function button:CreateTexture()
			return {
				SetTexture = function() end, SetBlendMode = function() end, SetAllPoints = function() end,
				Hide = function() end, SetAlpha = function() end, SetShown = function() end,
			}
		end
		function button:SetHighlightTexture() end
		function button:GetHighlightTexture()
			return { SetAlpha = function() end }
		end
		function button:CreateFontString()
			return {
				SetPoint = function() end, SetJustifyH = function() end, SetWordWrap = function() end,
				SetMaxLines = function() end, SetFontObject = function() end,
				SetText = function(self, text) self.text = text end,
			}
		end
		function button:RegisterForClicks() end
		function button:SetScript(name, callback) self.scripts[name] = callback end
		function button:GetElementData() return self.data end
		return button
	end
	env3.CreateFrame = function(kind, name, parent, template)
		local widget = base_create()
		widget.name, widget.template = name, template
		widget.TitleText = label()
		widget.portrait = { SetTexture = function() end }
		widget.CreateFontString = label
		for _, method in ipairs({ "SetFrameStrata", "SetClampedToScreen", "SetMovable", "EnableMouse", "RegisterForDrag", "StartMoving", "StopMovingOrSizing", "SetWidth" }) do
			widget[method] = function() end
		end
		function widget:SetShown(value) self.shown = value end
		function widget:IsShown() return self.shown end
		function widget:SetDataProvider(entries)
			self.entries = entries
			local initializer = self.view and self.view.initializer
			if type(initializer) ~= "function" or type(entries) ~= "table" then
				return
			end
			self.buttons = {}
			for index = 1, #entries do
				local button = list_button()
				button.data = entries[index]
				initializer(button, entries[index])
				self.buttons[index] = button
			end
		end
		function widget:Show()
			self.shown = true
			if self.scripts.OnShow then self.scripts.OnShow(self) end
		end
		return widget
	end
	env3.CreateDataProvider = function(entries) return entries end
	env3.CreateScrollBoxListLinearView = function()
		local view = { SetElementExtent = function() end }
		function view:SetElementInitializer(_, initializer)
			self.initializer = initializer
		end
		return view
	end
	env3.ScrollUtil = {
		InitScrollBoxListWithScrollBar = function(scroll_box, _, view)
			scroll_box.view = view
		end,
	}
	addon3.world = {
		collected = function()
			return { { bucket = "npcs", label = "Creatures", count = 1, records = { { id = "448", text = "Hogger" } } } }
		end,
		row = function(bucket, id)
			if bucket == "maps" and id == 37 then
				return { name = "Elwynn Forest" }
			end
			if bucket == "npcs" and (id == 448 or id == "448") then
				return { locations = { { mapId = 37, x = 500, y = 250, role = 1 } } }
			end
		end,
	}
	local before = #frames3
	local collected = assert(loadfile(source("collected"))); setfenv(collected, env3); collected("Everlook", addon3)
	check("collected browser builds nothing until its page is asked for", #frames3 == before)
	local browser = addon3.collected.page()
	check("the browser is one plain frame for a settings page, not a window", #frames3 == before + 1 and browser == frames3[before + 1] and browser.template == nil and browser.name == "EverlookCollectedPage")
	check("asking again returns the same frame", addon3.collected.page() == browser and #frames3 == before + 1)
	check("the browser has no window chrome and no Escape hook", env3.UISpecialFrames[1] == nil and addon3.collected.show == nil)
	check("the lists wait for the page to be shown", #frames3 == before + 1)
	browser:Show()
	check("collected browser retains bucket and record providers", frames3[before + 2].entries[1].bucket == "npcs" and frames3[before + 4].entries[1].text == "Hogger")
	check("the selected record shows its map location", frames3[before + 4].buttons[1].detail.text == "Elwynn Forest 50.0, 25.0 giver")
	addon3.world.collected = function() return {} end
	browser:Show()
	check("showing the page again refreshes the browser", not frames3[before + 2].shown and #frames3 == before + 6)


	-- Radial wheel: geometry and drawing.
	do
		local radial_addon = load_qol()
		local wheel = radial_addon.wheel
		check("the first wedge is straight up", wheel.sector(4, 0, 100) == 1)
		check("wedges run clockwise from the top", wheel.sector(4, 100, 0) == 2 and wheel.sector(4, 0, -100) == 3 and wheel.sector(4, -100, 0) == 4)
		check("a cursor close to the centre chooses nothing", wheel.sector(4, 5, 5) == nil)
		check("a wedge owns the angles around its own direction", wheel.sector(8, 40, 100) == 1 and wheel.sector(8, 60, 100) == 2 and wheel.sector(8, 100, 100) == 2)
		check("the first wedge reaches across the top to the left", wheel.sector(8, -10, 100) == 1 and wheel.sector(8, -60, 100) == 8)
		check("one wedge takes every direction", wheel.sector(1, -50, -50) == 1)
		check("no wedges choose nothing", wheel.sector(0, 0, 100) == nil)
		local x1, y1 = wheel.position(1, 4)
		local x2, y2 = wheel.position(2, 4)
		local x3, y3 = wheel.position(3, 4)
		local x4, y4 = wheel.position(4, 4)
		check("labels sit on the ring in wedge order", math.abs(x1) < 1e-6 and y1 > 0 and x2 > 0 and math.abs(y2) < 1e-6 and math.abs(x3) < 1e-6 and y3 < 0 and x4 < 0 and math.abs(y4) < 1e-6)
		local xa, ya = wheel.position(2, 8)
		check("a label sits along its own direction", xa > 0 and ya > 0 and math.abs(xa / ya - 1) < 1e-6)
	end
	local function drawn_wheel(radial_addon, radial_env)
		if not radial_addon then radial_addon, radial_env = load_qol() end
		local made = {}
		local function fake(kind, name)
			local object = { kind = kind, name = name, points = {}, shown = false }
			made[#made + 1] = object
			function object:SetScript(event, fn) self.scripts = self.scripts or {}; self.scripts[event] = fn end
			function object:SetPoint(...) self.points[#self.points + 1] = { ... } end
			function object:ClearAllPoints() self.points = {} end
			function object:Show() self.shown = true end
			function object:Hide() self.shown = false end
			function object:IsShown() return self.shown end
			function object:SetText(text) self.text = text end
			function object:GetStringWidth() return 50 end
			function object:SetSize(width, height) self.width, self.height = width, height end
			function object:SetWidth(width) self.width = width end
			function object:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
			function object:SetTextColor(r, g, b, a) self.text_color = { r, g, b, a } end
			function object:CreateFontString() return fake("fontstring") end
			function object:CreateTexture() return fake("texture") end
			function object:CreateMaskTexture() return fake("mask") end
			for _, method in ipairs({ "SetFrameStrata", "SetFontObject", "EnableMouse", "SetAllPoints", "SetTexture", "AddMaskTexture", "SetJustifyH", "SetVertexColor", "SetAlpha", "SetDrawLayer" }) do
				object[method] = function() end
			end
			return object
		end
		radial_env.CreateFrame = function(_, name) return fake("frame", name) end
		radial_env.UIParent = { GetWidth = function() return 1920 end, GetHeight = function() return 1080 end, GetEffectiveScale = function() return 1 end }
		local cursor = { x = 0, y = 0 }
		radial_env.GetCursorPosition = function() return cursor.x, cursor.y end
		return radial_addon.wheel, radial_env, made, cursor
	end
	do
		local wheel, env_w, made, cursor = drawn_wheel()
		check("the wheel builds nothing until it opens", #made == 0 and not wheel.is_open())
		cursor.x, cursor.y = 960, 540
		wheel.open({ "Attack", "Warning", "On my way" }, 960, 540)
		local root
		for _, object in ipairs(made) do if object.name == "EverlookRadialWheel" then root = object end end
		check("opening shows the wheel", wheel.is_open() and root and root.shown)
		local texts = {}
		for _, object in ipairs(made) do if object.kind == "fontstring" and object.text then texts[#texts + 1] = object.text end end
		check("each wedge is drawn with its text", table.concat(texts, ",") == "Attack,Warning,On my way")
		local point = root.points[#root.points]
		check("the wheel is centred where it opened", point[1] == "CENTER" and point[2] == env_w.UIParent and point[3] == "BOTTOMLEFT" and point[4] == 960 and point[5] == 540)
		check("nothing is chosen before the cursor moves", wheel.selected() == nil)
		cursor.x, cursor.y = 960, 640
		root.scripts.OnUpdate(root, 0.016)
		check("the cursor above the centre chooses the first wedge", wheel.selected() == 1)
		cursor.x, cursor.y = 1060, 440
		root.scripts.OnUpdate(root, 0.016)
		check("the cursor to the lower right chooses the next wedge clockwise", wheel.selected() == 2)
		cursor.x, cursor.y = 960, 545
		root.scripts.OnUpdate(root, 0.016)
		check("moving back to the centre cancels the choice", wheel.selected() == nil)
		cursor.x, cursor.y = 960, 640
		root.scripts.OnUpdate(root, 0.016)
		wheel.close()
		check("closing hides the wheel and forgets the choice", not wheel.is_open() and not root.shown and wheel.selected() == nil)
		local built = #made
		wheel.open({ "Attack", "Warning" }, 960, 540)
		check("a second opening with fewer wedges builds nothing new", #made == built)
		wheel.close()
		wheel.open({ "A" }, 4, 4)
		local clamped = root.points[#root.points]
		check("a wheel opened at the screen edge is moved to fit", clamped[4] > 100 and clamped[5] > 100)
		wheel.close()
		wheel.open({ "A" }, 1919, 1079)
		clamped = root.points[#root.points]
		check("and so is one opened at the opposite corner", clamped[4] < 1819 and clamped[5] < 979)
		wheel.close()
	end

	-- Radial menu: what is under the cursor decides the wheel, and the secure button fires the choice.
	local function radial_fixture(real_wheel)
		local radial_addon, radial_env, event, _, _, frames = load_qol()
		local button
		for _, frame in ipairs(frames) do if frame.name == "EverlookRadialButton" then button = frame end end
		local hover = { exists = false, is_self = false, is_player = false, can_attack = false, guid = "Player-1-0A", name = "Thrall", realm = "Orgrimmar",
			in_party = false, in_group = false, in_raid = false, leader = false, assistant = false, over = nil }
		local seen = { calls = {}, closed = 0 }
		local function log(name) return function(...) seen.calls[#seen.calls + 1] = { name = name, ... } end end
		radial_env.UIParent = { GetEffectiveScale = function() return 2 end }
		radial_env.GetCursorPosition = function() return 400, 600 end
		radial_env.GetMouseFoci = function() return { hover.over } end
		radial_env.UnitIsUnit = function(unit, other) return unit == "mouseover" and other == "player" and hover.is_self end
		radial_env.UnitIsPlayer = function() return hover.is_player end
		radial_env.UnitCanAttack = function() return hover.can_attack end
		radial_env.UnitGUID = function(unit)
			if unit == "mouseover" and hover.exists then return hover.mouse_guid or hover.guid end
			if unit == (hover.token or "party1") then return hover.token_guid or hover.guid end
		end
		radial_env.UnitExists = function(unit) return radial_env.UnitGUID(unit) ~= nil end
		radial_env.UnitFullName = function() return hover.name, hover.realm end
		radial_env.UnitTokenFromGUID = function(guid) if guid == hover.guid and not hover.gone then return hover.token or "party1" end end
		radial_env.GetNormalizedRealmName = function() return "Stormrage" end
		-- Blizzard's name helper omits your realm and preserves native surname formatting.
		radial_env.NameUtil = { GetUnmodifiedUnitFullName = function()
			if hover.native_name then return hover.native_name end
			if hover.realm and hover.realm ~= "" and hover.realm ~= "Stormrage" then return hover.name .. "-" .. hover.realm end
			return hover.name
		end }
		radial_env.CanGuildInvite = function() return true end
		radial_env.UnitInParty = function(unit) return unit == "mouseover" and hover.in_party end
		radial_env.UnitInRaid = function() return false end
		radial_env.IsInGroup = function() return hover.in_group end
		radial_env.IsInRaid = function() return hover.in_raid end
		radial_env.UnitIsGroupLeader = function() return hover.leader end
		radial_env.UnitIsGroupAssistant = function() return hover.assistant end
		radial_env.GetRaidTargetIndex = function(unit)
			if unit == "mouseover" or unit == (hover.token or "party1") then return hover.marked end
		end
		radial_env.FollowUnit = log("follow")
		radial_env.FocusUnit = log("focus")
		radial_env.SetRaidTarget = log("mark")
		radial_env.InitiateTrade = log("trade")
		radial_env.InspectUnit = log("inspect")
		radial_env.InitiateRolePoll = log("role_check")
		radial_env.RemoveRaidTargets = log("clear_marks")
		radial_env.ChatFrameUtil = { SendTell = log("whisper") }
		if real_wheel then
			local _, _, made, cursor = drawn_wheel(radial_addon, radial_env)
			seen.cursor = cursor
			cursor.x, cursor.y = 960, 540
			seen.render = function()
				for _, object in ipairs(made) do
					if object.name == "EverlookRadialWheel" then object.scripts.OnUpdate(object, 0.016) end
				end
			end
		else
			radial_addon.wheel.open = function(texts, x, y) seen.opened = { texts = texts, x = x, y = y } end
			radial_addon.wheel.selected = function() return seen.index end
			radial_addon.wheel.close = function() seen.opened = nil; seen.closed = seen.closed + 1 end
		end
		radial_addon.module.set("radial_menu", "enabled", true)
		local function press() button.scripts.PreClick(button, "LeftButton", true); button.scripts.PostClick(button, "LeftButton", true) end
		-- Letting go chooses a wedge by number, or nothing. The macro is read between the two click scripts,
		-- which is when the secure handler would run it.
		local function release(index)
			seen.index = index
			button.scripts.PreClick(button, "LeftButton", false)
			local fired = { type = button.attributes.type, macrotext = button.attributes.macrotext,
				unit = button.attributes.unit, marker = button.attributes.marker, action = button.attributes.action }
			-- Relevant native handlers from Blizzard's SlashCommands and SecureTemplates:
			-- /follow passes its argument to FollowUnit; /tm resolves its conditional unit.
			if fired.macrotext then
				local name = fired.macrotext:match("^/follow (.+)$")
				if name then radial_env.FollowUnit(name) end
				local marker = fired.macrotext:match("^/tm %[@mouseover,exists%] (%d+)$")
				if marker and radial_env.UnitExists("mouseover") then radial_env.SetRaidTarget("mouseover", tonumber(marker)) end
				if fired.macrotext == "/focus [@mouseover,exists]" and radial_env.UnitExists("mouseover") then radial_env.FocusUnit("mouseover") end
			elseif fired.type == "focus" and radial_env.UnitExists(fired.unit) then radial_env.FocusUnit(fired.unit)
			elseif fired.type == "raidtarget" and radial_env.UnitExists(fired.unit) then
				if fired.action == "clear" then radial_env.SetRaidTarget(fired.unit, 0)
				elseif fired.action == "set" and radial_env.GetRaidTargetIndex(fired.unit) ~= fired.marker then radial_env.SetRaidTarget(fired.unit, fired.marker) end
			end
			button.scripts.PostClick(button, "LeftButton", false)
			return fired
		end
		local function words(list) return table.concat(list or {}, ",") end
		return radial_env, hover, seen, radial_addon, button, press, release, words, event
	end
	do
		local _, hover, seen, _, _, press, release = radial_fixture(true)
		hover.exists, hover.can_attack, hover.token = true, true, "nameplate1"
		press()
		seen.render()
		hover.exists = false
		seen.cursor.y = 640
		release()
		check("focus follows a flick completed between the last rendered frame and key release",
			#seen.calls == 1 and seen.calls[1].name == "focus" and seen.calls[1][1] == "nameplate1")
	end
	do
		local _, hover, seen, _, _, press, release = radial_fixture(true)
		hover.exists, hover.can_attack, hover.token = true, true, "nameplate1"
		press()
		seen.cursor.y = 640
		seen.render()
		seen.cursor.y = 540
		release()
		check("returning to the centre before release cancels a previously highlighted focus", #seen.calls == 0)
	end
	do
		local _, hover, seen, _, _, press, release = radial_fixture(true)
		hover.exists, hover.is_player, hover.realm = true, true, nil
		press()
		seen.render()
		local angle = 2 * math.pi * 6 / 8
		seen.cursor.x, seen.cursor.y = 960 + math.sin(angle) * 100, 540 + math.cos(angle) * 100
		hover.exists = false
		release()
		check("follow also uses the cursor at release instead of the last painted selection",
			#seen.calls == 1 and seen.calls[1].name == "follow" and seen.calls[1][1] == "Thrall")
	end
	do
		local _, hover, seen, _, _, press, release = radial_fixture(true)
		hover.exists, hover.can_attack, hover.token = true, true, "nameplate1"
		press()
		seen.render()
		seen.cursor.y = 440
		hover.exists = false
		release()
		check("skull uses the final cursor position when released between frames",
			#seen.calls == 1 and seen.calls[1].name == "mark" and seen.calls[1][1] == "nameplate1" and seen.calls[1][2] == 8)
	end
	do
		local env_r, hover, seen, radial_addon, button, press = radial_fixture()
		check("the radial button is one secure action button", button and button.template == "SecureActionButtonTemplate")
		check("it is clicked on key down and key up", button.clicks and button.clicks[1] == "AnyDown" and button.clicks[2] == "AnyUp")
		check("its action waits for the key to come up", button.attributes.useOnKeyDown == false and button.attributes.type == nil)
		check("it is a live button that no one can see or click", button.mouse == false and button.alpha == 0 and button.shown == true and button.width == 1 and button.height == 1)
		local radial_module
		for _, module in ipairs(radial_addon.module.modules) do
			if module.id == "radial_menu" then radial_module = module end
		end
		check("the page asks for the button's own binding", radial_module and radial_module.keybinding == "CLICK EverlookRadialButton:LeftButton")
		radial_addon.module.set("radial_menu", "enabled", false)
		press()
		check("a disabled module opens nothing", seen.opened == nil)
	end
	do
		local env_r, hover, seen, _, button, press, release, words = radial_fixture()
		press()
		check("the ground gets the four pings", words(seen.opened.texts) == "Attack,Warning,On my way,Assist")
		check("the wheel opens at the cursor in interface units", seen.opened.x == 200 and seen.opened.y == 300)
		local fired = release(3)
		check("a ping is a secure macro and nothing else", fired.type == "macro" and fired.macrotext == "/ping 3" and #seen.calls == 0)
		check("the wheel closes and the button is cleared", seen.closed == 1 and button.attributes.type == nil and button.attributes.macrotext == nil)
		press()
		check("letting go on the centre fires nothing", release(nil).type == nil and seen.closed == 2)
		press()
		check("a second press while open is ignored", (function() local before = seen.opened; press(); return seen.opened == before end)())
		release(nil)
		hover.exists = true
		press()
		check("a friendly creature gets the pings too", words(seen.opened.texts) == "Attack,Warning,On my way,Assist")
		release(nil)
		hover.over = {}
		seen.opened = nil
		press()
		check("interface under the cursor opens nothing", seen.opened == nil)
		check("and nothing is waiting to be released", release(1).type == nil)
		env_r.GetMouseFoci = function() return {} end
		hover.exists = false
		press()
		check("no frame under the cursor is the world", seen.opened ~= nil)
		release(nil)
	end
	do
		local env_r, hover, seen, _, button, press, release, words = radial_fixture()
		hover.exists, hover.is_player = true, true
		press()
		check("a player gets the player wedges", words(seen.opened.texts) == "Trade,Invite,Guild invite,Whisper,Add friend,Inspect,Follow,Duel")
		local function pick(index)
			press()
			return release(index)
		end
		release(nil)
		hover.exists = false
		local names = { [2] = "/invite ", [3] = "/ginvite ", [5] = "/friend ", [8] = "/duel " }
		hover.exists = true
		for index, command in pairs(names) do
			local fired = pick(index)
			check("wedge " .. index .. " is the macro " .. command .. "with the full name", fired.type == "macro" and fired.macrotext == command .. "Thrall-Orgrimmar")
		end
		seen.calls = {}
		check("trade is a call on the unit token", pick(1).type == nil and seen.calls[1].name == "trade" and seen.calls[1][1] == "party1")
		check("whisper opens a tell to the full name", pick(4).type == nil and seen.calls[2].name == "whisper" and seen.calls[2][1] == "Thrall-Orgrimmar")
		check("inspect is a call on the unit token", pick(6).type == nil and seen.calls[3].name == "inspect" and seen.calls[3][1] == "party1")
		hover.realm = nil
		check("a player on your realm gets your realm", pick(2).macrotext == "/invite Thrall-Stormrage")
		hover.realm = "Orgrimmar"
		env_r.CanGuildInvite = function() return false end
		press()
		check("guild invite is left out without the permission", words(seen.opened.texts) == "Trade,Invite,Whisper,Add friend,Inspect,Follow,Duel")
		release(nil)
		env_r.CanGuildInvite = nil
		press()
		check("guild invite is left out when the permission check is missing", words(seen.opened.texts) == "Trade,Invite,Whisper,Add friend,Inspect,Follow,Duel")
		release(nil)
		env_r.CanGuildInvite = function() return true end
		seen.calls = {}
		hover.gone = true
		pick(1); pick(6)
		check("a unit with no token gets no trade or inspect", #seen.calls == 0)
		hover.gone = false
		env_r.InitiateTrade = nil
		check("a missing game function does nothing and raises nothing", pcall(pick, 1) and #seen.calls == 0)
		env_r.InitiateTrade = function() end
		env_r.issecretvalue = function(value) return value == "Thrall" end
		press()
		check("a secret name leaves the wedges that need no name", words(seen.opened.texts) == "Trade,Inspect")
		release(nil)
		env_r.issecretvalue = function(value) return value == "Player-1-0A" end
		press()
		check("a secret guid gives the ground wheel", words(seen.opened.texts) == "Attack,Warning,On my way,Assist")
		release(nil)
		env_r.issecretvalue = nil
		hover.exists = true
		seen.calls = {}
		press()
		env_r.issecretvalue = function(value) return value == "Player-1-0A" end
		check("a guid that turns secret before the key comes up does not trade", release(1).type == nil and #seen.calls == 0)
		env_r.issecretvalue = nil
	end
	do
		local _, hover, seen, _, button, press, release = radial_fixture()
		hover.exists, hover.is_player = true, true
		press()
		hover.exists, hover.name, hover.realm = false, "Other", "OtherRealm"
		release(7)
		check("follow uses the captured full name with the native menu's exact lookup",
			#seen.calls == 1 and seen.calls[1].name == "follow" and seen.calls[1][1] == "Thrall-Orgrimmar" and seen.calls[1][2] == true)
	end
	do
		local _, hover, seen, _, _, press, release = radial_fixture()
		hover.exists, hover.is_player, hover.realm = true, true, nil
		press()
		hover.exists = false
		release(7)
		check("follow does not append your realm to a local player's name", #seen.calls == 1 and seen.calls[1][1] == "Thrall")
		hover.exists, hover.realm = true, "Stormrage"
		press()
		hover.exists = false
		release(7)
		check("follow omits an explicitly returned same realm too", #seen.calls == 2 and seen.calls[2][1] == "Thrall")
		hover.exists, hover.native_name = true, "Thrall-Surname"
		press()
		hover.exists = false
		release(7)
		check("follow preserves the native helper's full name", #seen.calls == 3 and seen.calls[3][1] == "Thrall-Surname")
	end
	do
		local env_r, hover, seen, _, _, press, release, words = radial_fixture()
		hover.exists, hover.is_player = true, true
		env_r.NameUtil = nil
		env_r.GetUnitName = function(unit, show_realm)
			check("the older native name helper receives the captured mouseover", unit == "mouseover" and show_realm == true)
			return "Thrall"
		end
		press()
		hover.exists = false
		release(7)
		check("the older name helper also leaves the local realm off", #seen.calls == 1 and seen.calls[1][1] == "Thrall")
		hover.exists = true
		env_r.GetUnitName = nil
		press()
		check("no name helper leaves follow out", words(seen.opened.texts) == "Trade,Invite,Guild invite,Whisper,Add friend,Inspect,Duel")
		release(nil)
		env_r.NameUtil = { GetUnmodifiedUnitFullName = function() return "secret-name" end }
		env_r.issecretvalue = function(value) return value == "secret-name" end
		press()
		check("a secret native name leaves follow out", words(seen.opened.texts) == "Trade,Invite,Guild invite,Whisper,Add friend,Inspect,Duel")
		release(nil)
	end
	do
		local env_r, hover, seen, _, button, press, release = radial_fixture()
		hover.exists, hover.can_attack, hover.token = true, true, "nameplate7"
		press()
		hover.exists = false
		release(1)
		check("focus reaches the captured enemy after the cursor leaves it", #seen.calls == 1 and seen.calls[1].name == "focus" and seen.calls[1][1] == "nameplate7")
		check("focus attributes are cleared after release", button.attributes.type == nil and button.attributes.unit == nil)
		hover.exists = true
		press()
		hover.mouse_guid = "Creature-other"
		seen.calls = {}
		release(1)
		check("moving onto another enemy keeps focus on the captured one", #seen.calls == 1 and seen.calls[1][1] == "nameplate7")
		hover.mouse_guid = nil
		press()
		hover.token_guid = "Creature-other"
		seen.calls = {}
		check("focus skips a reused unit token", release(1).type == nil and #seen.calls == 0)
	end
	do
		local env_r, hover, seen, _, button, press, release = radial_fixture()
		hover.exists, hover.can_attack, hover.token = true, true, "nameplate7"
		press()
		hover.exists = false
		release(4)
		check("a skull reaches the captured enemy after the cursor leaves it",
			#seen.calls == 1 and seen.calls[1].name == "mark" and seen.calls[1][1] == "nameplate7" and seen.calls[1][2] == 8)
		check("the marker attributes are cleared after release", button.attributes.unit == nil and button.attributes.marker == nil and button.attributes.action == nil)
		seen.calls = {}
		hover.exists, hover.marked = true, 8
		press()
		hover.exists = false
		release(7)
		check("clear mark also reaches the captured enemy", #seen.calls == 1 and seen.calls[1][1] == "nameplate7" and seen.calls[1][2] == 0)
		hover.exists, hover.marked = true, nil
		press()
		hover.mouse_guid = "Creature-other"
		seen.calls = {}
		release(5)
		check("moving onto another enemy still marks the original one", #seen.calls == 1 and seen.calls[1][1] == "nameplate7" and seen.calls[1][2] == 7)
		hover.mouse_guid = nil
		press()
		hover.token_guid = "Creature-other"
		seen.calls = {}
		check("a reused token cannot mark a different enemy", release(4).type == nil and #seen.calls == 0)
		hover.token_guid = nil
		press()
		hover.gone = true
		check("a captured token is kept when GUID lookup stops resolving it", release(6).unit == "nameplate7")
		hover.gone = false
		press()
		local unit_guid = env_r.UnitGUID
		env_r.UnitGUID = function() return nil end
		seen.calls = {}
		check("an enemy with no matching token is skipped", release(4).type == nil and #seen.calls == 0)
		env_r.UnitGUID = unit_guid
		press()
		release(4)
		hover.exists = false
		press()
		check("a later ping has no unit or marker left over", release(1).macrotext == "/ping 1" and button.attributes.unit == nil and button.attributes.marker == nil)
	end
	do
		local env_r, hover, seen, _, button, press, release, words = radial_fixture()
		hover.exists, hover.is_player, hover.in_party = true, true, true
		press()
		check("a group member gets their own wedges", words(seen.opened.texts) == "Whisper,Trade,Inspect,Follow,Set focus,Assist")
		local focused = release(5)
		check("a group member's focus uses the captured token", focused.type == "focus" and focused.unit == "party1")
		press()
		check("an assist ping is the plain ping macro", release(6).macrotext == "/ping 4")
		press()
		hover.exists = false
		seen.calls = {}
		release(4)
		check("a group member's follow uses the same captured full name", #seen.calls == 1 and seen.calls[1].name == "follow" and seen.calls[1][1] == "Thrall-Orgrimmar" and seen.calls[1][2] == true)
	end
	do
		local env_r, hover, seen, _, button, press, release, words = radial_fixture()
		hover.exists, hover.can_attack = true, true
		press()
		check("a hostile creature gets focus, pings and marks", words(seen.opened.texts) == "Set focus,Attack,Assist,Skull,Cross,Square")
		local focused = release(1)
		check("a hostile unit's focus uses the captured token", focused.type == "focus" and focused.unit == "party1")
		press()
		check("attack is the plain ping macro", release(2).macrotext == "/ping 1")
		local marks = { [4] = 8, [5] = 7, [6] = 6 }
		for index, mark in pairs(marks) do
			press()
			local fired = release(index)
			check("wedge " .. index .. " marks the captured unit with " .. mark,
				fired.type == "raidtarget" and fired.unit == "party1" and fired.marker == mark and fired.action == "set")
		end
		hover.marked = 8
		press()
		check("a marked unit offers to clear its mark", words(seen.opened.texts) == "Set focus,Attack,Assist,Skull,Cross,Square,Clear mark")
		local cleared = release(7)
		check("clearing is the native clear action on the captured unit", cleared.type == "raidtarget" and cleared.unit == "party1" and cleared.action == "clear")
		hover.marked = nil
		hover.is_player = true
		press()
		check("a hostile player can also be inspected", words(seen.opened.texts) == "Set focus,Attack,Assist,Skull,Cross,Square,Inspect")
		seen.calls = {}
		local fired = release(7)
		check("inspect stays a call on the unit token", fired.type == nil and seen.calls[1].name == "inspect" and seen.calls[1][1] == "party1")
		hover.is_player = false
		hover.in_group, hover.in_raid = true, true
		press()
		check("a raid member without lead or assist cannot mark", words(seen.opened.texts) == "Set focus,Attack,Assist")
		release(nil)
		hover.assistant = true
		press()
		check("a raid assistant can mark", words(seen.opened.texts) == "Set focus,Attack,Assist,Skull,Cross,Square")
		release(nil)
	end
	do
		local env_r, hover, seen, _, button, press, release, words = radial_fixture()
		hover.exists, hover.is_self = true, true
		press()
		check("your own character outside a group gets the pings", words(seen.opened.texts) == "Attack,Warning,On my way,Assist")
		release(nil)
		hover.in_group = true
		press()
		check("a member who does not lead gets the pings", words(seen.opened.texts) == "Attack,Warning,On my way,Assist")
		release(nil)
		hover.leader = true
		press()
		check("the leader gets the group tools", words(seen.opened.texts) == "Ready check,Role check,Pull timer,Clear marks")
		check("ready check is a macro", release(1).macrotext == "/readycheck")
		press()
		seen.calls = {}
		check("role check is a call", release(2).type == nil and seen.calls[1].name == "role_check")
		press()
		check("the pull timer is a ten second macro", release(3).macrotext == "/countdown 10")
		press()
		check("clear marks is a call", release(4).type == nil and seen.calls[2].name == "clear_marks")
		hover.leader, hover.assistant = false, true
		press()
		check("an assistant gets the group tools too", #seen.opened.texts == 4)
		release(nil)
	end
	do
		local env_r, hover, seen, radial_addon, button, press, release, words, event = radial_fixture()
		env_r.InCombatLockdown = function() return true end
		press()
		check("in combat nothing opens", seen.opened == nil)
		env_r.InCombatLockdown = function() return false end
		press()
		env_r.InCombatLockdown = function() return true end
		check("a wedge chosen after combat starts fires nothing", release(1).type == nil)
		env_r.InCombatLockdown = function() return false end
		press()
		seen.index = 1
		button.scripts.PreClick(button, "LeftButton", false)
		env_r.InCombatLockdown = function() return true end
		button.scripts.PostClick(button, "LeftButton", false)
		check("a macro left on the button by a fight is kept until the fight ends", button.attributes.type == "macro")
		env_r.InCombatLockdown = function() return false end
		event("PLAYER_REGEN_ENABLED")
		check("and cleared when it ends", button.attributes.type == nil and button.attributes.macrotext == nil)
		press()
		radial_addon.module.set("radial_menu", "enabled", false)
		seen.index = 1
		button.scripts.PreClick(button, "LeftButton", false)
		check("turning the module off mid-press fires nothing but still closes the wheel", button.attributes.type == nil and seen.opened == nil)
	end

	-- Smart island: a closed experience chip that opens into one data bar.
	local function island_world()
		local addon, env, event, hooks, tickers, frames = load_qol()
		local afters, state = {}, {
			xp = 450, xp_max = 1000, level = 12, money = 12345,
			hour = 14, minute = 5, time = 100,
			slots = { [1] = { 40, 50 }, [5] = { 10, 20 } },
			bags = { [0] = 6, [1] = 2 }, bag_families = {},
			health_reads = 0, name_reads = 0, power_reads = 0,
		}
		local function forbidden(kind)
			return function()
				state[kind] = (state[kind] or 0) + 1
				error(kind .. " is not a safe island readout")
			end
		end
		env.C_Timer.After = function(delay, callback)
			afters[#afters + 1] = { delay = delay, callback = callback }
		end
		env.UIParent = {}
		env.BACKPACK_CONTAINER = 0
		env.NUM_BAG_SLOTS = 1
		env.INVSLOT_FIRST_EQUIPPED = 1
		env.INVSLOT_LAST_EQUIPPED = 19
		env.UnitXP = function() return state.xp end
		env.UnitXPMax = function() return state.xp_max end
		env.UnitLevel = function() return state.level end
		env.GetMoney = function() return state.money end
		env.GetGameTime = function() return state.hour, state.minute end
		env.GetTime = function() return state.time end
		env.GetInventoryItemDurability = function(slot)
			local pair = state.slots[slot]
			if pair then return pair[1], pair[2] end
		end
		env.C_Container = {
			GetContainerNumFreeSlots = function(bag) return state.bags[bag] or 0, state.bag_families[bag] or 0 end,
		}
		env.C_Map = {
			GetBestMapForUnit = function() return 37 end,
			GetPlayerMapPosition = function()
				return { GetXY = function() return 0.5, 0.25 end }
			end,
		}
		env.UnitHealth = forbidden("health_reads")
		env.UnitHealthMax = forbidden("health_reads")
		env.UnitPower = forbidden("power_reads")
		env.UnitName = forbidden("name_reads")
		env.MainMenuExpBar = { Hide = function() error("the default experience bar must stay") end }
		env.StatusTrackingBarManager = { Hide = function() error("the default experience bar must stay") end }
		env.EverlookMinimapButton = { SetParent = function() error("the minimap button must stay") end }
		-- The geometry tests measure the plain level chip. The wider pill has its own tests.
		addon.module.set("smart_island", "closed_xp", false)
		return addon, env, event, state, afters, tickers, frames, hooks
	end
	local function fire_after(afters, delay)
		for index = 1, #afters do
			if afters[index].delay == delay and not afters[index].done then
				afters[index].done = true
				afters[index].callback()
				return true
			end
		end
	end
	local function finish_animations(frames)
		local pending = {}
		for _, frame in ipairs(frames) do
			for _, group in ipairs(frame.animation_groups or {}) do
				if group.playing then pending[#pending + 1] = group end
			end
		end
		for _, group in ipairs(pending) do
			group.playing = false
			for _, animation in ipairs(group.animations) do animation.progress = 1 end
			if group.scripts.OnFinished then group.scripts.OnFinished(group) end
		end
	end
	local function last_toast_text(addon)
		local toasts = addon.smart_island.view().toasts
		return toasts[#toasts] and toasts[#toasts].text
	end
	local function island_fill(frames)
		for index = 1, #frames do
			if frames[index].value ~= nil then return frames[index] end
		end
	end
	local function secret_stat()
		local value = newproxy(true)
		local meta = getmetatable(value)
		meta.__add = function() error("arithmetic on a secret value") end
		meta.__sub = function() error("arithmetic on a secret value") end
		meta.__mul = function() error("arithmetic on a secret value") end
		meta.__div = function() error("arithmetic on a secret value") end
		meta.__unm = function() error("arithmetic on a secret value") end
		meta.__lt = function() error("comparison on a secret value") end
		meta.__le = function() error("comparison on a secret value") end
		return value
	end
	local function quest_world()
		local addon, env, event, state, afters, tickers, frames = island_world()
		state.quests, state.watched, state.selected = {
			{ questID = 21, title = "Nearby dangerous", level = 18, distance = 100 },
			{ questID = 22, title = "Suitable farther", level = 12, distance = 800 },
			{ questID = 23, title = "Ready to return", level = 40, distance = 400, ready = true },
			{ questID = 24, title = "Across the sea", level = 12, distance = 1, remote = true },
		}, { 21, 22 }, 22
		for _, quest in ipairs(state.quests) do quest.objectives = { { text = "Collect things", numFulfilled = 1, numRequired = 6, finished = false } } end
		local function find(id)
			for _, quest in ipairs(state.quests) do if quest.questID == id then return quest end end
		end
		env.C_QuestLog = {
			GetNumQuestLogEntries = function() return #state.quests end,
			GetInfo = function(index) return state.quests[index] end,
			GetNumQuestWatches = function() return #state.watched end,
			GetQuestIDForQuestWatchIndex = function(index) return state.watched[index] end,
			GetQuestObjectives = function(id) return find(id).objectives end,
			GetDistanceSqToQuest = function(id)
				local quest = find(id)
				return quest.distance and quest.distance * quest.distance, not quest.remote
			end,
			ReadyForTurnIn = function(id) return find(id).ready or false end,
		}
		env.C_SuperTrack = { GetSuperTrackedQuestID = function() return state.selected end }
		addon.module.set("smart_island", "enabled", true)
		-- The older quest tests exercise the fallbacks that apply without a suggestion. The suggestion has its own tests.
		addon.module.set("smart_island", "quest_plan", false)
		-- Quest events collapse inside half a second. These tests treat each event as its own moment.
		local burst_event = event
		event = function(name, ...)
			if name:find("^QUEST_") or name == "SUPER_TRACKING_CHANGED" then state.time = state.time + 1 end
			return burst_event(name, ...)
		end
		return addon, env, event, state, afters, tickers, frames
	end
	do
		local addon, env, event, state, _, tickers = quest_world()
		check("quest context starts off", addon.smart_island.view().quests == nil)
		addon.module.set("smart_island", "quest_context", true)
		local view = addon.smart_island.view().quests
		check("quest context follows native super tracking", view.current.id == 22 and view.current.distance == 800)
		check("native objectives retain readable counts", view.current.objectives[1].fulfilled == 1 and view.current.objectives[1].required == 6)
		addon.module.set("smart_island", "quest_plan", true)
		view = addon.smart_island.view().quests
		check("ready quests use distance without encounter difficulty", view.order[1].id == 23 and view.order[1].ready)
		check("level suitability outweighs a nearby dangerous quest", view.order[2].id == 22 and view.order[3].id == 21)
		check("another continent sorts after local quests", view.order[4].id == 24 and view.order[4].distance == nil)
		addon.smart_island.pin_quest(21)
		check("manual pin overrides a recommendation without changing native tracking", addon.smart_island.view().quests.current.id == 21 and state.selected == 22)
		addon.smart_island.pin_quest(nil)
		check("releasing a quest pin restores the suggestion", addon.smart_island.view().quests.current.id == 23)
		state.quests[3].distance = 1200
		event("QUEST_LOG_UPDATE")
		check("a better candidate replaces the recommendation", addon.smart_island.view().quests.suggested == 22)
		state.quests[3].distance = 700
		event("QUEST_LOG_UPDATE")
		check("recommendation holds through a small score change", addon.smart_island.view().quests.suggested == 22)
		state.quests[3].distance = 600
		event("QUEST_LOG_UPDATE")
		check("twenty percent improvement changes recommendation", addon.smart_island.view().quests.suggested == 23)
		local prior = addon.smart_island.view().quests.order[1].distance
		state.quests[3].distance = 550
		state.time = state.time + 1
		tickers[1].callback()
		check("current distance refreshes before the ordered plan", addon.smart_island.view().quests.current.distance == 550 and addon.smart_island.view().quests.order[1].distance == prior)
		state.time = state.time + 2
		tickers[1].callback()
		check("ordered plan refreshes at three seconds", addon.smart_island.view().quests.order[1].distance == 550)
		addon.smart_island.pin_quest(21)
		table.remove(state.quests, 1)
		event("QUEST_LOG_UPDATE")
		check("removing a quest releases its stale pin", addon.smart_island.view().quests.pinned == nil)
		view.current.title = "Mutated copy"
		check("quest snapshots cannot mutate the display model", addon.smart_island.view().quests.current.title ~= "Mutated copy")
	end
	do
		local addon, env, event, state = quest_world()
		state.quests[3].ready, state.quests[3].level = false, 12
		state.quests[3].distance = 800
		addon.module.set("smart_island", "quest_context", true)
		addon.module.set("smart_island", "quest_plan", true)
		check("equivalent quest costs have deterministic ID order", addon.smart_island.view().quests.order[1].id == 22 and addon.smart_island.view().quests.order[2].id == 23)
		addon.module.set("smart_island", "quest_level_weight", 0)
		check("zero level weight still penalizes quests far above your level", addon.smart_island.view().quests.order[3].id == 21)
		state.quests[1].level = 13
		event("QUEST_LOG_UPDATE")
		check("a close suitable quest becomes a suggestion", addon.smart_island.view().quests.suggested == 21)
		state.quests[1].level, state.quests[1].distance = 13, 300
		state.quests[2].distance = 450
		event("QUEST_LOG_UPDATE")
		addon.module.set("smart_island", "quest_level_weight", 2)
		check("level weighting can favor a farther matching quest", addon.smart_island.view().quests.order[1].id == 22)
		addon.module.set("smart_island", "quest_distance_weight", 4)
		check("distance weighting can favor a nearer suitable quest", addon.smart_island.view().quests.order[1].id == 21)
	end

	do
		local addon, env, event, state = quest_world()
		addon.module.set("smart_island", "quest_context", true)
		addon.module.set("smart_island", "quest_recent", true)
		check("logging in does not imply objective progress", addon.smart_island.view().quests.current.id == 22)
		state.quests[1].objectives[1].numFulfilled = 2
		event("QUEST_WATCH_UPDATE", 21)
		check("watched objective progress gets temporary attention", addon.smart_island.view().quests.current.id == 21)
		state.time = state.time + 16
		event("QUEST_LOG_UPDATE")
		check("progress attention expires back to selected quest", addon.smart_island.view().quests.current.id == 22)
		addon.module.set("smart_island", "quest_nearby", true)
		check("nearby attention considers watched quests", addon.smart_island.view().quests.current.id == 21)
		local secret = secret_stat()
		env.issecretvalue = function(value) return rawequal(value, secret) end
		env.C_QuestLog.GetDistanceSqToQuest = function() return secret, true end
		state.quests[1].level = secret
		state.quests[1].objectives[1].numFulfilled = secret
		state.quests[1].objectives[1].text = secret
		addon.module.set("smart_island", "quest_plan", true)
		local view = addon.smart_island.view().quests
		check("secret distances and objective counts are omitted", view.order[1].distance == nil and view.order[4].id == 21)
		addon.smart_island.pin_quest(21)
		view = addon.smart_island.view().quests
		check("secret levels and objectives never imply progress", view.current.level == nil and view.current.objectives[1].fulfilled == nil and view.current.objectives[1].text == "Objective unavailable")
		addon.module.set("smart_island", "quest_context", false)
		check("disabling quest context clears its pin and view", addon.smart_island.view().quests == nil)
	end

	do
		local addon, env, event, state, _, _, frames = quest_world()
		addon.module.set("smart_island", "quest_context", true)
		local function label(text)
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions) do if region.text == text and region.shown ~= false then return region end end
			end
		end
		check("wide quest capsule replaces the level chip", addon.smart_island.view().width > 100 and label("Suitable farther"))
		addon.module.set("smart_island", "quest_title", false)
		check("compact quest capsule keeps the native distance", addon.smart_island.view().width < 130 and label("~800 yd"))
		addon.module.set("smart_island", "quest_plan", true)
		env.everlook_smart_island_key("down")
		check("expanded quest inspection shows objective counts", label("Collect things  1/6"))
		check("expanded quest plan is headed Next up and explains its order", label("NEXT UP") and label("Closest to you and matched to your level"))
		local pin
		for _, frame in ipairs(frames) do if frame.name == "EverlookIslandPinQuest" then pin = frame end end
		local current = addon.smart_island.view().quests.current
		local release_button
		for _, frame in ipairs(frames) do if frame.name == "EverlookIslandReleaseQuest" then release_button = frame end end
		local title, count = label(current.title), label("Collect things  1/6")
		-- 12 edge, a 14 high title, 4 to the explanation, 14 high, 8 to the first objective.
		check("the card's lines follow the spacing scale: edge, within a group, between siblings",
			title and title.point[5] == -12 and count.point[5] == -(12 + 14 + 4 + 14 + 8) and count.point[4] == 12 + 16 + 8)
		check("the pin action sits in the quests heading row, not in the card, and only the one that applies shows",
			pin.shown ~= false and pin.point[1] == "TOPRIGHT" and pin.parent.shown ~= false and release_button.shown == false)
		pin.scripts.OnClick(pin)
		check("native pin button changes only Island context", addon.smart_island.view().quests.pinned == 23 and state.selected == 22)
		local release
		for _, frame in ipairs(frames) do if frame.name == "EverlookIslandReleaseQuest" then release = frame end end
		release.scripts.OnClick(release)
		check("release button resumes quest suggestion", addon.smart_island.view().quests.pinned == nil)
		event("QUEST_TURNED_IN", 22, 100, 123)
		check("quest completion feed starts off", #addon.smart_island.view().notices == 0)
		addon.module.set("smart_island", "source_quest_completion", true)
		event("QUEST_TURNED_IN", 23, 100, 123)
		local notice = addon.smart_island.view().notices[1]
		check("native quest turn-in reports readable rewards", notice.kind == "quest" and notice.money == 123 and notice.detail == "Ready to return")
		addon.module.set("smart_island", "quest_plan", false)
		event("QUEST_TURNED_IN", 21, 40, 0)
		notice = addon.smart_island.view().notices[#addon.smart_island.view().notices]
		check("a completed quest keeps its log title when it is not the selected one", notice.detail == "Nearby dangerous" and notice.money == 123 and notice.count == 2)
		addon.module.set("smart_island", "quest_context", false)
		event("QUEST_TURNED_IN", 22, 10, 50)
		notice = addon.smart_island.view().notices[#addon.smart_island.view().notices]
		check("completed quests keep the log title while the capsule is off", addon.smart_island.view().quests == nil and notice.detail == "Suitable farther" and notice.money == 173 and notice.count == 3)
	end

	do
		local addon, env, _, state, _, _, frames = quest_world()
		addon.module.set("smart_island", "quest_context", true)
		state.quests[2].objectives = {
			{ text = "Slay the first", numFulfilled = 8, numRequired = 8, finished = true },
			{ text = "Slay the second", numFulfilled = 2, numRequired = 5, finished = false },
		}
		addon.island_quests.refresh(true)
		env.everlook_smart_island_key("down")
		local function shown(text)
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions or {}) do if region.shown ~= false and type(region.text) == "string" and region.text:find(text, 1, true) then return region end end
			end
		end
		local done, todo = shown("Slay the first"), shown("Slay the second")
		local rings, checks = 0, 0
		for _, frame in ipairs(frames) do
			if frame.cooldown and frame.shown == true and frame.width == 16 then rings = rings + 1 end
			for _, region in ipairs(frame.regions or {}) do
				if region.atlas == "common-icon-checkmark" and region.shown ~= false then checks = checks + 1 end
			end
		end
		check("a finished objective steps back and takes a check, one still to do stays bright and takes a ring",
			done and todo and done.color[1] < 0.6 and todo.color[1] > 0.9 and rings == 1 and checks == 1)
		local pin_link
		for _, frame in ipairs(frames) do if frame.name == "EverlookIslandPinQuest" then pin_link = frame end end
		check("the pin action shows while a quest is followed", pin_link.shown ~= false)
		addon.module.set("smart_island", "quest_context", false)
		check("turning quest tracking off takes the pin action away and narrows the island",
			pin_link.shown == false and addon.smart_island.view().width == 440)
	end
	do
		local addon, env, _, state = quest_world()
		addon.module.set("smart_island", "quest_context", true)
		addon.module.set("smart_island", "quest_plan", true)
		env.everlook_smart_island_key("down")
		local view = addon.smart_island.view()
		check("the quest card starts at its top beside an empty notice list", #view.notices == 0 and view.quest_height > 0 and view.quest_offset == 0)
		check("a typical card with its route fits without scrolling", view.quest_height <= view.scroll_height)
		-- On a short screen the panes lose height and the card has to scroll.
		env.UIParent.GetHeight = function() return 330 end
		env.Everlook.island.notify({ text = "A notice" })
		view = addon.smart_island.view()
		check("a tall card scrolls on its own, and the notices stay where they were",
			view.quest_height > view.scroll_height and view.quest_offset == 0 and view.scroll_offset == 0)
		addon.smart_island.scroll_quests(80)
		view = addon.smart_island.view()
		check("scrolling the quests moves only the quests", view.quest_offset == 80 and view.scroll_offset == 0)
		env.Everlook.island.notify({ text = "Another notice" })
		check("a new notice does not drag the card down", addon.smart_island.view().quest_offset == 80)
		addon.smart_island.scroll_quests(100000)
		check("the quest offset stops at the end of the card", addon.smart_island.view().quest_offset == view.quest_height - view.scroll_height)
	end

	do
		local addon, env, event, state, _, _, frames = quest_world()
		addon.module.set("smart_island", "quest_context", true)
		state.guid, state.server = "Player-1-UI", 2000000
		env.GetServerTime = function() return state.server end
		env.UnitGUID = function() return state.guid end
		env.GetXPExhaustion = function() return nil end
		env.GetMaxPlayerLevel = function() return 60 end
		state.xp = 600
		event("PLAYER_XP_UPDATE")
		addon.module.set("smart_island", "feed_experience", true)
		env.everlook_smart_island_key("down")
		local status, quests_heading, notices_heading, names, hour, quest_pane, notice_pane
		for _, object in ipairs(frames) do
			for _, region in ipairs(object.regions or {}) do
				if region.shown ~= false then
					if region.text == "STATUS" then status = region end
					if region.text == "QUESTS" then quests_heading = region end
					if region.text == "NOTIFICATIONS" then notices_heading = region end
					if region.text and region.text:find("EXPERIENCE", 1, true) then names = region end
					if region.text == "HOUR" then hour = region end
				end
			end
			if object.scroll_child and object.point then
				if object.point[4] == 0 then quest_pane = object else notice_pane = object end
			end
		end
		-- 720 wide, split at 46%: the left column is 331 and the right begins there.
		check("the island is two columns wide when there is a quest to show", addon.smart_island.view().width == 720)
		check("the Experience table and the quests share the left column's edge", names and quests_heading
			and names.point[4] == 12 and quests_heading.point[4] == 12)
		check("Status and the notifications share the right column's edge", status and notices_heading
			and status.point[4] == 331 + 12 and notices_heading.point[4] == 331 + 12)
		check("the table and Status begin on one line", status and hour and hour.point[5] == status.point[5])
		check("the two panes share a top and a height, and the left ends where the right begins",
			quest_pane and notice_pane and quest_pane.point[5] == notice_pane.point[5] and quest_pane.height == notice_pane.height
			and quest_pane.width == notice_pane.point[4] and quest_pane.width + notice_pane.width == 720)
	end
	do
		local addon, env, event, state, _, _, frames = quest_world()
		addon.module.set("smart_island", "quest_context", true)
		env.everlook_smart_island_key("down")
		check("with a quest the island is wide", addon.smart_island.view().width == 720)
		state.quests, state.watched, state.selected = {}, {}, nil
		event("QUEST_LOG_UPDATE")
		check("with no quest to follow or suggest it narrows to the notifications alone", addon.smart_island.view().width == 440)
		local pane
		for _, object in ipairs(frames) do
			-- The quests list is made before the notifications list.
			if object.scroll_child and not pane then pane = object end
		end
		check("and the quests column is hidden", pane and pane.shown == false)
		state.quests, state.watched, state.selected = { { questID = 21, title = "Back again", level = 12, distance = 100 } }, { 21 }, 21
		state.quests[1].objectives = { { text = "Return", finished = false } }
		event("QUEST_LOG_UPDATE")
		check("a quest brings the column and the width back", addon.smart_island.view().width == 720 and pane.shown ~= false)
	end
	do
		local addon, env, event, state, _, _, frames = quest_world()
		addon.module.set("smart_island", "quest_context", true)
		local function ring()
			for _, frame in ipairs(frames) do
				if frame.cooldown and frame.width == 24 and frame.shown == true then return frame end
			end
		end
		local seen = ring()
		check("rings keep addons that count cooldowns from printing a number on them", seen and seen.noCooldownCount == true)
		check("the closed quest capsule has a ring round its arrow, filled to the quest's progress",
			seen and math.abs((env.GetTime() - seen.cooldown.start) / seen.cooldown.duration - 1 / 6) < 1e-9 and seen.swipe_color[1] == 1)
		state.selected = 23
		state.watched = { 23 }
		event("SUPER_TRACKING_CHANGED")
		addon.module.set("smart_island", "quest_plan", true)
		event("QUEST_LOG_UPDATE")
		local done = ring()
		check("a quest ready to hand in fills its ring and turns it green",
			done and (env.GetTime() - done.cooldown.start) / done.cooldown.duration > 0.99 and done.swipe_color[1] < 0.6 and done.swipe_color[2] > 0.8)
	end
	do
		local function near(actual, expected)
			return type(actual) == "number" and math.abs(actual - expected) < 1e-4
		end
		local function arrow_on(frame)
			for _, region in ipairs(frame and frame.regions or {}) do
				if region.path == "Interface\\AddOns\\Everlook_Island\\assets\\island_arrow.tga" then return region end
			end
		end
		local addon, env, event, state, _, _, frames = quest_world()
		local bearing = addon.island_quests.bearing
		-- GetWorldPosFromMapPos on Elwynn 37: x grows north, y grows west.
		check("facing north, a point due north is straight ahead", type(bearing) == "function" and near(bearing(-7939.580078125 + 0.5 * (-10254.200195312 - -7939.580078125), 1535.4200439453 + 0.5 * (-1935.4200439453 - 1535.4200439453), -7939.580078125 + 0.25 * (-10254.200195312 - -7939.580078125), 1535.4200439453 + 0.5 * (-1935.4200439453 - 1535.4200439453), 0), 0))
		check("facing north, a point due west points left", near(bearing(0, 0, 0, 10, 0), math.pi / 2))
		check("facing north, a point due east points right", near(bearing(0, 0, 0, -10, 0), -math.pi / 2))
		check("facing the point puts the arrow straight ahead", near(bearing(0, 0, 0, 10, math.pi / 2), 0))
		check("Elwynn east points right", near(bearing(-7939.580078125 + 0.5 * (-10254.200195312 - -7939.580078125), 1535.4200439453 + 0.5 * (-1935.4200439453 - 1535.4200439453), -7939.580078125 + 0.5 * (-10254.200195312 - -7939.580078125), 1535.4200439453 + 0.75 * (-1935.4200439453 - 1535.4200439453), 0), -math.pi / 2))
		check("a point within a yard has no direction", bearing(0, 0, 0.5, 0, 0) == nil)
		local secret = secret_stat()
		env.issecretvalue = function(value) return rawequal(value, secret) end
		check("a secret facing has no direction", bearing(0, 0, 0, 10, secret) == nil)
		state.player_map, state.px, state.py, state.facing = 37, 0.5, 0.5, 0
		state.maps = {
			[37] = { continent = 0, origin_x = 0, origin_y = 0, width = 100, height = 100 },
			[40] = { continent = 0, origin_x = 0, origin_y = 0, width = 100, height = 100 },
			[12] = { continent = 1, origin_x = 0, origin_y = 0, width = 100, height = 100 },
		}
		env.GetPlayerFacing = function() return state.facing end
		env.C_Map.GetBestMapForUnit = function() return state.player_map end
		env.C_Map.GetPlayerMapPosition = function() return { x = state.px, y = state.py } end
		env.C_Map.GetWorldPosFromMapPos = function(map_id, pos)
			local spot = state.maps[map_id]
			if not spot or type(pos) ~= "table" or type(pos.x) ~= "number" or type(pos.y) ~= "number" then return end
			return spot.continent, { x = spot.origin_x - pos.y * spot.height, y = spot.origin_y - pos.x * spot.width }
		end
		local asked = {}
		env.C_QuestLog.GetNextWaypoint = function(id)
			asked[#asked + 1] = id
			for _, quest in ipairs(state.quests) do
				if quest.questID == id and quest.waypoint then return quest.waypoint.map, quest.waypoint.x, quest.waypoint.y end
			end
		end
		env.C_SuperTrack.SetSuperTrackedQuestID = function() error("the arrow must leave tracking alone") end
		for _, quest in ipairs(state.quests) do quest.waypoint = { map = 37, x = 0.5, y = 0.25 } end
		addon.module.set("smart_island", "quest_context", true)
		local function arrows()
			local capsule, inspection, closed_arrow, open_arrow
			for _, frame in ipairs(frames) do
				if frame.name == "EverlookIslandQuestCapsule" then capsule, closed_arrow = frame, arrow_on(frame) end
				if frame.name == "EverlookIslandQuestInspection" then inspection = frame end
			end
			for _, frame in ipairs(frames) do
				if frame.parent == inspection then open_arrow = arrow_on(frame) or open_arrow end
			end
			return capsule, inspection, closed_arrow, open_arrow
		end
		local capsule, inspection, closed_arrow, open_arrow = arrows()
		check("the closed capsule points toward the selected quest", asked[#asked] == 22 and closed_arrow and closed_arrow.shown and near(closed_arrow.rotation, 0))
		check("turning the character waits a tenth of a second", (function()
			state.facing = math.pi / 2
			capsule.scripts.OnUpdate(capsule, 0.08)
			return near(closed_arrow.rotation, 0)
		end)())
		capsule.scripts.OnUpdate(capsule, 0.04)
		check("turning the character turns the arrow", near(closed_arrow.rotation, -math.pi / 2) and near(open_arrow.rotation, -math.pi / 2))
		state.facing = 0
		state.quests[2].waypoint = { map = 40, x = 0.25, y = 0.5 }
		capsule.scripts.OnUpdate(capsule, 0.1)
		check("a waypoint on another map of this continent still aims", near(closed_arrow.rotation, math.pi / 2))
		addon.module.set("smart_island", "quest_plan", true)
		check("the arrow follows the suggestion", asked[#asked] == 23 and state.selected == 22)
		addon.smart_island.pin_quest(21)
		check("the arrow follows the pinned quest", asked[#asked] == 21 and state.selected == 22 and closed_arrow.shown)
		state.quests[1].waypoint = { map = 12, x = 0.5, y = 0.25 }
		capsule.scripts.OnUpdate(capsule, 0.1)
		check("another continent hides the arrow", closed_arrow.shown == false and open_arrow.shown == false)
		state.quests[1].waypoint = nil
		capsule.scripts.OnUpdate(capsule, 0.1)
		check("a quest without a waypoint hides the arrow", closed_arrow.shown == false)
		state.quests[1].waypoint = { map = 37, x = 0.5, y = 0.25 }
		state.facing = nil
		capsule.scripts.OnUpdate(capsule, 0.1)
		check("missing facing hides the arrow", closed_arrow.shown == false)
		state.facing = 0
		env.everlook_smart_island_key("down")
		check("the open quest title keeps the same arrow", open_arrow.shown and near(open_arrow.rotation, 0) and near(closed_arrow.rotation, 0))
		inspection.scripts.OnUpdate(inspection, 0.1)
		state.facing = secret
		inspection.scripts.OnUpdate(inspection, 0.1)
		check("a secret facing hides the arrow", closed_arrow.shown == false and open_arrow.shown == false)
		state.facing = 0
		state.time = state.time + 2
		env.C_QuestLog.GetNextWaypoint = function() end
		state.pins = { [37] = { { questID = 21, x = 0.5, y = 0.25 } } }
		state.parents = {}
		env.C_QuestLog.GetQuestsOnMap = function(map_id) return state.pins[map_id] end
		env.C_Map.GetMapInfo = function(map_id) return { parentMapID = state.parents[map_id] } end
		capsule.scripts.OnUpdate(capsule, 0.1)
		local icon
		for _, region in ipairs(capsule.regions) do
			if region.atlas == "questlog-questtypeicon-quest" then icon = region end
		end
		check("a map pin aims when the client has no waypoint", closed_arrow.shown and near(closed_arrow.rotation, 0) and icon.shown == false and closed_arrow.point[1] == "TOPLEFT")
		state.pins = { [37] = {}, [13] = { { questID = 21, x = 0.25, y = 0.5 } } }
		state.parents = { [37] = 13 }
		state.maps[13] = { continent = 0, origin_x = 0, origin_y = 0, width = 100, height = 100 }
		state.time = state.time + 2
		capsule.scripts.OnUpdate(capsule, 0.1)
		check("a pin on the parent map still aims", near(closed_arrow.rotation, math.pi / 2))
		env.C_Map.GetWorldPosFromMapPos = function() end
		env.C_Map.GetMapWorldSize = function() return 1000, 1000 end
		env.C_QuestLog.GetNextWaypoint = function() return 37, 0.5, 0.25 end
		capsule.scripts.OnUpdate(capsule, 0.1)
		check("the same map aims when world positions are missing", near(closed_arrow.rotation, 0) and closed_arrow.path == "Interface\\AddOns\\Everlook_Island\\assets\\island_arrow.tga")
	end

	do
		local addon, env, event, state, afters, _, frames = island_world()
		env.UIParent.GetWidth = function() return 320 end
		env.UIParent.GetHeight = function() return 480 end
		addon.module.set("smart_island", "enabled", true)
		local root_frame
		for _, frame in ipairs(frames) do if frame.name == "EverlookSmartIsland" then root_frame = frame end end
		check("island placement defaults to twelve below the top", root_frame.point[5] == -12)
		addon.module.set("smart_island", "size", 150)
		addon.module.set("smart_island", "position_x", 600)
		addon.module.set("smart_island", "position_top", 300)
		check("scaled capsule is clamped inside a narrow screen", root_frame.scale == 1.5 and root_frame.point[4] < 100 and root_frame.point[5] > -300)
		env.everlook_smart_island_key("down")
		check("expanded width accounts for the island scale", addon.smart_island.view().width <= 320 / 1.5)
		addon.smart_island.reset_position()
		check("reset changes placement without changing size", addon.module.get("smart_island", "position_x") == 0 and addon.module.get("smart_island", "position_top") == 12 and addon.module.get("smart_island", "size") == 150)
		state.time = state.time + 1
		env.everlook_smart_island_key("up")
		addon.module.set("smart_island", "hover_preview", false)
		root_frame.scripts.OnEnter(root_frame)
		check("hover preview can be disabled without losing click opening", addon.smart_island.view().mode == "closed")
		root_frame.scripts.OnClick(root_frame)
		check("click still pins with hover disabled", addon.smart_island.view().pinned)
		root_frame.scripts.OnClick(root_frame)
		addon.module.set("smart_island", "read_time", 7)
		env.Everlook.island.notify({ text = "Default read time" })
		check("read time controls the implicit notification duration", addon.smart_island.view().notices[1].duration == 7)
		env.Everlook.island.notify({ text = "Explicit duration", duration = 2 })
		check("producer duration overrides the read time", addon.smart_island.view().notices[2].duration == 2)
		local before = #addon.smart_island.view().toasts
		env.InCombatLockdown = function() return true end
		env.Everlook.island.notify({ text = "Routine combat notice" })
		check("routine combat notices remain in the inbox", #addon.smart_island.view().toasts == before and #addon.smart_island.view().queue == 0 and #addon.smart_island.view().notices == 3)
		env.Everlook.island.notify({ text = "Combat warning", severity = "warning" })
		check("combat warnings can still toast", #addon.smart_island.view().toasts == before + 1)
		env.InCombatLockdown = function() return false end
		event("PLAYER_REGEN_ENABLED")
		check("combat ends without replaying routine arrivals", #addon.smart_island.view().queue == 0)
		env.EverlookDB.qol.smart_island.size = 0 / 0
		env.EverlookDB.qol.smart_island.position_x = math.huge
		env.EverlookDB.qol.smart_island.position_top = -1000
		event("UI_SCALE_CHANGED")
		check("corrupt numeric preferences use finite bounded values", root_frame.scale == 1 and root_frame.point[4] == 0 and root_frame.point[5] == -8)
	end

	do
		local addon, env, event, state, afters = island_world()
		state.bags[0], state.bags[1], state.bags[5] = 8, 20, 100
		state.bag_families[1] = 32
		addon.module.set("smart_island", "enabled", true)
		check("general free slots exclude specialty and reagent capacity", addon.smart_island.view().bags == "8 free slots")
		state.bags[0] = 7
		event("BAG_UPDATE_DELAYED")
		check("ordinary bag changes stay quiet", #addon.smart_island.view().notices == 0)
		state.bags[0] = 5
		event("BAG_UPDATE_DELAYED")
		local view = addon.smart_island.view()
		local first = view.notices[1]
		check("low free slots produce one keyed warning", first and first.severity == "warning" and first.key == "free-slots")
		state.bags[0] = 0
		event("BAG_UPDATE_DELAYED")
		view = addon.smart_island.view()
		check("full bags strengthen the same warning identity", #view.notices == 1 and view.notices[1].id == first.id and view.notices[1].severity == "error")
		state.bags[0] = 7
		event("BAG_UPDATE_DELAYED")
		check("bag warning retains its recovery margin", #addon.smart_island.view().notices == 1)
		state.bags[0] = 8
		event("BAG_UPDATE_DELAYED")
		check("bag recovery resolves the condition without another notice", #addon.smart_island.view().notices == 0)
		state.money = 22345
		event("PLAYER_MONEY")
		check("money updates quietly by default", #addon.smart_island.view().notices == 0 and addon.smart_island.view().money == "2g 23s 45c")
	end
	do
		local addon, _, event, state, afters = island_world()
		addon.module.set("smart_island", "enabled", true)
		addon.module.set("smart_island", "source_money", true)
		state.money = 12445
		event("PLAYER_MONEY")
		local stale = afters[#afters] and afters[#afters].callback
		state.time = 100.2
		state.money = 12645
		event("PLAYER_MONEY")
		check("routine money waits for a quiet window", #addon.smart_island.view().notices == 0)
		if stale then stale() end
		check("an earlier batch deadline cannot publish a partial delta", #addon.smart_island.view().notices == 0)
		local current = afters[#afters] and afters[#afters].callback
		if current then current() end
		local entry = addon.smart_island.view().notices[1]
		check("routine money publishes one signed rich net amount", entry and entry.money == 300 and entry.text == "Money received")
		local before = #addon.smart_island.view().notices
		state.money = 12646
		event("PLAYER_MONEY")
		if afters[#afters] then afters[#afters].callback() end
		check("tiny routine money deltas stay quiet", #addon.smart_island.view().notices == before)
		state.money = 22646
		event("PLAYER_MONEY")
		local disabled = afters[#afters] and afters[#afters].callback
		addon.module.set("smart_island", "source_money", false)
		if disabled then disabled() end
		check("turning off money delivery cancels pending batches", #addon.smart_island.view().notices == before)
	end
	do
		local addon, _, event, state = island_world()
		addon.module.set("smart_island", "enabled", true)
		event("PLAYER_LEVEL_UP", 13)
		event("PLAYER_LEVEL_UP", 13)
		check("a readable level event outruns a delayed getter exactly once", addon.smart_island.view().level == 13 and #addon.smart_island.view().notices == 1)
		state.level = 13
		event("PLAYER_XP_UPDATE", "player")
		check("the level getter catches up without another notice", addon.smart_island.view().level == 13 and #addon.smart_island.view().notices == 1)
	end
	do
		local addon, env, event, state, afters, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		state.slots[1] = { 14, 50 }
		event("UPDATE_INVENTORY_DURABILITY")
		local handle = addon.smart_island.view().notices[1].id
		check("weakest-item damage crosses a threshold despite healthier gear", addon.smart_island.view().durability == "28%")
		state.slots[1] = { 4, 50 }
		event("UPDATE_INVENTORY_DURABILITY")
		check("severe damage updates one condition", #addon.smart_island.view().notices == 1 and addon.smart_island.view().notices[1].id == handle)
		state.slots[1] = { 0, 50 }
		event("UPDATE_INVENTORY_DURABILITY")
		check("a broken item strengthens the same condition", addon.smart_island.view().notices[1].severity == "error")
		state.slots[1] = { 18, 50 }
		event("UPDATE_INVENTORY_DURABILITY")
		check("durability recovery resolves the retained warning", #addon.smart_island.view().notices == 0)
		state.bags[0], state.bags[1] = 3, 1
		event("BAG_UPDATE_DELAYED")
		addon.module.set("smart_island", "source_bags", false)
		check("disabling a condition source removes its warning immediately", #addon.smart_island.view().notices == 0)
		finish_animations(frames)
		addon.module.set("smart_island", "source_money", true)
		state.money = 12545
		event("BAG_UPDATE_DELAYED")
		event("PLAYER_MONEY")
		local maximum = afters[#afters - 1].callback
		state.time = 101
		state.money = 12745
		event("PLAYER_MONEY")
		maximum()
		check("other readouts preserve the money baseline and maximum-window total", addon.smart_island.view().notices[1].money == 400)
		local secret = secret_stat()
		env.issecretvalue = function(value) return value == secret end
		env.C_Container.GetContainerNumFreeSlots = function(bag) return 20, bag == 0 and 0 or secret end
		addon.module.set("smart_island", "source_bags", true)
		event("BAG_UPDATE_DELAYED")
		check("secret bag classification leaves capacity unavailable without a warning", addon.smart_island.view().bags == nil and #addon.smart_island.view().notices == 1)
	end
	do
		local addon, env, event, state, afters = island_world()
		local requests, cost, needed = {}, 500, true
		env.CanMerchantRepair = function() return true end
		env.GetRepairAllCost = function() return cost, needed end
		env.RepairAllItems = function(guild) requests[#requests + 1] = guild end
		addon.module.set("smart_island", "enabled", true)
		addon.module.set("smart_island", "source_money", true)
		addon.module.set("auto_repair", "enabled", true)
		event("MERCHANT_SHOW")
		check("requesting repair does not announce success", #requests == 1 and #addon.smart_island.view().notices == 0)
		state.money = state.money - 500
		event("PLAYER_MONEY")
		cost, needed = 0, false
		event("UPDATE_INVENTORY_DURABILITY")
		local entry = addon.smart_island.view().notices[1]
		check("confirmed personal repair reports rich cost and fund source", entry and entry.text == "Equipment repaired" and entry.money == -500 and entry.detail == "Paid from personal funds")
		fire_after(afters, 0.75)
		check("a matching confirmed cost consumes only its pending money summary", #addon.smart_island.view().notices == 1)
		state.money = state.money - 300
		event("PLAYER_MONEY")
		cost, needed = 300, true
		env.CanGuildBankRepair = function() return true end
		env.GetGuildBankWithdrawMoney = function() return -1 end
		env.GetGuildBankMoney = function() return 1000 end
		addon.module.set("auto_repair", "guild_funds", true)
		event("MERCHANT_SHOW")
		cost, needed = 0, false
		event("UPDATE_INVENTORY_DURABILITY")
		local notices = addon.smart_island.view().notices
		entry = notices[#notices]
		check("confirmed guild repair identifies guild payment", requests[2] == true and entry.detail == "Paid from guild funds" and entry.money == -800 and entry.count == 2)
		fire_after(afters, 0.75)
		entry = addon.smart_island.view().notices
		check("a guild repair leaves an equal personal money batch", #entry == 2 and entry[1].detail == "Paid from guild funds" and entry[1].money == -800 and entry[2].text == "Money spent" and entry[2].money == -300)
		local count = #entry
		cost, needed = 100, true
		event("MERCHANT_SHOW")
		event("MERCHANT_CLOSED")
		cost, needed = 0, false
		event("UPDATE_INVENTORY_DURABILITY")
		check("closing the vendor cancels an unconfirmed repair notice", #addon.smart_island.view().notices == count)
	end
	do
		local addon, env, event, state, afters = island_world()
		local cost, needed, requests = 100, true, 0
		env.CanMerchantRepair = function() return true end
		env.GetRepairAllCost = function() return cost, needed end
		env.RepairAllItems = function() requests = requests + 1 end
		addon.module.set("smart_island", "enabled", true)
		addon.module.set("smart_island", "source_money", true)
		addon.module.set("smart_island", "money_min_silver", 0)
		addon.module.set("auto_repair", "enabled", true)
		event("MERCHANT_SHOW")
		state.money = state.money - 75 -- Includes a separate 25-copper gain.
		event("PLAYER_MONEY")
		event("UPDATE_INVENTORY_DURABILITY")
		check("an unchanged repair cost cannot confirm an attempted repair", #addon.smart_island.view().notices == 0)
		cost, needed = 0, false
		fire_after(afters, 0.1)
		fire_after(afters, 0.75)
		local notices = addon.smart_island.view().notices
		check("a delayed getter confirms after the observed durability event", #notices == 2 and notices[1].text == "Equipment repaired")
		check("mixed money batches preserve unrelated activity", notices[#notices].money == -75)
		cost, needed = 50, true
		event("MERCHANT_SHOW")
		fire_after(afters, 3)
		fire_after(afters, 3)
		fire_after(afters, 3)
		cost, needed = 0, false
		event("UPDATE_INVENTORY_DURABILITY")
		check("expired repair observation does not announce late success", #addon.smart_island.view().notices == 2)
		local secret = secret_stat()
		env.issecretvalue = function(value) return value == secret end
		cost, needed = secret, true
		local ok = pcall(event, "MERCHANT_SHOW")
		check("secret repair cost prevents spending and formatting", ok and requests == 2)
	end
	do
		local addon, env, event, state, afters, tickers = island_world()
		local items = { { itemID = 1, quality = 0, stackCount = 2 }, { itemID = 2, quality = 0, stackCount = 1 } }
		local reported, used = nil, 0
		env.NUM_BAG_SLOTS = 0
		env.C_Item = { GetItemInfo = function() return "Junk", nil, 0, 1, 0, "Miscellaneous", "Junk", 20, "", 1, 100, 15, 0, 0, 0, nil, false end }
		env.C_Container.GetContainerNumSlots = function() return 2 end
		env.C_Container.GetContainerItemInfo = function(_, slot) return items[slot] end
		env.C_Container.UseContainerItem = function(_, slot)
			used = used + 1
			state.money = state.money + items[slot].stackCount * 100
			items[slot] = nil
		end
		addon.say = function(text) reported = text end
		addon.module.set("smart_island", "enabled", true)
		addon.module.set("smart_island", "source_money", true)
		addon.module.set("sell_junk", "enabled", true)
		event("MERCHANT_SHOW")
		local selling = tickers[#tickers]
		selling.callback()
		event("PLAYER_MONEY")
		check("an attempted junk sale has no island result", #addon.smart_island.view().notices == 0)
		selling.callback()
		event("PLAYER_MONEY")
		selling.callback()
		local entry = addon.smart_island.view().notices[1]
		check("confirmed junk proceeds reach the island before totals reset", entry and entry.text == "Junk sold" and entry.money == 300 and entry.severity == "success" and used == 2)
		check("the original junk chat report remains", reported and reported:find("300 copper", 1, true))
		fire_after(afters, 0.75)
		fire_after(afters, 0.75)
		check("a confirmed matching junk batch has one result", #addon.smart_island.view().notices == 1)
		items[1] = { itemID = 1, quality = 0, stackCount = 2 }
		addon.module.set("smart_island", "source_sell", false)
		event("MERCHANT_SHOW")
		selling = tickers[#tickers]
		selling.callback()
		selling.callback()
		check("disabling the sale feed preserves selling and its chat report", used == 3 and #addon.smart_island.view().notices == 1 and reported:find("200 copper", 1, true))
		event("PLAYER_MONEY")
		fire_after(afters, 0.75)
		addon.module.set("smart_island", "source_sell", true)
		local original, errors = env.Everlook.island.notify, {}
		env.geterrorhandler = function() return function(message) errors[#errors + 1] = message end end
		env.Everlook.island.notify = function(payload)
			if payload.source == "everlook.sell_junk" then error("display failed") end
			return original(payload)
		end
		items[1] = { itemID = 1, quality = 0, stackCount = 1 }
		event("MERCHANT_SHOW")
		selling = tickers[#tickers]
		selling.callback()
		event("PLAYER_MONEY")
		selling.callback()
		fire_after(afters, 0.75)
		local money_notice = addon.smart_island.view().notices[2]
		check("sale display errors preserve chat and the routine-money fallback", #errors == 1 and reported:find("100 copper", 1, true) and money_notice and money_notice.text == "Money received" and money_notice.money == 300 and money_notice.count == 2)
	end
	do
		local addon, env, event, state, afters = island_world()
		local cost, needed, requests, errors = 100, true, 0, {}
		env.CanMerchantRepair = function() return true end
		env.GetRepairAllCost = function() return cost, needed end
		env.RepairAllItems = function() requests = requests + 1 end
		addon.module.set("smart_island", "enabled", true)
		addon.module.set("smart_island", "source_money", true)
		addon.module.set("auto_repair", "enabled", true)
		local original = env.Everlook.island.notify
		env.geterrorhandler = function() return function(message) errors[#errors + 1] = message end end
		env.Everlook.island.notify = function(payload)
			if payload.source == "everlook.auto_repair" then error("display failed") end
			return original(payload)
		end
		event("MERCHANT_SHOW")
		state.money = state.money - 100
		event("PLAYER_MONEY")
		cost, needed = 0, false
		event("UPDATE_INVENTORY_DURABILITY")
		fire_after(afters, 0.75)
		local fallback = addon.smart_island.view().notices[1]
		check("repair display failure leaves the completed action and money fallback", requests == 1 and #errors == 1 and fallback and fallback.money == -100)
	end
	do
		local addon, env, _, state, _, _, frames, hooks = island_world()
		local flying = false
		env.UnitOnTaxi = function() return flying end
		env.TakeTaxiNode = function() end
		env.NumTaxiNodes = function() return 2 end
		env.TaxiNodeGetType = function(index) return index == 1 and "CURRENT" or "REACHABLE" end
		env.TaxiNodeName = function(index) return index == 1 and "Crossroads" or "Ratchet" end
		addon.module.set("smart_island", "enabled", true)
		addon.module.set("smart_island", "source_flight", true)
		addon.module.set("flight_time", "enabled", true)
		local poller, timer
		for _, object in ipairs(frames) do
			if object.name == "EverlookFlightPoller" then poller = object end
			if object.name == "EverlookFlightTime" then timer = object end
		end
		check("flight time does not poll while you are on the ground", poller and poller.scripts.OnUpdate == nil)
		hooks.TakeTaxiNode(2)
		check("taking a flight starts one poller", poller.scripts.OnUpdate ~= nil)
		poller.scripts.OnUpdate(poller, 0.25)
		check("a flight request alone has no ongoing status", addon.smart_island.view().status == nil)
		flying, state.time = true, 101
		poller.scripts.OnUpdate(poller, 0.25)
		local view = addon.smart_island.view()
		local handle = view.status and view.status.id
		check("an unknown flight shows elapsed time without invented progress", handle and view.status.text == "Flying to Ratchet" and view.status.progress == nil and #view.toasts == 0)
		state.time = 102
		poller.scripts.OnUpdate(poller, 0.25)
		check("flight updates retain one status identity", addon.smart_island.view().status and addon.smart_island.view().status.id == handle and #addon.smart_island.view().notices == 1)
		check("an unknown flight capsule shows elapsed time", addon.smart_island.view().status.capsule and addon.smart_island.view().status.capsule.text == "0:01" and addon.smart_island.view().status.capsule.trailing == "Ratchet")
		flying, state.time = false, 161
		poller.scripts.OnUpdate(poller, 0.25)
		view = addon.smart_island.view()
		check("arrival completes the existing status exactly once", view.status == nil and #view.toasts == 1 and view.toasts[1].id == handle and view.toasts[1].text == "Arrived at Ratchet")
		hooks.TakeTaxiNode(2)
		flying, state.time = true, 200
		poller.scripts.OnUpdate(poller, 0.25)
		state.time = 230
		poller.scripts.OnUpdate(poller, 0.25)
		check("a learned flight estimate produces measured progress", addon.smart_island.view().status and addon.smart_island.view().status.progress == 0.5)
		check("a learned flight capsule shows remaining time", addon.smart_island.view().status.capsule and addon.smart_island.view().status.capsule.text == "0:30")
		state.time = 230.25
		local updated_at = addon.smart_island.view().status.updated_at
		poller.scripts.OnUpdate(poller, 0.25)
		check("flight status updates are limited to once per second", addon.smart_island.view().status.updated_at == updated_at)
		local secret = secret_stat()
		env.issecretvalue = function(value) return value == secret end
		flying = secret
		poller.scripts.OnUpdate(poller, 0.25)
		check("unreadable taxi state does not invent arrival", addon.smart_island.view().status ~= nil and #addon.smart_island.view().toasts == 1)
		flying, env.issecretvalue = true, nil
		addon.module.set("flight_time", "only_island", true)
		poller.scripts.OnUpdate(poller, 0.25)
		check("Island-only display is an explicit flight preference", not timer.shown)
		local original, errors = env.Everlook.island.notify, {}
		env.geterrorhandler = function() return function(message) errors[#errors + 1] = message end end
		env.Everlook.island.notify = function(payload)
			if payload.source == "everlook.flight_time" then error("display failed") end
			return original(payload)
		end
		state.time = 231.5
		poller.scripts.OnUpdate(poller, 0.25)
		check("a failed flight feed cleans up its status and keeps the ordinary timer", #errors == 1 and addon.smart_island.view().status == nil and timer.shown)
		env.Everlook.island.notify = original
		state.time = 233
		poller.scripts.OnUpdate(poller, 0.25)
		addon.module.set("smart_island", "source_flight", false)
		poller.scripts.OnUpdate(poller, 0.25)
		check("disabling the feed removes status and restores the ordinary timer", addon.smart_island.view().status == nil and timer.shown)
		addon.module.set("flight_time", "enabled", false)
		check("disabling flight time clears its own display and poller", not timer.shown and poller.scripts.OnUpdate == nil)
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		env.UIParent.GetWidth = function() return 400 end
		addon.module.set("smart_island", "enabled", true)
		check("the resting island is a readable capsule", addon.smart_island.view().width == 64 and addon.smart_island.view().height == 36)
		env.everlook_smart_island_key("down")
		local before = addon.smart_island.view()
		check("the expanded summary fits the available screen", before.width == 368)
		env.Everlook.island.notify({ text = string.rep("A wrapped history message ", 12) })
		local after = addon.smart_island.view()
		check("long history rows grow below a stable summary", before.summary_height ~= nil and before.summary_height == after.summary_height and after.height > before.height + 16)
		local bar = island_fill(frames)
		check("experience uses a thin header rail", bar.height == 3 and bar.status_texture ~= nil and not bar.all_points)
	end

	do
		local addon, env = island_world()
		addon.module.set("smart_island", "enabled", true)
		local payload = { text = "Equipment repaired", detail = "Personal funds", money = -21500,
			severity = "success", icon = "repair", progress = 0.5, presentation = "inbox" }
		local handle = env.Everlook.island.notify(payload)
		payload.detail, payload.money = "Changed by caller", 0
		local view = addon.smart_island.view()
		local entry = view.notices[1]
		check("rich notifications copy accepted fields without showing an inbox-only card", handle and entry.detail == "Personal funds"
			and entry.money == -21500 and entry.severity == "success" and entry.icon == "repair" and entry.progress == 0.5
			and entry.presentation == "inbox" and #view.toasts == 0)
		local secret = secret_stat()
		env.issecretvalue = function(value) return value == secret end
		local cases = {
			{ "severity", "urgent" }, { "severity", secret }, { "severity", false },
			{ "detail", string.rep("x", 513) }, { "detail", secret }, { "detail", {} },
			{ "icon", {} }, { "icon", secret },
			{ "money", 1.5 }, { "money", math.huge }, { "money", 0 / 0 }, { "money", secret }, { "money", 9007199254740992 },
			{ "progress", -0.1 }, { "progress", 1.1 }, { "progress", math.huge }, { "progress", secret },
			{ "presentation", "modal" }, { "presentation", secret }, { "presentation", false },
		}
		for index, case in ipairs(cases) do
			local input = { text = "Safe" }
			input[case[1]] = case[2]
			local ok, accepted, reason = pcall(env.Everlook.island.notify, input)
			check("invalid rich field " .. index .. " is rejected safely", ok and accepted == nil and reason == "invalid_" .. case[1])
		end
		local fallback = env.Everlook.island.notify({ text = "Unknown icon", icon = "someone-elses-icon" })
		entry = addon.smart_island.view().notices[2]
		check("unknown icon names fall back with legacy defaults", fallback and entry.icon == "generic" and entry.severity == "info" and entry.presentation == "toast")
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		local api = env.Everlook.island
		local first = api.notify({ text = "Routine one" })
		api.notify({ text = "Routine two" })
		api.notify({ text = "Routine three" })
		for index = 1, 5 do api.notify({ text = "Warning " .. index, severity = "warning" }) end
		api.notify({ text = "Late routine" })
		local view = addon.smart_island.view()
		check("a routine burst cannot evict queued warnings", #view.queue == 5 and view.queue[1].text == "Warning 1" and view.queue[5].text == "Warning 5")
		api.notify({ source = "Important", key = "error", text = "Equipment broken", severity = "error" })
		view = addon.smart_island.view()
		check("an error releases the oldest routine card through its exit", view.toasts[1].id == first and view.toasts[1].phase == "exiting" and #view.toasts == 3)
		api.notify({ source = "Important", key = "error", text = "Equipment still broken", severity = "error" })
		check("a keyed error update cannot repeatedly preempt active cards", addon.smart_island.view().toasts[2].phase ~= "exiting")
		finish_animations(frames)
		view = addon.smart_island.view()
		check("errors promote ahead of warnings without erasing warning history", view.toasts[3].text == "Equipment still broken" and #view.queue == 4)
		api.dismiss(view.toasts[2].id)
		finish_animations(frames)
		check("warning promotion preserves FIFO within its severity", last_toast_text(addon) == "Warning 2")
	end
	do
		local addon, env, _, _, afters = island_world()
		addon.module.set("smart_island", "enabled", true)
		local api = env.Everlook.island
		local missing, reason = api.notify({ text = "Activity", presentation = "status" })
		check("status requires an explicit source and key", missing == nil and reason == "invalid_status_source")
		missing, reason = api.notify({ source = "Flight", text = "Activity", presentation = "status" })
		check("status requires a stable key", missing == nil and reason == "invalid_status_key")
		local first = api.notify({ source = "Flight", key = "trip", text = "Flying to Ratchet", presentation = "status", progress = 0.1 })
		local old_deadline = afters[#afters].callback
		local second = api.notify({ source = "Quest", key = "active", text = "Smart Drinks", presentation = "status" })
		local view = addon.smart_island.view()
		check("the newest status owns one row while earlier activity stays in history", view.status and view.status.id == second and #view.notices == 2 and #view.toasts == 0)
		local updated = api.notify({ source = "Flight", key = "trip", text = "Flying to Ratchet", presentation = "status", progress = 0.8 })
		old_deadline()
		view = addon.smart_island.view()
		check("progress refreshes liveness without taking a newer status's row", updated == first and view.status.id == second and #view.notices == 2 and view.unread_count == 2)
		api.dismiss(second)
		check("dismissing the owner restores the earlier live activity", addon.smart_island.view().status.id == first)
		local current_deadline = afters[#afters].callback
		api.notify({ source = "Flight", key = "trip", text = "Arrived at Ratchet", severity = "success", presentation = "toast" })
		current_deadline()
		view = addon.smart_island.view()
		check("status completion keeps its handle and becomes one toast", view.status == nil and #view.toasts == 1 and view.toasts[1].id == first and #view.notices == 1)
		api.notify({ source = "Quest", key = "forgotten", text = "No more updates", presentation = "status" })
		afters[#afters].callback()
		check("abandoned activity falls back to retained history", addon.smart_island.view().status == nil and #addon.smart_island.view().notices == 2)
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		env.GetMoneyString = function(amount) return "<coin:" .. amount .. ">" end
		addon.module.set("smart_island", "enabled", true)
		env.Everlook.island.notify({ source = "Repair", key = "result", text = "Equipment repaired",
			detail = "Personal funds", severity = "success", money = -21500, progress = 1 })
		local title, detail, label, progress
		for _, object in ipairs(frames) do
			if object.max == 1 and object.value == 1 then progress = object end
			for _, region in ipairs(object.regions) do
				if region.text == "Equipment repaired" then title = region end
				if region.text and region.text:find("Personal funds", 1, true) and region.text:find("<coin:20000>", 1, true) then detail = region end
				if region.text and region.text:find("Success", 1, true) then label = region end
			end
		end
		check("rich cards render a primary title, supporting detail, colored native coins and a severity label", title and detail and detail.text:find("|cffffd166", 1, true) and label)
		check("readable notification progress uses a native rail", progress and progress.height == 3)
		env.Everlook.island.notify({ source = "Quest", key = "active", kind = "quest", text = "Smart Drinks", presentation = "status" })
		check("an active status adds a compact icon without scrolling capsule text", addon.smart_island.view().width == 88)
		env.everlook_smart_island_key("down")
		local view = addon.smart_island.view()
		check("expanded activity occupies its own row above the inbox", view.status_height and view.status_height >= 44)
	end
	do
		local addon, env, _, _, afters, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		local api = env.Everlook.island
		local function finish_morph()
			local island, resting
			for _, object in ipairs(frames) do
				if object.name == "EverlookSmartIsland" then island = object end
				if object.name == "EverlookIslandResting" then resting = object end
			end
			if island and island.scripts.OnUpdate and resting and resting.animation_groups and resting.animation_groups[1] then
				resting.animation_groups[1].animations[1].progress = 1
				island.scripts.OnUpdate()
			end
		end
		local function shown_text(needle)
			for _, object in ipairs(frames) do
				for _, region in ipairs(object.regions or {}) do
					if region.text and region.text:find(needle, 1, true) then return region.text end
				end
			end
		end
		local payload = { source = "A", key = "trip", text = "Flying to Ratchet", presentation = "status",
			capsule = { icon = "flight", text = "1:10", trailing = "Ratchet" } }
		local handle = api.notify(payload)
		payload.capsule.text = "9:99"
		local view = addon.smart_island.view()
		check("a copied capsule survives mutation of the caller's table", handle and view.status.capsule.text == "1:10" and view.status.capsule.trailing == "Ratchet")
		check("a capsule morph starts from the resting width", view.shell.playing and view.shell.from == 64 and view.shell.to == view.width and view.width > 64)
		finish_morph()
		local settled = addon.smart_island.view().shell.width
		api.notify({ source = "A", key = "trip", text = "Flying to Ratchet", presentation = "status", capsule = { icon = "clock", text = "1:10", trailing = "Ratchet" } })
		view = addon.smart_island.view()
		check("an icon change starts from the current width", view.shell.playing and view.shell.from == settled)
		finish_morph()
		env.everlook_smart_island_key("down")
		env.everlook_smart_island_key("up")
		for index = #afters, 1, -1 do
			if afters[index].delay == 0.75 then afters[index].callback() end
		end
		local pill = addon.smart_island.view().shell.width
		api.notify({ source = "A", key = "trip", text = "Flying to Ratchet", presentation = "status", capsule = { icon = "clock", text = "1:09", trailing = "Ratchet" } })
		view = addon.smart_island.view()
		check("a clock update keeps one read notice and the same pill width", view.unread_count == 0 and #view.notices == 1 and view.shell.width == pill and view.status.capsule.text == "1:09")
		local rejected, reason = api.notify({ source = "A", key = "toast", text = "Hello", capsule = { text = "1:10" } })
		check("a capsule on a toast is rejected", rejected == nil and reason == "invalid_capsule")
		local secret = secret_stat()
		env.issecretvalue = function(value) return value == secret end
		rejected, reason = api.notify({ source = "A", key = "secret", text = "Flying", presentation = "status", capsule = { text = secret } })
		check("a secret capsule is rejected", rejected == nil and reason == "invalid_capsule" and addon.smart_island.view().status.capsule.text == "1:09")
		env.issecretvalue = nil
		rejected, reason = api.notify({ source = "A", key = "mark", text = "Flying", presentation = "status", capsule = { text = "1:10|T" } })
		check("markup in capsule text is rejected", rejected == nil and reason == "invalid_capsule")
		local runs = {}
		for index = 1, 7 do runs[index] = { text = "Run" } end
		rejected, reason = api.notify({ source = "A", key = "runs", text = "Too many", runs = runs })
		check("a seventh run is rejected", rejected == nil and reason == "invalid_runs")
		rejected, reason = api.notify({ source = "A", key = "atlas", text = "Bad atlas", runs = { { atlas = "Interface/Icons/Foo" } } })
		check("a path-like atlas is rejected", rejected == nil and reason == "invalid_atlas")
		env.GetMoneyString = function(amount) return "<coin:" .. amount .. ">" end
		handle = api.notify({ source = "A", key = "rich", text = "Paid", runs = {
			{ text = "Paid", tone = "primary" }, { money = -21500 }, { atlas = "Taxi_Frame_Gray" },
		} })
		local compiled = shown_text("|A:Taxi_Frame_Gray:16:16|a")
		check("compiled runs contain the coin color and the atlas escape", handle and compiled and compiled:find("|cffffd166", 1, true) and compiled:find("|A:Taxi_Frame_Gray:16:16|a", 1, true))
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		addon.module.set("smart_island", "reduced_motion", true)
		env.Everlook.island.notify({ source = "A", key = "trip", text = "Flying to Ratchet", presentation = "status",
			capsule = { icon = "flight", text = "1:10", trailing = "Ratchet" } })
		local view = addon.smart_island.view()
		check("reduced motion settles on the target width in one paint", view.shell.width == view.width and view.width > 64 and view.shell.playing)
	end
	do
		local addon, env, _, _, afters = island_world()
		addon.module.set("smart_island", "enabled", true)
		local api = env.Everlook.island
		local handle = api.notify({ source = "Flight", key = "trip", text = "Flying", detail = "1 second", presentation = "status", progress = 0.1 })
		env.everlook_smart_island_key("down")
		afters[#afters].callback()
		api.notify({ source = "Flight", key = "trip", text = "Flying", detail = "2 seconds", presentation = "status", progress = 0.2 })
		check("reading activity stays acknowledged through numeric updates", addon.smart_island.view().unread_count == 0 and #addon.smart_island.view().notices == 1)
		local deadline = afters[#afters].callback
		addon.module.set("smart_island", "enabled", false)
		addon.module.set("smart_island", "enabled", true)
		local next_handle = api.notify({ source = "Flight", key = "trip", text = "New flight", presentation = "status" })
		deadline()
		check("a disabled status deadline cannot affect a new session", next_handle ~= handle and addon.smart_island.view().status.id == next_handle)
		api.notify({ source = "Flight", key = "trip", text = "Keep in history", presentation = "inbox" })
		check("moving status to inbox removes live activity", addon.smart_island.view().status == nil and #addon.smart_island.view().toasts == 0)
	end
	do
		local addon, env, _, _, afters, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		env.Everlook.island.notify({ text = "Visible before preview" })
		finish_animations(frames)
		local pill
		for _, object in ipairs(frames) do if object.name == "EverlookSmartIsland" then pill = object end end
		pill.scripts.OnEnter(pill)
		local view = addon.smart_island.view()
		check("pointer opening makes the inbox available with a short reveal", view.mode == "open" and view.preview and view.preview.phase == "opening" and view.preview.duration == 0.15)
		check("visible cards hand off through a fade without exiting their identity", view.toasts[1].phase == "handoff" and view.toasts[1].shown)
		finish_animations(frames)
		check("a completed handoff hides cards while retaining their history", not addon.smart_island.view().toasts[1].shown and #addon.smart_island.view().notices == 1)
		pill.scripts.OnLeave(pill)
		fire_after(afters, 0.1)
		view = addon.smart_island.view()
		check("pointer close fades a visual layer while restoring capsule input bounds", view.mode == "closed" and view.width == 64 and view.preview.phase == "closing" and view.preview.duration == 0.125)
		pill.scripts.OnEnter(pill)
		check("pointer reopening interrupts the close without waiting", addon.smart_island.view().mode == "open" and addon.smart_island.view().preview.phase == "opening")
		env.everlook_smart_island_key("down")
		check("keyboard inspection immediately settles a pointer transition", addon.smart_island.view().preview.phase == "settled" and addon.smart_island.view().preview.alpha == 1)
	end
	do
		local addon, env, event, state, afters, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		local pill
		for _, object in ipairs(frames) do if object.name == "EverlookSmartIsland" then pill = object end end
		pill.scripts.OnEnter(pill)
		local original_targets = {}
		for _, object in ipairs(frames) do
			for _, group in ipairs(object.animation_groups or {}) do
				if group.playing then
					for _, animation in ipairs(group.animations) do
						animation.progress = 0.5
						if animation.kind == "Translation" then original_targets[#original_targets + 1] = animation.target end
					end
				end
			end
		end
		check("preview motion samples native progress", addon.smart_island.view().preview.alpha == 0.5 and addon.smart_island.view().preview.y == -3)
		local controller_motion = false
		for _, target in ipairs(original_targets) do if target and target.mouse ~= false then controller_motion = true end end
		check("preview translations target visuals rather than mouse controls", #original_targets > 0 and not controller_motion)
		addon.module.set("smart_island", "reduced_motion", true)
		check("reduced motion removes translation during an interrupted reveal", addon.smart_island.view().preview.y == 0 and addon.smart_island.view().preview.alpha == 0.5)
		finish_animations(frames)
		pill.scripts.OnLeave(pill)
		fire_after(afters, 0.1)
		local old_finish
		for _, object in ipairs(frames) do
			for _, group in ipairs(object.animation_groups or {}) do
				if group.playing then old_finish = group.scripts.OnFinished end
			end
		end
		addon.module.set("smart_island", "enabled", false)
		addon.module.set("smart_island", "enabled", true)
		if old_finish then old_finish() end
		check("an old preview completion cannot reopen a new session", addon.smart_island.view().mode == "closed" and addon.smart_island.view().preview.alpha == 0)
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		local pill, resting, expanded, face
		local function find_island()
			pill, resting, expanded, face = nil, nil, nil, nil
			for _, object in ipairs(frames) do
				if object.name == "EverlookSmartIsland" then pill = object end
				if object.name == "EverlookIslandResting" then resting = object end
				if object.name == "EverlookIslandExpanded" then expanded = object end
				if object.name == "EverlookIslandFace" then face = object end
			end
		end
		local function preview_fade(object)
			for _, group in ipairs(object.animation_groups or {}) do
				for _, animation in ipairs(group.animations) do
					if animation.kind == "Alpha" then return animation end
				end
			end
		end
		find_island()
		pill.scripts.OnEnter(pill)
		local view = addon.smart_island.view()
		check("pointer open starts from the resting pill", view.shell.width == 64 and view.shell.height == 36 and view.width > view.shell.width)
		check("the chrome stays opaque while the open page is clipped to it", resting.shown and resting.alpha == 1 and expanded.clips and expanded.width == view.shell.width and face.alpha == 1)
		local fade = preview_fade(expanded)
		fade.progress = 0.5
		pill.scripts.OnUpdate()
		view = addon.smart_island.view()
		check("halfway the chrome is between the pill and the island", view.shell.width > 64 and view.shell.width < view.width and expanded.width == view.shell.width)
		addon.module.set("smart_island", "reduced_motion", true)
		view = addon.smart_island.view()
		check("reduced motion snaps the open chrome while the fade continues", view.shell.width == view.width and view.preview.alpha == 0.5 and view.preview.y == 0)
		env.everlook_smart_island_key("down")
		view = addon.smart_island.view()
		check("a keyboard open leaves the chrome at the island size", view.preview.phase == "settled" and view.preview.alpha == 1 and view.shell.width == view.width)
	end
	do
		local addon, env, _, _, afters, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		env.Everlook.island.notify({ text = "Keep this card" })
		finish_animations(frames)
		local pill
		for _, object in ipairs(frames) do if object.name == "EverlookSmartIsland" then pill = object end end
		pill.scripts.OnEnter(pill)
		pill.scripts.OnLeave(pill)
		fire_after(afters, 0.1)
		finish_animations(frames)
		local view = addon.smart_island.view()
		check("closing during a handoff restores the live card instead of hiding it", view.mode == "closed" and #view.toasts == 1 and view.toasts[1].shown and view.toasts[1].alpha == 1)
		local api = env.Everlook.island
		api.notify({ source = "Trip", key = "one", text = "Flying", presentation = "status" })
		api.notify({ source = "Trip", key = "one", text = "Arrived", presentation = "toast", severity = "success" })
		local completion_fade
		for _, object in ipairs(frames) do
			for _, group in ipairs(object.animation_groups or {}) do
				if group.playing then
					for _, animation in ipairs(group.animations) do
						if animation.kind == "Alpha" and animation.to == 1 and animation.duration == 0.15 then completion_fade = animation end
					end
				end
			end
		end
		check("status completion reveals success once with a short fade", completion_fade ~= nil)
	end
	do
		local addon, env, _, state, afters, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		local handle = env.Everlook.island.notify({ text = "Keep this notice", duration = 4 })
		state.time = 100.5
		env.everlook_smart_island_key("down")
		state.time = 100.6
		env.everlook_smart_island_key("up")
		env.everlook_smart_island_key("down")
		env.everlook_smart_island_key("up")
		local view = addon.smart_island.view()
		check("a short peek retains an unread notice", #view.notices == 1 and view.notices[1].id == handle and view.unread_count == 1)
		env.everlook_smart_island_key("down")
		state.time = 110
		fire_after(afters, 4)
		finish_animations(frames)
		check("inspection pauses visible toast expiry", #addon.smart_island.view().toasts == 1)
		afters[#afters].callback()
		check("visible rows become read after the dwell", addon.smart_island.view().unread_count == 0)
		env.everlook_smart_island_key("up")
		check("closing inspection retains its history", #addon.smart_island.view().notices == 1)
	end
	do
		local addon, env, _, state, afters, _, frames = island_world()
		env.UIParent.GetWidth = function() return 320 end
		env.UIParent.GetHeight = function() return 400 end
		addon.module.set("smart_island", "enabled", true)
		for index = 1, 10 do env.Everlook.island.notify({ text = "History row " .. index }) end
		env.everlook_smart_island_key("down")
		local controls = {}
		for _, button in ipairs(frames) do if button.name then controls[button.name] = button end end
		local island_scroll_to = addon.smart_island.scroll_to
		local view = addon.smart_island.view()
		check("the inbox exposes overflow inside a bounded viewport", view.scroll_height <= 240 and view.content_height > view.scroll_height and view.height <= 400)
		local function shown_fades()
			local fades = {}
			for _, object in ipairs(frames) do
				for _, region in ipairs(object.regions or {}) do
					if region.gradient and region.shown ~= false then fades[#fades + 1] = region end
				end
			end
			return fades
		end
		check("each fade has a white base for the gradient to tint", #shown_fades() == 1 and shown_fades()[1].color ~= nil and shown_fades()[1].color[4] == 1)
		check("a list with more below fades out at its bottom edge", view.more_below and not view.more_above and #shown_fades() == 1
			and shown_fades()[1].gradient.low.a > 0.9 and shown_fades()[1].gradient.high.a == 0)
		island_scroll_to(view.scroll_height)
		check("a list scrolled into the middle fades at both edges", addon.smart_island.view().more_below and addon.smart_island.view().more_above and #shown_fades() == 2)
		island_scroll_to(0)
		view = addon.smart_island.view()
		local function button_text()
			for _, region in ipairs(controls.EverlookIslandNewNotices.regions or {}) do
				if type(region.text) == "string" then return region.text end
			end
			for _, object in ipairs(frames) do
				for _, region in ipairs(object.regions or {}) do
					if type(region.text) == "string" and region.text:find(" new notice", 1, true) then return region.text end
				end
			end
		end
		check("the footer counts the unread rows below the visible ones", view.unread_below > 0 and view.unread_below < 10
			and button_text() == view.unread_below .. " new notices" and controls.EverlookIslandNewNotices.shown ~= false)
		local first_unread_below = view.unread_below
		controls.EverlookIslandNewNotices.scripts.OnClick()
		view = addon.smart_island.view()
		check("the button brings the first of them to the top, not just the bottom", view.scroll_offset > 0 and view.scroll_offset < view.content_height - view.scroll_height + 1
			and view.unread_below < first_unread_below)
		check("new notices can be reached without growing the panel", view.scroll_offset > 0)
		for _ = 1, 10 do
			if addon.smart_island.view().unread_below == 0 then break end
			controls.EverlookIslandNewNotices.scripts.OnClick()
		end
		island_scroll_to(addon.smart_island.view().content_height)
		check("a list scrolled to its end fades only at its top", addon.smart_island.view().more_above and not addon.smart_island.view().more_below and #shown_fades() == 1
			and shown_fades()[1].gradient.high.a > 0.9 and shown_fades()[1].gradient.low.a == 0)
		check("with nothing unread below, the button goes away", controls.EverlookIslandNewNotices.shown == false)
		-- Room for one more, so the list grows and the new row starts below the old end.
		addon.module.set("smart_island", "inbox_size", 30)
		local before_arrival = addon.smart_island.view().content_height
		env.Everlook.island.notify({ text = "Arrives while you are at the end" })
		view = addon.smart_island.view()
		check("a notice that arrives under your eyes is not counted as below them", view.content_height > before_arrival and view.unread_below == 0 and controls.EverlookIslandNewNotices.shown == false
			and view.scroll_offset == view.content_height - view.scroll_height)
		addon.module.set("smart_island", "inbox_size", 10)
		controls.EverlookIslandClearHistory.scripts.OnClick()
		check("clear history acknowledges the inbox with Undo", #addon.smart_island.view().notices == 0 and addon.smart_island.view().can_undo)
		env.Everlook.island.notify({ source = "New arrival", text = "Arrived after clear" })
		controls.EverlookIslandUndo.scripts.OnClick()
		view = addon.smart_island.view()
		check("Undo merges new arrivals without replaying toasts", #view.notices == 10 and view.notices[10].text == "Arrived after clear" and #view.toasts == 0 and not view.can_undo)
		controls.EverlookIslandClearHistory.scripts.OnClick()
		fire_after(afters, 5)
		-- The first clear's timeout is stale; the second clear owns the window.
		fire_after(afters, 5)
		check("Undo expires without restoring history", not addon.smart_island.view().can_undo and #addon.smart_island.view().notices == 0)
		state.time = 101
		env.everlook_smart_island_key("up")
	end
	do
		local addon, env, _, state, afters = island_world()
		addon.module.set("smart_island", "enabled", true)
		env.Everlook.island.notify({ text = "Read without a deadline", duration = 4 })
		state.time = 100.5
		env.everlook_smart_island_key("down")
		state.time = 200
		fire_after(afters, 4)
		env.everlook_smart_island_key("up")
		check("resuming preserves the remaining visible lifetime", afters[#afters].delay == 3.5 and #addon.smart_island.view().toasts == 1)
		fire_after(afters, 3.5)
		check("the resumed timer expires its own toast", addon.smart_island.view().toasts[1].phase == "exiting")
	end
	do
		local addon, env, _, _, afters = island_world()
		addon.module.set("smart_island", "enabled", true)
		env.Everlook.island.notify({ source = "Work", key = "one", text = "Before clear" })
		env.everlook_smart_island_key("down")
		local stale_read = afters[#afters].callback
		addon.smart_island.clear_history()
		addon.smart_island.undo_clear()
		stale_read()
		check("Undo requires a fresh reading dwell", addon.smart_island.view().unread_count == 1)
		afters[#afters].callback()
		check("a restored row becomes read after its new dwell", addon.smart_island.view().unread_count == 0)
		env.Everlook.island.notify({ source = "Work", key = "one", text = "Changed after reading" })
		check("changed content rearms unread without duplicating history", addon.smart_island.view().unread_count == 1 and #addon.smart_island.view().notices == 1)
	end
	do
		local island, island_env = load_qol()
		local found
		for _, module in ipairs(island.module.modules) do
			if module.id == "smart_island" then found = module end
		end
		check("the smart island is on its own settings page", found and found.page == "smart_island" and found.keybinding == "EVERLOOK_SMART_ISLAND")
		local names, seen, missing = {}, {}, false
		for _, section in ipairs(found and island.module.sections(found) or {}) do
			names[#names + 1] = section.name
			for _, key in ipairs(section.keys) do
				if seen[key] or not found.options[key] then missing = true end
				seen[key] = true
			end
		end
		for key in pairs(found and found.options or {}) do
			if key ~= "enabled" and not seen[key] then missing = true end
		end
		check("island sections name every option once",
			found and not missing and table.concat(names, ",") == "Presets,Placement,Opening,Closed pill,Quest display,Notices,Activity")
		check("the smart island starts disabled", not island.module.enabled("smart_island"))
		check("the island key is not the radial menu key",
			found.keybinding ~= "CLICK EverlookRadialButton:LeftButton" and island_env.BINDING_NAME_EVERLOOK_SMART_ISLAND == "Open smart island")
		check("money formats gold, silver and copper",
			island.island_vitals.money(1234567) == "123g 45s 67c"
			and island.island_vitals.money(0) == "0c"
			and island.island_vitals.delta(10000) == "+1g"
			and island.island_vitals.delta(-45) == "-45c"
			and island.island_vitals.rich(10000) == "1g")
		check("durability and bags format as a glance",
			island.island_vitals.percent(50, 70) == "71%"
			and island.island_vitals.bags(1) == "1 free slot"
			and island.island_vitals.bags(8) == "8 free slots"
			and island.smart_island.format_clock(14, 5) == "14:05"
			and island.smart_island.format_level(12) == "12")
	end
	do
		local addon, env, _, state, afters, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		check("the closed chip draws no bar", island_fill(frames).shown ~= true)
		env.everlook_smart_island_key("down")
		local heading, metric, clear, undo, experience, status
		for _, object in ipairs(frames) do
			if object.name == "EverlookIslandClearHistory" then clear = object end
			if object.name == "EverlookIslandUndo" then undo = object end
			for _, region in ipairs(object.regions) do
				if region.text == "Level 12" then heading = region end
				if region.text == "STATUS" then status = region end
				if region.text == "14:05    |cffad76ef45%|r" then experience = region end
				if region.text == "Money" then metric = region end
			end
		end
		check("the open bar shows the phrased experience", experience ~= nil)
		check("the first section clears the level text", -status.point[5] >= -heading.point[5] + heading:GetStringHeight() + 6)
		check("expanded metrics begin below the Status heading", -metric.parent.parent.point[5] >= -status.point[5] + 6)
		check("empty history has no disabled Clear button", clear.shown == false)
		check("an empty island holds its panes to the height of its empty message", addon.smart_island.view().scroll_height >= 48 and addon.smart_island.view().scroll_height <= 80)
		local empty_height = addon.smart_island.view().height
		env.Everlook.island.notify({ text = "A notice to clear" })
		check("history controls return when there is a notice", clear.shown ~= false and #addon.smart_island.view().notices == 1)
		local row_label
		for _, object in ipairs(frames) do
			for _, region in ipairs(object.regions or {}) do
				if region.text == "A notice to clear" and region.font == "GameFontHighlight" then row_label = region end
			end
		end
		check("a row is set in text type, smaller than the toast it came from, and bright while unread",
			row_label and row_label.shown ~= false and row_label.color[1] > 0.9)
		fire_after(afters, 0.75)
		check("a row you have read steps back from one you have not", addon.smart_island.view().unread_count == 0 and row_label.color[1] < 0.75)
		addon.smart_island.clear_history()
		check("clearing history keeps Undo without a disabled Clear button", clear.shown == false and undo.shown)
		check("Undo takes the right end of the notifications heading when Clear is gone", undo.point and undo.point[1] == "TOPRIGHT" and undo.point[2] == clear.parent and undo.point[5] == -4 and clear.point[5] == -4)
		fire_after(afters, 5)
		check("expired Undo returns to the compact empty state", clear.shown == false and undo.shown == false and addon.smart_island.view().height == empty_height)
		state.time = state.time + 1
		env.everlook_smart_island_key("up")
		env.everlook_smart_island_key("down")
		heading.GetStringHeight = function() return 28 end
		addon.module.set("smart_island", "size", 150)
		check("larger native text keeps clear space above the first section", -status.point[5] >= -heading.point[5] + heading:GetStringHeight() + 6)
	end

	do
		local addon, env, event, state, afters, tickers, frames = island_world()
		event("PLAYER_LEVEL_UP", 13)
		event("PLAYER_MONEY")
		check("a disabled island ignores notices", addon.smart_island.view().mode == "closed" and #addon.smart_island.view().notices == 0)
		addon.module.set("smart_island", "enabled", true)
		local view = addon.smart_island.view()
		check("enabling shows a closed experience chip",
			view.mode == "closed" and view.shown and view.level == 12 and view.xp == 450 and view.xp_max == 1000
			and view.width == 64 and view.height == 36)
		check("the closed chip already knows the safe readouts",
			view.money == "1g 23s 45c" and view.durability == "50%" and view.bags == "8 free slots" and view.clock == "14:05" and view.coords == nil)
		state.xp = 600
		event("PLAYER_XP_UPDATE", "player")
		check("experience updates the fill without a notice", addon.smart_island.view().xp == 600 and addon.smart_island.view().mode == "closed" and #addon.smart_island.view().notices == 0)
		state.level = 13
		event("PLAYER_LEVEL_UP", 13)
		check("a level-up emerges below a steady island",
			addon.smart_island.view().mode == "closed" and last_toast_text(addon) == "Level 13" and addon.smart_island.view().width == 64)
		fire_after(afters, 4)
		finish_animations(frames)
		check("the level toast leaves with its inbox row", addon.smart_island.view().mode == "closed" and last_toast_text(addon) == nil and #addon.smart_island.view().notices == 0)
		addon.module.set("smart_island", "enabled", false)
		check("turning the island off hides it and drops notices",
			addon.smart_island.view().shown == false and #addon.smart_island.view().notices == 0 and tickers[#tickers].cancelled)
	end
	do
		local addon, _, _, _, afters, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		local pill
		for index = 1, #frames do
			if frames[index].name == "EverlookSmartIsland" then
				pill = frames[index]
			end
		end
		check("the island is its own mouse frame", pill ~= nil)
		pill.scripts.OnEnter(pill)
		check("hover opens a preview of the data bar", addon.smart_island.view().mode == "open" and addon.smart_island.view().hovering and addon.smart_island.view().width == 440)
		pill.scripts.OnLeave(pill)
		fire_after(afters, 0.1)
		check("leaving a hover closes the island", addon.smart_island.view().mode == "closed" and not addon.smart_island.view().hovering)
		pill.scripts.OnClick(pill)
		check("a click pins the island open", addon.smart_island.view().pinned and addon.smart_island.view().mode == "open")
		pill.scripts.OnLeave(pill)
		check("leaving a pinned island keeps it open", addon.smart_island.view().mode == "open")
		pill.scripts.OnClick(pill)
		check("a second click lets the island close", not addon.smart_island.view().pinned and addon.smart_island.view().mode == "closed")
	end
	do
		local addon, _, _, state, _, tickers, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		local root
		for _, frame in ipairs(frames) do
			if frame.name == "EverlookSmartIsland" then root = frame end
		end
		local placements = 0
		local place = root.SetPoint
		function root:SetPoint(...)
			placements = placements + 1
			return place(self, ...)
		end
		local tick = tickers[#tickers].callback
		tick()
		tick()
		check("a quiet closed island keeps its layout between seconds", placements == 0)
		root.scripts.OnClick(root)
		placements = 0
		tick()
		check("an open bar with the same minute stays still", placements == 0 and addon.smart_island.view().clock == "14:05" and addon.smart_island.view().mode == "open")
		state.minute = 6
		tick()
		check("the open bar updates when the minute changes", placements == 1 and addon.smart_island.view().clock == "14:06")
		root.scripts.OnClick(root)
		placements = 0
		state.minute = 7
		tick()
		check("a closed chip does not relayout for the clock", placements == 0 and addon.smart_island.view().mode == "closed")
	end
	do
		local addon, _, _, state, _, tickers, frames = quest_world()
		addon.module.set("smart_island", "quest_context", true)
		local root
		for _, frame in ipairs(frames) do
			if frame.name == "EverlookSmartIsland" then root = frame end
		end
		local placements = 0
		local place = root.SetPoint
		function root:SetPoint(...)
			placements = placements + 1
			return place(self, ...)
		end
		local tick = tickers[#tickers].callback
		tick()
		check("an unchanged quest chip stays still", placements == 0)
		state.quests[2].distance = 700
		state.time = state.time + 1
		tick()
		check("a new quest distance redraws the closed chip", placements == 1 and addon.smart_island.view().quests.current.distance == 700)
	end
	do
		local addon, env, event, state, _, _, frames = island_world()
		env.everlook_smart_island_key("down")
		env.everlook_smart_island_key("up")
		check("a disabled island leaves the key alone", addon.smart_island.view().mode == "closed" and not addon.smart_island.view().pinned)
		addon.module.set("smart_island", "enabled", true)
		env.everlook_smart_island_key("down")
		check("the key peeks while it is down", addon.smart_island.view().holding and addon.smart_island.view().mode == "open")
		env.everlook_smart_island_key("up")
		check("a tap pins the island", addon.smart_island.view().pinned and addon.smart_island.view().mode == "open" and not addon.smart_island.view().holding)
		env.everlook_smart_island_key("down")
		env.everlook_smart_island_key("up")
		check("a second tap unpins the island", not addon.smart_island.view().pinned and addon.smart_island.view().mode == "closed")
		env.everlook_smart_island_key("down")
		state.time = 100.3
		env.everlook_smart_island_key("up")
		check("holding the key peeks and releasing leaves it closed", not addon.smart_island.view().pinned and addon.smart_island.view().mode == "closed")
		env.everlook_smart_island_key("down")
		env.everlook_smart_island_key("up")
		check("a tap after a hold pins it", addon.smart_island.view().pinned)
		env.everlook_smart_island_key("down")
		state.time = 100.6
		env.everlook_smart_island_key("up")
		check("holding while pinned restores the pin", addon.smart_island.view().pinned and addon.smart_island.view().mode == "open")
		for _, frame in ipairs(frames) do
			if frame.name == "EverlookRadialButton" then
				frame.scripts.PreClick(frame, "LeftButton", true)
				frame.scripts.PostClick(frame, "LeftButton", true)
				frame.scripts.PreClick(frame, "LeftButton", false)
				frame.scripts.PostClick(frame, "LeftButton", false)
			end
		end
		check("the island key does not reuse the radial menu binding", addon.smart_island.view().pinned)
	end
	do
		local addon, env, event, state, afters, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		addon.module.set("smart_island", "source_money", true)
		env.everlook_smart_island_key("down")
		env.everlook_smart_island_key("up")
		state.money = 22345
		event("PLAYER_MONEY")
		fire_after(afters, 0.75)
		check("an open island keeps a money notice in the list",
			addon.smart_island.view().mode == "open" and addon.smart_island.view().notices[1].money == 10000 and last_toast_text(addon) == nil)
		env.everlook_smart_island_key("down")
		env.everlook_smart_island_key("up")
		check("closing the island keeps the notice until its clock ends", #addon.smart_island.view().notices == 1)
		state.slots[1] = { 10, 50 }
		event("UPDATE_INVENTORY_DURABILITY")
		check("a low durability threshold creates a toast", last_toast_text(addon) == "Equipment at 20%" and addon.smart_island.view().mode == "closed")
		fire_after(afters, 4)
		state.bags[0], state.bags[1] = 1, 0
		event("BAG_UPDATE_DELAYED")
		check("low bag slots create a toast", last_toast_text(addon) == "Only 1 free slot")
		addon.module.set("coordinates", "enabled", true)
		event("PLAYER_ENTERING_WORLD")
		env.everlook_smart_island_key("down")
		check("coordinates join the open bar only when that module is on", addon.smart_island.view().coords == "50.0, 25.0")
		do
			local position, money_cell
			for _, object in ipairs(frames) do
				for _, region in ipairs(object.regions or {}) do
					if region.text == "Position" and region.shown ~= false then position = region.parent.parent end
					if region.text == "Money" and region.shown ~= false then money_cell = region.parent.parent end
				end
			end
			check("the position cell shares money's row, to its right",
				position and money_cell and position.point[5] == money_cell.point[5] and position.point[4] == money_cell.point[4] + money_cell.width + 8)
		end
		addon.module.set("coordinates", "enabled", false)
		event("PLAYER_ENTERING_WORLD")
		check("clearing coordinates removes them from the island", addon.smart_island.view().coords == nil)
		env.InCombatLockdown = function() return true end
		local ok = pcall(function()
			event("PLAYER_XP_UPDATE", "player")
			event("PLAYER_MONEY")
			event("UPDATE_INVENTORY_DURABILITY")
			event("BAG_UPDATE_DELAYED")
		end)
		check("combat still paints the safe readouts and never reads health, power or names",
			ok and state.health_reads == 0 and state.power_reads == 0 and state.name_reads == 0
			and addon.smart_island.view().money ~= nil)
		addon.module.set("smart_island", "enabled", false)
		check("disabling removes only the island", addon.smart_island.view().shown == false)
	end
	do
		local addon, env, event, state, _, _, frames = island_world()
		env.GetMoney = nil
		env.GetInventoryItemDurability = nil
		env.C_Container = nil
		env.GetGameTime = nil
		addon.module.set("smart_island", "enabled", true)
		local view = addon.smart_island.view()
		check("a missing readout API leaves that field blank and keeps experience",
			view.level == 12 and view.xp == 450 and view.money == nil and view.durability == nil and view.bags == nil and view.clock == nil)
		env.issecretvalue = function(value) return value == 450 or value == 1000 end
		state.xp, state.xp_max = 450, 1000
		event("PLAYER_XP_UPDATE", "player")
		check("secret experience still updates the bar values", addon.smart_island.view().xp == 450 and addon.smart_island.view().xp_max == 1000)
		env.issecretvalue = function(value) return value == 20 or value == 50 end
		state.slots[1], state.slots[5] = { 20, 50 }, nil
		event("UPDATE_INVENTORY_DURABILITY")
		check("secret durability is not turned into a percent", addon.smart_island.view().durability == nil or addon.smart_island.view().durability == "")
	end
	do
		local addon, env, event, state, _, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		local bar = island_fill(frames)
		check("the closed pill draws no experience bar, with a numeric reading or a secret one",
			addon.smart_island.view().xp == 450 and bar.shown ~= true)
		local xp, xp_max = secret_stat(), secret_stat()
		check("a secret experience reading is not a number", type(xp) ~= "number" and type(xp_max) ~= "number")
		env.issecretvalue = function(value) return value == xp or value == xp_max end
		state.xp, state.xp_max = xp, xp_max
		event("PLAYER_XP_UPDATE", "player")
		check("a secret reading is kept as it arrived and draws nothing",
			addon.smart_island.view().xp == xp and addon.smart_island.view().xp_max == xp_max and island_fill(frames).shown ~= true)
		env.everlook_smart_island_key("down")
		local open = addon.smart_island.view()
		check("the open island still reads its other figures, and draws no bar either",
			open.mode == "open" and island_fill(frames).shown ~= true
			and open.money == "1g 23s 45c" and open.durability == "50%" and open.bags == "8 free slots" and open.clock == "14:05")
		local function status_top()
			for _, object in ipairs(frames) do
				for _, region in ipairs(object.regions or {}) do
					if region.text == "STATUS" and region.shown ~= false then return -region.point[5] end
				end
			end
		end
		check("the Status heading is a section gap under the level line: edge, line, section", status_top() == 12 + 14 + 16)
		state.xp, state.xp_max = 700, 2000
		env.issecretvalue = nil
		event("PLAYER_XP_UPDATE", "player")
		check("a numeric reading after a secret one is read again", addon.smart_island.view().xp == 700)
	end
	do
		local addon, env = island_world()
		addon.module.set("smart_island", "enabled", true)
		env.everlook_smart_island_key("down")
		addon.module.set("smart_island", "enabled", false)
		env.everlook_smart_island_key("up")
		check("turning the island off mid-press still releases the hold", not addon.smart_island.view().holding and addon.smart_island.view().shown == false)
	end

	do
		local addon, env, _, _, afters, _, frames = island_world()
		local api = env.Everlook.island
		check("addon modules and other addons share Everlook.island", type(api) == "table" and type(api.notify) == "function" and addon.island == api)
		local handle, reason = api.notify({ text = "Repair complete", source = "TestAddon" })
		check("disabled notifications are rejected without retaining history", handle == nil and reason == "disabled" and #addon.smart_island.view().notices == 0)
		addon.module.set("smart_island", "enabled", true)
		local payload = { text = "Repair complete", source = "TestAddon", kind = "repair", duration = 6 }
		handle = api.notify(payload)
		payload.text = "Caller changed its table"
		local view = addon.smart_island.view()
		check("external notifications reach the island and own their payload",
			type(handle) == "number" and view.toasts[1].text == "Repair complete" and view.notices[1].id == handle
			and view.notices[1].source == "TestAddon" and view.notices[1].kind == "repair")
		view.notices[1].text = "Caller changed its snapshot"
		check("notification snapshots cannot change the displayed message", addon.smart_island.view().notices[1].text == "Repair complete")
		fire_after(afters, 6)
		check("the requested duration starts the toast's exit", addon.smart_island.view().toasts[1].phase == "exiting")
		finish_animations(frames)
		check("a notification duration removes the toast and the inbox row", #addon.smart_island.view().toasts == 0 and #addon.smart_island.view().notices == 0)
	end

	do
		local addon, env, _, _, afters = island_world()
		addon.module.set("smart_island", "enabled", true)
		local api = env.Everlook.island
		local first = api.notify({ source = "RepairAddon", key = "repair", text = "Repair started" })
		local updated = api.notify({ source = "RepairAddon", key = "repair", text = "Repair complete" })
		check("a source key updates one notification with a stable handle", first == updated and #addon.smart_island.view().notices == 1 and last_toast_text(addon) == "Repair complete")
		fire_after(afters, 4)
		check("the earlier timeout cannot expire an updated notification", last_toast_text(addon) == "Repair complete")
		local other = api.notify({ source = "OtherAddon", key = "repair", text = "Other notice" })
		check("notification keys belong to their source", other ~= first and #addon.smart_island.view().notices == 2)
		check("dismissing an older notice leaves the other toast", api.dismiss(first) and last_toast_text(addon) == "Other notice")
		check("dismissing the active notice closes its history row", api.dismiss(other) and addon.smart_island.view().mode == "closed" and #addon.smart_island.view().notices == 0)
		check("dismiss reports an unknown handle", not api.dismiss(other))
		local old = api.notify({ text = "Old session" })
		local old_timeout = afters[#afters].callback
		addon.module.set("smart_island", "enabled", false)
		addon.module.set("smart_island", "enabled", true)
		local fresh = api.notify({ text = "New session" })
		check("handles are not reused after disabling", fresh ~= old and not api.dismiss(old))
		old_timeout()
		check("pending timeouts from before disable leave the new toast", last_toast_text(addon) == "New session")
		for index = 1, 14 do api.notify({ text = "Notice " .. index }) end
		local notices = addon.smart_island.view().notices
		check("notification history remains bounded", #notices == 10 and notices[1].text == "Notice 5" and notices[10].text == "Notice 14")
	end

	do
		local addon, env, event, _, _, _, frames = island_world()
		local api = env.Everlook.island
		local calls = 0
		local hook = api.register_event("QUEST_TURNED_IN", function(name, quest_id, xp, money)
			calls = calls + 1
			check("event adapters receive the original WoW arguments", name == "QUEST_TURNED_IN" and quest_id == 42 and xp == 50 and money == 100)
			return { source = "TestAddon", text = "Quest turned in" }
		end)
		local adapter_frame = frames[#frames]
		event("QUEST_TURNED_IN", 42, 50, 100)
		check("disabled islands do not run registered event adapters", calls == 0)
		addon.module.set("smart_island", "enabled", true)
		event("QUEST_TURNED_IN", 42, 50, 100)
		check("a WoW event can feed an external notification", calls == 1 and last_toast_text(addon) == "Quest turned in")
		local optional = api.register_event("QUEST_WATCH_LIST_CHANGED", function(name, quest_id, added)
			check("event adapters preserve optional nil arguments", name == "QUEST_WATCH_LIST_CHANGED" and quest_id == nil and added == true)
		end)
		event("QUEST_WATCH_LIST_CHANGED", nil, true)
		api.unregister_event(optional)
		local second = api.register_event("QUEST_TURNED_IN", function() return { text = "Second addon" } end)
		check("unregister reports an existing event subscription", api.unregister_event(hook))
		event("QUEST_TURNED_IN", 42, 50, 100)
		check("removing one event adapter leaves another active", calls == 1 and last_toast_text(addon) == "Second addon")
		api.unregister_event(second)
		check("removing the last adapter releases its native event subscription", not adapter_frame.events.QUEST_TURNED_IN and not api.unregister_event(second))
		local errors = {}
		env.geterrorhandler = function() return function(message) errors[#errors + 1] = message end end
		api.register_event("QUEST_TURNED_IN", function() error("broken producer") end)
		api.register_event("QUEST_TURNED_IN", function() return { text = "Still delivered" } end)
		event("QUEST_TURNED_IN")
		check("one faulty producer reports an error without blocking another", #errors == 1 and errors[1]:find("QUEST_TURNED_IN", 1, true) and errors[1]:find("broken producer", 1, true) and last_toast_text(addon) == "Still delivered")
		addon.module.set("smart_island", "enabled", false)
		addon.module.set("smart_island", "enabled", true)
		event("QUEST_TURNED_IN")
		check("event subscriptions survive a disable and re-enable", last_toast_text(addon) == "Still delivered")
	end

	do
		local addon, env, event = island_world()
		addon.module.set("smart_island", "enabled", true)
		local api, calls = env.Everlook.island, 0
		api.register_event("QUEST_TURNED_IN", function() addon.module.set("smart_island", "enabled", false) end)
		api.register_event("QUEST_TURNED_IN", function() calls = calls + 1 end)
		event("QUEST_TURNED_IN")
		check("disabling during an event stops remaining producers", calls == 0)
	end
	do
		local addon, env, event, _, _, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		local api = env.Everlook.island
		local secret = secret_stat()
		env.issecretvalue = function(value) return value == secret end
		local cases = {
			{ secret, "invalid_notification" },
			{ "message", "invalid_notification" },
			{ { text = "   " }, "invalid_text" },
			{ { text = string.rep("x", 513) }, "invalid_text" },
			{ { text = secret }, "invalid_text" },
			{ { text = "Safe", source = secret }, "invalid_source" },
			{ { text = "Safe", key = secret }, "invalid_key" },
			{ { text = "Safe", kind = secret }, "invalid_kind" },
			{ { text = "Safe", duration = secret }, "invalid_duration" },
			{ { text = "Safe", duration = 0 / 0 }, "invalid_duration" },
			{ { text = "Safe", duration = math.huge }, "invalid_duration" },
			{ { text = "Safe", duration = 0 }, "invalid_duration" },
			{ { text = "Safe", duration = 31 }, "invalid_duration" },
			{ { text = "Safe", persist = secret }, "invalid_persist" },
			{ { text = "Safe", persist = "yes" }, "invalid_persist" },
			{ { text = "Safe", stack = secret }, "invalid_stack" },
			{ { text = "Safe", stack = "   " }, "invalid_stack" },
			{ { text = "Safe", stack = string.rep("s", 65) }, "invalid_stack" },
			{ setmetatable({}, { __index = function() error("foreign code") end }), "invalid_notification" },
		}
		for index, case in ipairs(cases) do
			local ok, handle, reason = pcall(api.notify, case[1])
			check("invalid notification " .. index .. " is rejected without inspecting secret values", ok and handle == nil and reason == case[2])
		end
		check("invalid input adds no notifications", #addon.smart_island.view().notices == 0)
		check("secret handles cannot dismiss notifications or event subscriptions", not api.dismiss(secret) and not api.unregister_event(secret))
		local calls, removed = 0
		api.register_event("QUEST_TURNED_IN", function() api.unregister_event(removed) end)
		removed = api.register_event("QUEST_TURNED_IN", function() calls = calls + 1 end)
		event("QUEST_TURNED_IN")
		check("an adapter removed during dispatch is skipped", calls == 0)
		local handle, reason = api.register_event(secret, function() end)
		check("secret event names are rejected", handle == nil and reason == "invalid_event")
		handle, reason = api.register_event("QUEST_TURNED_IN", "callback")
		check("invalid event callbacks are rejected", handle == nil and reason == "invalid_callback")
		for _, frame in ipairs(frames) do
			if frame.events.QUEST_TURNED_IN then frame.RegisterEvent = function() return false end end
		end
		handle, reason = api.register_event("NOT_A_WOW_EVENT", function() end)
		check("a refused native event registration is not retained", handle == nil and reason == "invalid_event")
		local errors = {}
		env.geterrorhandler = function() return function(message) errors[#errors + 1] = message end end
		-- Use a fresh fixture because the native event stub above intentionally rejects registration.
		local other, other_env, other_event = island_world()
		other.module.set("smart_island", "enabled", true)
		other_env.geterrorhandler = env.geterrorhandler
		other_env.Everlook.island.register_event("QUEST_TURNED_IN", function() return { text = "" } end)
		other_env.Everlook.island.register_event("QUEST_TURNED_IN", function() return nil end)
		other_event("QUEST_TURNED_IN")
		check("invalid adapter output is observable and nil means no notice", #errors == 1 and errors[1]:find("invalid_text", 1, true) and #other.smart_island.view().notices == 0)
	end

	do
		local addon, env, _, _, afters = island_world()
		addon.module.set("smart_island", "enabled", true)
		env.everlook_smart_island_key("down")
		env.everlook_smart_island_key("up")
		local api = env.Everlook.island
		local handle = api.notify({ text = "Delivered while open" })
		local view = addon.smart_island.view()
		check("an external notice respects an open island", view.mode == "open" and #view.toasts == 0 and view.notices[1].id == handle and #afters == 1 and afters[1].delay == 0.75)
		check("default notification fields are applied", view.notices[1].source == "everlook" and view.notices[1].kind == "info" and view.notices[1].duration == 4)
		check("dismissing an open row preserves the pin", api.dismiss(handle) and addon.smart_island.view().pinned and #addon.smart_island.view().notices == 0)
	end

	do
		local feeds = {}
		for _, file in ipairs({ "island_share", "island_quest_notices", "island_loot", "island_hearth", "island_reputation", "island_professions",
			"island_mail", "island_invites", "island_buffs", "island_recap", "island_experience", "island_warnings" }) do
			feeds[file] = true
		end
		local addon, env, event = load_qol(feeds)
		addon.module.set("smart_island", "enabled", true)
		check("the island runs with its feed addons turned off", addon.smart_island.apply_preset("Informative")
			and addon.module.get("smart_island", "closed_clock") == true and addon.module.get("smart_island", "feed_loot") == nil)
		event("CHAT_MSG_LOOT", "You receive loot: [Thing].")
		event("BAG_UPDATE_DELAYED")
		event("QUEST_TURNED_IN", 5, 0, 0)
		local handle = env.Everlook.island.notify({ text = "Still delivered" })
		check("notices still reach the island without its feeds", handle ~= nil and #addon.smart_island.view().notices == 1)
		local names, island = {}, nil
		for _, module in ipairs(addon.module.modules) do
			if module.id == "smart_island" then island = module end
		end
		for _, section in ipairs(addon.module.sections(island)) do names[#names + 1] = section.name end
		check("the island keeps its own sections without its feeds", table.concat(names, ",") == "Presets,Placement,Opening,Closed pill,Quest display,Notices,Activity")
	end

	do
		local addon, env = load_qol()
		check("the island API sits on the shared namespace without its internals", env.Everlook.island == addon.island and env.Everlook.island.notify and env.Everlook.island.view == nil)
	end

	do
		local addon, env, _, _, afters, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		local api = env.Everlook.island
		local first = api.notify({ text = "First notice", duration = 2 })
		local second = api.notify({ text = "Second notice", duration = 6 })
		local third = api.notify({ text = "Third notice", duration = 8 })
		local view = addon.smart_island.view()
		check("three notices emerge together without resizing the island", #view.toasts == 3 and view.width == 64 and view.mode == "closed")
		check("concurrent notices keep their own text and handles", view.toasts[1].id == first and view.toasts[2].id == second and view.toasts[3].id == third and view.toasts[2].text == "Second notice")
		finish_animations(frames)
		view = addon.smart_island.view()
		check("toast entrances settle into separate rows", view.toasts[1].alpha == 1 and view.toasts[1].y > view.toasts[2].y and view.toasts[2].y > view.toasts[3].y)
		fire_after(afters, 2)
		check("only the expired toast begins leaving", addon.smart_island.view().toasts[1].phase == "exiting" and addon.smart_island.view().toasts[2].phase == "visible")
		finish_animations(frames)
		view = addon.smart_island.view()
		check("an expired toast leaves the other notices visible", #view.toasts == 2 and view.toasts[1].id == second and view.toasts[2].id == third)
	end

	do
		local addon, env, _, _, afters, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		for index = 1, 4 do env.Everlook.island.notify({ text = "Burst " .. index, duration = index + 1 }) end
		local view = addon.smart_island.view()
		check("a fourth toast waits for a visible slot", #view.toasts == 3 and #view.queue == 1 and view.queue[1].text == "Burst 4")
		check("queued notices do not start their reading timer", #afters == 3)
		finish_animations(frames)
		fire_after(afters, 2)
		finish_animations(frames)
		view = addon.smart_island.view()
		check("a queued toast enters when an earlier toast finishes leaving", #view.toasts == 3 and #view.queue == 0 and view.toasts[3].text == "Burst 4" and afters[#afters].delay == 5)
	end

	do
		local addon, env, _, _, afters, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		env.Everlook.island.notify({ text = "First use", duration = 2 })
		finish_animations(frames)
		fire_after(afters, 2)
		finish_animations(frames)
		local frame_count = #frames
		env.Everlook.island.notify({ text = "Reuse the first slot" })
		finish_animations(frames)
		local view = addon.smart_island.view()
		check("a reused toast frame becomes visible at the same position", #view.toasts == 1 and view.toasts[1].alpha == 1 and view.toasts[1].phase == "visible" and #frames == frame_count)
	end
	do
		local addon, env, _, _, afters, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		addon.module.set("smart_island", "reduced_motion", true)
		local handle = env.Everlook.island.notify({ text = "A quieter notice" })
		local view = addon.smart_island.view()
		check("reduced motion fades a toast at its final position", view.toasts[1].y == -8 and view.toasts[1].alpha == 0)
		finish_animations(frames)
		addon.module.set("smart_island", "reduced_motion", false)
		finish_animations(frames)
		env.Everlook.island.dismiss(handle)
		addon.module.set("smart_island", "reduced_motion", true)
		view = addon.smart_island.view()
		check("enabling reduced motion also settles a pending exit", view.toasts[1].y == 0)
		finish_animations(frames)
		check("a reduced-motion exit still cleans up the toast", #addon.smart_island.view().toasts == 0)
	end

	do
		local addon, env, _, _, afters, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		local api = env.Everlook.island
		local active = api.notify({ source = "Producer", key = "work", text = "Working", duration = 2 })
		local old_timeout = afters[#afters].callback
		local handles = {}
		for index = 2, 14 do handles[index] = api.notify({ text = "Burst " .. index }) end
		local view = addon.smart_island.view()
		check("burst limits keep three active and preserve five waiting peers", #view.toasts == 3 and #view.queue == 5 and view.queue[1].text == "Burst 4" and view.queue[5].text == "Burst 8")
		local updated = api.notify({ source = "Producer", key = "work", text = "Done", duration = 6 })
		check("a keyed toast stays stable even after its history row is evicted", updated == active and addon.smart_island.view().toasts[1].text == "Done")
		old_timeout()
		check("the replaced timer cannot close an updated toast", addon.smart_island.view().toasts[1].phase ~= "exiting")
		api.dismiss(handles[4])
		local queued = api.notify({ source = "Producer", key = "pending", text = "Queued" })
		local timer_count = #afters
		updated = api.notify({ source = "Producer", key = "pending", text = "Queued update", duration = 8 })
		view = addon.smart_island.view()
		check("queued updates replace one row without consuming a slot or timer", queued == updated and #view.queue == 5 and view.queue[5].text == "Queued update" and #afters == timer_count)
		check("a queued notification can be dismissed before it appears", api.dismiss(queued) and #addon.smart_island.view().queue == 4)
		finish_animations(frames)
		api.dismiss(active)
		check("dismissing a visible toast begins an individual exit", addon.smart_island.view().toasts[1].phase == "exiting" and #addon.smart_island.view().toasts == 3)
		finish_animations(frames)
		check("a dismissal makes room for the next queued notice", #addon.smart_island.view().toasts == 3 and #addon.smart_island.view().queue == 3)
	end
	do
		local addon, env, _, _, afters, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		local api = env.Everlook.island
		local first = api.notify({ text = "A" })
		for index = 1, 3 do api.notify({ text = "More " .. index }) end
		local stale_timeout = afters[1].callback
		local stale_finished
		for _, card in ipairs(frames) do
			for _, group in ipairs(card.animation_groups or {}) do
				stale_finished = stale_finished or group.scripts.OnFinished
			end
		end
		addon.module.set("smart_island", "enabled", false)
		check("disabling removes the active stack and waiting notices immediately", #addon.smart_island.view().toasts == 0 and #addon.smart_island.view().queue == 0)
		addon.module.set("smart_island", "enabled", true)
		api.notify({ text = "Fresh" })
		stale_timeout()
		stale_finished()
		check("old timer and animation completions cannot affect reused frames", #addon.smart_island.view().toasts == 1 and addon.smart_island.view().toasts[1].text == "Fresh" and not api.dismiss(first))
		addon.module.set("smart_island", "toasts", false)
		api.notify({ text = "History only" })
		check("toast controls preserve notifications in the expanded history", #addon.smart_island.view().toasts == 0 and #addon.smart_island.view().queue == 0 and addon.smart_island.view().notices[#addon.smart_island.view().notices].text == "History only")
	end
	do
		local addon, env, _, state, afters, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		for index = 1, 4 do env.Everlook.island.notify({ text = "Peek " .. index, duration = index + 1 }) end
		finish_animations(frames)
		env.everlook_smart_island_key("down")
		check("opening the island hides the stack immediately", addon.smart_island.view().mode == "open" and not addon.smart_island.view().toasts[1].shown)
		fire_after(afters, 2)
		check("the queue and active lifetimes pause during inspection", #addon.smart_island.view().toasts == 3 and #addon.smart_island.view().queue == 1)
		state.time = state.time + 0.3
		env.everlook_smart_island_key("up")
		check("closing a peek resumes the stack without consuming its queue", addon.smart_island.view().mode == "closed" and #addon.smart_island.view().toasts == 3 and #addon.smart_island.view().queue == 1 and addon.smart_island.view().toasts[1].shown)
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		env.UIParent.GetWidth = function() return 240 end
		addon.module.set("smart_island", "enabled", true)
		env.Everlook.island.notify({ text = string.rep("Long notice ", 30) })
		local view = addon.smart_island.view()
		check("long notices wrap inside the screen width", view.toasts[1].width == 208 and view.toasts[1].height > 34)
		for _, card in ipairs(frames) do
			if card.animation_groups then check("toast surfaces let clicks through to the game", card.mouse == false) end
		end
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		addon.module.set("smart_island", "enabled", true)
		local api = env.Everlook.island
		local handle = api.notify({ source = "A", key = "a", text = "In flight" })
		for _, card in ipairs(frames) do
			for _, group in ipairs(card.animation_groups or {}) do
				for _, animation in ipairs(group.animations) do animation.progress = 0.5 end
			end
		end
		local before = addon.smart_island.view().toasts[1]
		api.notify({ source = "A", key = "a", text = "Updated in flight" })
		local after = addon.smart_island.view().toasts[1]
		check("mid-animation updates keep the current position and opacity", before.y == after.y and before.alpha == after.alpha and after.id == handle)
		api.dismiss(handle)
		after = addon.smart_island.view().toasts[1]
		check("an interrupted entrance starts its exit from the visible position", before.y == after.y and before.alpha == after.alpha and after.phase == "exiting")
	end

	local function island_action_tests()
		local function button_named(frames, label)
			for index = 1, #frames do
				local frame = frames[index]
				if frame.action_id and frame.label and frame.label.text == label and frame.shown ~= false then return frame end
			end
		end
		local function callback(record, name)
			return function(handle, action_id) record[#record + 1] = { name = name, handle = handle, action = action_id } end
		end
		do
			local addon, env, _, _, _, _, frames = island_world()
			addon.module.set("smart_island", "enabled", true)
			local api, seen = env.Everlook.island, {}
			local payload = { text = "Hearthstone ready", source = "everlook.hearth", key = "ready",
				actions = { { id = "look", label = "Inspect", type = "callback", on_click = callback(seen, "look") } } }
			local handle = api.notify(payload)
			payload.actions[1].label = "Changed"
			local notice = addon.smart_island.view().notices[1]
			check("actions default to buttons and stay copied", handle and notice.interaction == "buttons" and notice.actions[1].label == "Inspect")
			local button = button_named(frames, "Inspect")
			check("a callback button is on the toast", button ~= nil)
			button.scripts.OnEnter(button)
			check("an action hover leaves the island preview closed", addon.smart_island.view().mode == "closed" and addon.smart_island.view().hovering == false)
			button.scripts.OnClick(button, "LeftButton")
			check("a callback receives the notice handle and action id", seen[1].handle == handle and seen[1].action == "look")
			local stale = button.scripts.OnClick
			api.notify({ text = "Hearthstone ready", source = "everlook.hearth", key = "ready",
				actions = { { id = "look", label = "Inspect", type = "callback", on_click = callback(seen, "next") } } })
			stale(button, "LeftButton")
			button = button_named(frames, "Inspect")
			button.scripts.OnClick(button, "LeftButton")
			check("a replaced callback ignores the previous click", #seen == 2 and seen[2].name == "next")
		end
		do
			local addon, env, _, state, afters, _, frames = island_world()
			addon.module.set("smart_island", "enabled", true)
			local api = env.Everlook.island
			api.notify({ text = "Stay visible", duration = 4, interaction = "buttons",
				actions = { { id = "keep", label = "Keep", type = "callback", on_click = function() end } } })
			local button = button_named(frames, "Keep")
			state.time = state.time + 1
			button.scripts.OnEnter(button)
			fire_after(afters, 4)
			check("hovering an action pauses that toast", #addon.smart_island.view().toasts == 1)
			state.time = state.time + 10
			button.scripts.OnLeave(button)
			check("leaving an action restarts the full lifetime", afters[#afters].delay == 4)
			fire_after(afters, 4)
			finish_animations(frames)
			check("the restarted lifetime still dismisses the toast", #addon.smart_island.view().toasts == 0)
		end
		do
			local addon, env, _, state, afters, _, frames = island_world()
			addon.module.set("smart_island", "enabled", true)
			env.Everlook.island.notify({ text = "Leaving", duration = 4, interaction = "buttons",
				actions = { { id = "keep", label = "Keep", type = "callback", on_click = function() end } } })
			local button = button_named(frames, "Keep")
			state.time = state.time + 4
			fire_after(afters, 4)
			check("a toast whose clock ran out is leaving", addon.smart_island.view().toasts[1].phase == "exiting")
			button.scripts.OnEnter(button)
			finish_animations(frames)
			check("the pointer reaching a leaving toast brings it back", #addon.smart_island.view().toasts == 1
				and addon.smart_island.view().toasts[1].phase == "visible")
		end
		do
			local addon, env, _, state, afters, _, frames = island_world()
			addon.module.set("smart_island", "enabled", true)
			env.Everlook.island.notify({ text = "Hovered", duration = 4, interaction = "buttons",
				actions = { { id = "keep", label = "Keep", type = "callback", on_click = function() end } } })
			local function pending(delay)
				local count = 0
				for index = 1, #afters do
					if afters[index].delay == delay and not afters[index].done then count = count + 1 end
				end
				return count
			end
			state.time = state.time + 1
			button_named(frames, "Keep").scripts.OnEnter(button_named(frames, "Keep"))
			local before = pending(4)
			env.everlook_smart_island_key("down")
			state.time = state.time + 0.3
			env.everlook_smart_island_key("up")
			check("opening the island releases a hover pause", addon.smart_island.view().mode == "closed" and pending(4) == before + 1)
			fire_after(afters, 4)
			fire_after(afters, 4)
			finish_animations(frames)
			check("the released hover still dismisses the toast", #addon.smart_island.view().toasts == 0)
		end
		do
			local addon, env, _, _, _, _, frames = island_world()
			addon.module.set("smart_island", "enabled", true)
			local api = env.Everlook.island
			local handle = api.notify({ text = "Session recap", detail = "One hour", interaction = "expand" })
			local card
			for index = 1, #frames do
				if frames[index].animation_groups and frames[index].scripts.OnClick then card = frames[index] end
			end
			card.scripts.OnClick(card, "LeftButton")
			local view = addon.smart_island.view()
			check("click to expand opens that notice", view.mode == "open" and view.notices[1].id == handle and view.notices[1].detail == "One hour")
		end
		do
			local addon, env, _, _, _, _, frames = island_world()
			addon.module.set("smart_island", "enabled", true)
			local api, seen = env.Everlook.island, {}
			api.notify({ text = "Mail is waiting", interaction = "inbox",
				actions = { { id = "later", label = "Later", type = "callback", on_click = callback(seen, "later") } } })
			local toast_mouse = true
			for index = 1, #frames do
				if frames[index].animation_groups then toast_mouse = frames[index].mouse end
			end
			check("inbox actions leave the toast click-through", toast_mouse == false and button_named(frames, "Later") == nil)
			env.everlook_smart_island_key("down")
			local button = button_named(frames, "Later")
			button.scripts.OnClick(button, "LeftButton")
			check("inbox actions run from the open notice", seen[1].action == "later")
		end
		do
			local addon, env, _, _, _, _, frames = island_world()
			addon.module.set("smart_island", "enabled", true)
			local api, seen, errors = env.Everlook.island, {}, {}
			env.geterrorhandler = function() return function(message) errors[#errors + 1] = message end end
			api.notify({ text = "Quiet in combat", actions = { { id = "go", label = "Go", type = "callback", on_click = callback(seen, "go"), allow_in_combat = true },
				{ id = "stop", label = "Stop", type = "callback", on_click = callback(seen, "stop") } } })
			local go, stop = button_named(frames, "Go"), button_named(frames, "Stop")
			env.InCombatLockdown = function() return true end
			go.scripts.OnClick(go)
			stop.scripts.OnClick(stop)
			check("combat blocks ordinary callbacks and keeps the marked ones", #seen == 1 and seen[1].name == "go")
			env.InCombatLockdown = function() return false end
			api.notify({ text = "Broken action", actions = { { id = "fail", label = "Fail", type = "callback", on_click = function() error("boom") end } } })
			button_named(frames, "Fail").scripts.OnClick(button_named(frames, "Fail"))
			check("callback failures reach the error handler", type(errors[1]) == "string" and errors[1]:find("action fail", 1, true) and errors[1]:find("boom", 1, true))
		end
		do
			local addon, env, _, _, _, _, frames = island_world()
			addon.module.set("smart_island", "enabled", true)
			local api, first_seen, second_seen = env.Everlook.island, {}, {}
			local first = api.notify({ text = "First card", actions = { { id = "one", label = "One", type = "callback", on_click = callback(first_seen, "one") } } })
			local stale = button_named(frames, "One").scripts.OnClick
			api.dismiss(first)
			finish_animations(frames)
			api.notify({ text = "Second card", actions = { { id = "two", label = "Two", type = "callback", on_click = callback(second_seen, "two") } } })
			stale()
			button_named(frames, "Two").scripts.OnClick(button_named(frames, "Two"))
			check("a reused toast cannot run the action from its previous notice", #first_seen == 0 and second_seen[1].name == "two")
		end
		do
			local addon, env, _, _, _, _, frames = island_world()
			addon.module.set("smart_island", "enabled", true)
			local api, secret = env.Everlook.island, secret_stat()
			env.issecretvalue = function(value) return rawequal(value, secret) end
			local samples = {
				{ { text = "Bad mode", interaction = "popup" }, "invalid_interaction" },
				{ { text = "Secret mode", interaction = secret }, "invalid_interaction" },
				{ { text = "Too many", actions = { { id = "a", label = "A", type = "callback", on_click = function() end },
					{ id = "b", label = "B", type = "callback", on_click = function() end },
					{ id = "c", label = "C", type = "callback", on_click = function() end } } }, "invalid_actions" },
				{ { text = "Same id", actions = { { id = "a", label = "A", type = "callback", on_click = function() end },
					{ id = "a", label = "B", type = "item", item_id = 6948 } } }, "invalid_action_id" },
				{ { text = "Mixed", actions = { { id = "a", label = "A", type = "item", item_id = 6948, on_click = function() end } } }, "invalid_action" },
				{ { text = "Bad item", actions = { { id = "a", label = "A", type = "item", item_id = 0 } } }, "invalid_action_item" },
				{ { text = "Bad spell", actions = { { id = "a", label = "A", type = "spell", spell_id = secret } } }, "invalid_action" },
				{ { text = "Bad icon", item_id = secret }, "invalid_item_id" },
			}
			for index = 1, #samples do
				local ok, handle, reason = pcall(api.notify, samples[index][1])
				check("action payload " .. index .. " is rejected", ok and handle == nil and reason == samples[index][2] and #addon.smart_island.view().notices == 0)
			end
			env.C_Item = { GetItemIconByID = function(item_id) return item_id == 6948 and 136535 or nil end }
			local handle = api.notify({ text = "Hearthstone ready", item_id = 6948 })
			local notice = addon.smart_island.view().notices[1]
			local painted = false
			for index = 1, #frames do
				for _, region in ipairs(frames[index].regions or {}) do
					if region.path == 136535 then painted = true end
				end
			end
			check("item metadata is stored for the native icon", handle and notice.item_id == 6948 and notice.interaction == nil)
			check("a generic notice paints the item icon through the capsule", painted)
		end
		do
			local addon, env, _, _, _, _, frames = island_world()
			addon.module.set("smart_island", "enabled", true)
			local api, seen = env.Everlook.island, {}
			local handle = api.notify({ text = "Pinned action", actions = { { id = "go", label = "Go", type = "callback", on_click = callback(seen, "go") } } })
			local stale = button_named(frames, "Go").scripts.OnClick
			addon.module.set("smart_island", "enabled", false)
			stale()
			check("disabling the island drops the notice and its click", #addon.smart_island.view().notices == 0 and #seen == 0 and handle ~= nil)
		end

		local function attribute_frame(frames, key, value)
			for index = 1, #frames do
				local frame = frames[index]
				if frame.attributes and frame.attributes[key] == value then return frame end
			end
		end
		local function region_text(frames, snippet)
			for index = 1, #frames do
				for _, region in ipairs(frames[index].regions or {}) do
					if type(region.text) == "string" and region.text:find(snippet, 1, true) then return region.text end
				end
			end
		end
		local function under_named(frame, name)
			local guard = 0
			while frame and guard < 12 do
				if frame.name == name then return true end
				frame = frame.parent
				guard = guard + 1
			end
			return false
		end
		local function secure_point(card)
			local point = card.point
			return point and table.concat({ tostring(point[1]), tostring(point[4]), tostring(point[5]) }, ":")
		end
		do
			local addon, env, _, _, _, _, frames = island_world()
			addon.module.set("smart_island", "enabled", true)
			local api = env.Everlook.island
			api.notify({ text = "Hearthstone ready", actions = { { id = "use", label = "Hearth", type = "item", item_id = 6948 } } })
			api.notify({ text = "Blink ready", actions = { { id = "cast", label = "Blink", type = "spell", spell_id = 1953 } } })
			finish_animations(frames)
			local view = addon.smart_island.view()
			local island
			for index = 1, #frames do
				if frames[index].name == "EverlookSmartIsland" then island = frames[index] end
			end
			local item = attribute_frame(frames, "item", "item:6948")
			local spell = attribute_frame(frames, "spell", 1953)
			local top = -(island.point[5] or 0)
			local item_y = -(top + island.height - view.toasts[1].y)
			local spell_y = -(top + island.height - view.toasts[2].y)
			check("item and spell cards are secure roots under UIParent",
				item and spell and item.scripts.OnClick == nil and spell.scripts.OnClick == nil
				and item.template:find("SecureActionButtonTemplate", 1, true) == 1 and spell.template:find("SecureActionButtonTemplate", 1, true) == 1
				and item.parent.parent == env.UIParent and spell.parent.parent == env.UIParent
				and not under_named(item, "EverlookSmartIsland") and not under_named(spell, "EverlookSmartIsland")
				and item.parent.scale == 1 and spell.parent.scale == 1
				and item.parent.point[1] == "TOP" and item.parent.point[2] == env.UIParent and item.parent.point[5] == item_y
				and spell.parent.point[5] == spell_y and item.parent.width == view.toasts[1].width)
		end
		do
			local addon, env, event, _, _, _, frames = island_world()
			addon.module.set("smart_island", "enabled", true)
			local api = env.Everlook.island
			api.notify({ text = "Hearthstone ready", source = "everlook.hearth", key = "ready",
				actions = { { id = "use", label = "Hearth", type = "item", item_id = 6948 } } })
			env.InCombatLockdown = function() return true end
			local ok, err = pcall(function()
				event("PLAYER_REGEN_DISABLED")
				finish_animations(frames)
				addon.module.set("smart_island", "position_x", 80)
				env.everlook_smart_island_key("down")
				env.everlook_smart_island_key("up")
				addon.smart_island.scroll_to(40)
				env.everlook_smart_island_key("down")
				env.everlook_smart_island_key("up")
				finish_animations(frames)
			end)
			check("combat during entrance, scrolling and placement does not touch secure frames",
				ok == true and attribute_frame(frames, "item", "item:6948") == nil and err == nil)
			check("a protected notice waits until combat ends",
				addon.smart_island.view().notices[1].deferred == true and region_text(frames, "Available after combat.") ~= nil)
			env.InCombatLockdown = function() return false end
			event("PLAYER_REGEN_ENABLED")
			finish_animations(frames)
			local item = attribute_frame(frames, "item", "item:6948")
			check("the item card arms after combat without clicking itself",
				item ~= nil and item.shown ~= false and item.scripts.OnClick == nil and item.parent.shown ~= false)
		end
		do
			local addon, env, event, state, afters, _, frames = island_world()
			addon.module.set("smart_island", "enabled", true)
			local api = env.Everlook.island
			local handle = api.notify({ text = "Hearthstone ready", source = "everlook.hearth", key = "ready", duration = 6,
				actions = { { id = "use", label = "Hearth", type = "item", item_id = 6948 } } })
			finish_animations(frames)
			local item = attribute_frame(frames, "item", "item:6948")
			local card, before = item.parent, secure_point(item.parent)
			local label = region_text(frames, "Hearthstone ready")
			env.InCombatLockdown = function() return true end
			local blocked, message = pcall(function() card:SetPoint("TOP", env.UIParent, "TOP", 9, -9) end)
			event("PLAYER_REGEN_DISABLED")
			addon.module.set("smart_island", "position_x", 80)
			env.everlook_smart_island_key("down")
			addon.smart_island.scroll_to(24)
			local dismissed, reason = api.dismiss(handle)
			local replaced, replace_reason = api.notify({ text = "Hearthstone moved", source = "everlook.hearth", key = "ready",
				actions = { { id = "use", label = "Hearth", type = "item", item_id = 6948 } } })
			local clicks = 0
			local original = card.scripts.OnMouseUp
			card.scripts.OnMouseUp = function(...)
				clicks = clicks + 1
				return original(...)
			end
			card.scripts.OnMouseUp(card, "RightButton")
			check("a frozen card rejects programmatic changes and keeps its secure click",
				blocked == false and type(message) == "string" and message:find("protected", 1, true)
				and dismissed == nil and reason == "combat_locked" and replaced == nil and replace_reason == "combat_locked"
				and secure_point(card) == before and region_text(frames, "Hearthstone ready") == label
				and card.shown ~= false and clicks == 1 and addon.smart_island.view().notices[1].text == "Hearthstone ready"
				and addon.smart_island.view().notices[1].frozen == true and #addon.smart_island.view().toasts == 1)
			state.time = state.time + 1
			fire_after(afters, 6)
			check("a frozen card ignores the timer that was running", card.shown ~= false and #addon.smart_island.view().toasts == 1)
			env.InCombatLockdown = function() return false end
			event("PLAYER_REGEN_ENABLED")
			finish_animations(frames)
			check("the player's combat dismiss removes the card when combat ends",
				clicks == 1 and card.shown == false and #addon.smart_island.view().notices == 0)
		end
		do
			local addon, env, event, _, _, _, frames = island_world()
			addon.module.set("smart_island", "enabled", true)
			local api = env.Everlook.island
			env.InCombatLockdown = function() return true end
			event("PLAYER_REGEN_DISABLED")
			local handle = api.notify({ text = "Soulstone", actions = { { id = "use", label = "Use", type = "item", item_id = 16892 } } })
			finish_animations(frames)
			check("a new protected notice during combat is visible and unarmed",
				handle and attribute_frame(frames, "item", "item:16892") == nil
				and region_text(frames, "Available after combat.") ~= nil and #addon.smart_island.view().toasts == 1)
			env.InCombatLockdown = function() return false end
			event("PLAYER_REGEN_ENABLED")
			finish_animations(frames)
			local item = attribute_frame(frames, "item", "item:16892")
			check("that notice arms only after combat", item ~= nil and item.scripts.OnClick == nil)
		end
		do
			local addon, env, event, _, _, _, frames = island_world()
			addon.module.set("smart_island", "enabled", true)
			local api = env.Everlook.island
			api.notify({ text = "Frozen loot", actions = { { id = "use", label = "Inspect", type = "item", item_id = 17182 } } })
			api.notify({ text = "Ordinary one" })
			api.notify({ text = "Ordinary two" })
			finish_animations(frames)
			local item = attribute_frame(frames, "item", "item:17182")
			env.InCombatLockdown = function() return true end
			event("PLAYER_REGEN_DISABLED")
			api.notify({ text = "Incoming damage", severity = "error" })
			local phases = {}
			for _, toast in ipairs(addon.smart_island.view().toasts) do phases[toast.text] = toast.phase end
			check("an error toast leaves a frozen protected card in its slot",
				item.parent.shown ~= false and phases["Frozen loot"] ~= "exiting" and phases["Ordinary one"] == "exiting"
				and addon.smart_island.view().notices[1].frozen == true)
		end
		do
			local addon, env, event, _, _, _, frames = island_world()
			addon.module.set("smart_island", "enabled", true)
			local api = env.Everlook.island
			api.notify({ text = "Hearthstone ready", actions = { { id = "use", label = "Hearth", type = "item", item_id = 6948 } } })
			finish_animations(frames)
			local item = attribute_frame(frames, "item", "item:6948")
			env.InCombatLockdown = function() return true end
			event("PLAYER_REGEN_DISABLED")
			addon.module.set("smart_island", "enabled", false)
			check("disabling during combat keeps the secure card",
				addon.smart_island.view().shown == false and item.parent.shown ~= false and #addon.smart_island.view().notices == 1)
			env.InCombatLockdown = function() return false end
			event("PLAYER_REGEN_ENABLED")
			finish_animations(frames)
			check("combat exit clears a card whose module is off", item.parent.shown == false and #addon.smart_island.view().notices == 0)
		end
		do
			local addon, env, event, _, _, _, frames = island_world()
			addon.module.set("smart_island", "enabled", true)
			local api = env.Everlook.island
			api.notify({ text = "Frozen loot", source = "loot", key = "frozen", actions = { { id = "use", label = "Inspect", type = "item", item_id = 17182 } } })
			api.notify({ text = "Ordinary note", source = "notes", key = "one" })
			finish_animations(frames)
			local item = attribute_frame(frames, "item", "item:17182")
			env.InCombatLockdown = function() return true end
			event("PLAYER_REGEN_DISABLED")
			local cleared = addon.smart_island.clear_history()
			local texts = {}
			for _, notice in ipairs(addon.smart_island.view().notices) do texts[#texts + 1] = notice.text end
			local again = addon.smart_island.clear_history()
			check("clear history skips a frozen card",
				cleared == true and again == false and texts[1] == "Frozen loot" and #texts == 1 and item.parent.shown ~= false)
			env.InCombatLockdown = function() return false end
			addon.smart_island.undo_clear()
			local restored
			for _, notice in ipairs(addon.smart_island.view().notices) do
				if notice.text == "Ordinary note" then restored = true end
			end
			check("undo restores only the notices clear history removed", restored == true and item.parent.shown ~= false)
		end
		do
			local addon, env, event, state, afters, _, frames = island_world()
			addon.module.set("smart_island", "enabled", true)
			local api = env.Everlook.island
			api.notify({ text = "Short hearth", duration = 2, actions = { { id = "use", label = "Hearth", type = "item", item_id = 6948 } } })
			finish_animations(frames)
			local item = attribute_frame(frames, "item", "item:6948")
			env.InCombatLockdown = function() return true end
			event("PLAYER_REGEN_DISABLED")
			state.time = state.time + 5
			fire_after(afters, 2)
			check("expiry waits while the card is frozen", item.parent.shown ~= false and #addon.smart_island.view().toasts == 1)
			env.InCombatLockdown = function() return false end
			event("PLAYER_REGEN_ENABLED")
			finish_animations(frames)
			check("an expired frozen card leaves when combat ends", item.parent.shown == false and #addon.smart_island.view().notices == 0)
		end
		do
			local addon, env, event, state, _, _, frames = island_world()
			addon.module.set("smart_island", "enabled", true)
			local api = env.Everlook.island
			api.notify({ text = "Stay armed", duration = 8, actions = { { id = "use", label = "Hearth", type = "item", item_id = 6948 } } })
			finish_animations(frames)
			local item = attribute_frame(frames, "item", "item:6948")
			local before = secure_point(item.parent)
			env.InCombatLockdown = function() return true end
			event("PLAYER_REGEN_DISABLED")
			addon.module.set("smart_island", "position_x", 40)
			check("combat movement leaves an armed card where it was", secure_point(item.parent) == before and item.parent.shown ~= false)
			env.InCombatLockdown = function() return false end
			event("PLAYER_REGEN_ENABLED")
			state.time = state.time + 1
			check("combat exit keeps the card armed and lets it follow the island",
				item.parent.shown ~= false and item.attributes.item == "item:6948" and item.scripts.OnClick == nil
				and secure_point(item.parent) ~= before and item.parent.point[4] == 40
				and #addon.smart_island.view().toasts == 1 and addon.smart_island.view().notices[1].frozen ~= true)
		end
		do
			local addon, env, _, _, _, _, frames = island_world()
			addon.module.set("smart_island", "enabled", true)
			local api = env.Everlook.island
			api.notify({ text = "Item first", actions = {
				{ id = "use", label = "Hearth", type = "item", item_id = 6948 },
				{ id = "look", label = "Inspect", type = "callback", on_click = function() end },
			} })
			api.notify({ text = "Callback first", actions = {
				{ id = "look", label = "Details", type = "callback", on_click = function() end },
				{ id = "cast", label = "Blink", type = "spell", spell_id = 1953 },
			} })
			finish_animations(frames)
			local item = attribute_frame(frames, "item", "item:6948")
			local spell = attribute_frame(frames, "spell", 1953)
			local inspect = button_named(frames, "Inspect")
			local details = button_named(frames, "Details")
			check("mixed actions keep their order on one row",
				item and spell and inspect and details
				and item.point[4] == 40 and inspect.point[4] == 168
				and details.point[4] == 40 and spell.point[4] == 168)
		end
		local function feed_tests()
			local function notice_key(addon, key)
				for _, notice in ipairs(addon.smart_island.view().notices) do
					if notice.key == key then return notice end
				end
			end
			local function listed(order, id)
				for index = 1, #(order or {}) do
					if order[index].id == id then return true end
				end
			end
			do
				local addon, env, event, state, _, _, frames = quest_world()
				check("quest feeds start off", addon.module.get("smart_island", "feed_quest_ready") == false and addon.smart_island.view().quests == nil)
				state.quests[1].ready = true
				event("QUEST_LOG_UPDATE")
				check("a ready quest stays quiet while the feed is off", #addon.smart_island.view().notices == 0)
				local opened = {}
				env.QuestMapFrame_OpenToQuestDetails = function(quest_id) opened[#opened + 1] = quest_id end
				addon.module.set("smart_island", "feed_quest_ready", true)
				check("the first ready scan keeps quests that were already ready", #addon.smart_island.view().notices == 0)
				state.quests[2].ready = true
				event("QUEST_LOG_UPDATE")
				local notice = notice_key(addon, "ready")
				check("a newly ready quest is announced once", notice and notice.text == "Suitable farther" and notice.detail == "Ready to turn in"
					and notice.persist == true and notice.actions[1].label == "View quest" and notice.actions[2].label == "Pin" and notice_key(addon, "ready:23") == nil)
				button_named(frames, "View quest").scripts.OnClick(button_named(frames, "View quest"))
				check("view quest opens the native details", opened[1] == 22)
				button_named(frames, "Pin").scripts.OnClick(button_named(frames, "Pin"))
				addon.module.set("smart_island", "quest_context", true)
				local quests = addon.smart_island.view().quests
				check("pin keeps that quest when the capsule is turned on", quests.current.id == 22 and quests.pinned == 22)
				state.quests[2].ready = false
				event("QUEST_LOG_UPDATE")
				check("leaving turn-in dismisses that notice", notice_key(addon, "ready") == nil)
				state.quests[2].ready = true
				event("QUEST_LOG_UPDATE")
				check("becoming ready again announces a new transition", notice_key(addon, "ready") ~= nil)
				state.quests[1].ready = false
				event("QUEST_LOG_UPDATE")
				state.quests[1].ready = true
				event("QUEST_LOG_UPDATE")
				notice = notice_key(addon, "ready")
				check("several ready quests share one notice", notice and notice.text == "2 quests ready" and notice.persist == true and #addon.smart_island.view().notices == 1)
				button_named(frames, "View quest").scripts.OnClick(button_named(frames, "View quest"))
				check("view quest follows the latest ready quest", opened[#opened] == 21)
				state.quests[1].ready = false
				event("QUEST_LOG_UPDATE")
				check("a smaller ready set keeps the remaining quest", notice_key(addon, "ready").text == "Suitable farther")
				state.quests[2].ready = false
				event("QUEST_LOG_UPDATE")
				check("the ready notice leaves when none of this session remain", notice_key(addon, "ready") == nil)
			end
			do
				local addon, env, event, state, _, _, frames = quest_world()
				check("next quest starts off and leaves the capsule alone", addon.module.get("smart_island", "feed_quest_next") == false and addon.smart_island.view().quests == nil)
				addon.module.set("smart_island", "feed_quest_next", true)
				check("the first planner scan is quiet", #addon.smart_island.view().notices == 0 and addon.smart_island.view().quests == nil)
				state.quests[3].distance = 1200
				event("QUEST_LOG_UPDATE")
				local first = notice_key(addon, "next-quest")
				check("a planner change toasts once", first and first.text == "Suitable farther" and first.presentation == "toast" and first.detail == "Suggested next")
				state.quests[1].level, state.quests[1].distance = 12, 50
				event("QUEST_LOG_UPDATE")
				local second = notice_key(addon, "next-quest")
				check("a second change within 30 seconds stays in the inbox", second and second.id == first.id and second.text == "Nearby dangerous" and second.presentation == "inbox")
				state.time = state.time + 30
				state.quests[2].distance = 10
				event("QUEST_LOG_UPDATE")
				local third = notice_key(addon, "next-quest")
				check("a later planner change can toast again", third and third.text == "Suitable farther" and third.presentation == "toast")
				button_named(frames, "Pin").scripts.OnClick(button_named(frames, "Pin"))
				addon.module.set("smart_island", "quest_context", true)
				local quests = addon.smart_island.view().quests
				check("pin from the next-quest notice sticks", quests.pinned == 22 and quests.current.id == 22)
			end
			do
				local addon, env, event, state, _, _, frames = quest_world()
				addon.module.set("smart_island", "feed_quest_next", true)
				state.quests[3].distance = 1200
				event("QUEST_LOG_UPDATE")
				button_named(frames, "Skip").scripts.OnClick(button_named(frames, "Skip"))
				local skipped = notice_key(addon, "next-quest")
				check("skip leaves the current suggestion immediately", skipped and skipped.text == "Ready to return")
				addon.module.set("smart_island", "quest_context", true)
				addon.module.set("smart_island", "quest_plan", true)
				local quests = addon.smart_island.view().quests
				check("a skipped quest stays in the planned order", quests.suggested ~= 22 and listed(quests.order, 22))
				state.quests[2].distance = 10
				event("QUEST_LOG_UPDATE")
				check("a skipped quest stays out after a large score change", notice_key(addon, "next-quest").text == "Ready to return")
				local removed = table.remove(state.quests, 2)
				event("QUEST_LOG_UPDATE")
				table.insert(state.quests, 2, removed)
				removed.distance = 10
				event("QUEST_LOG_UPDATE")
				check("removing a quest from the log clears its skip", notice_key(addon, "next-quest").text == "Suitable farther")
			end
			do
				local addon, _, event, state, _, _, frames = quest_world()
				addon.module.set("smart_island", "feed_quest_next", true)
				state.quests[3].distance = 1200
				event("QUEST_LOG_UPDATE")
				button_named(frames, "Skip").scripts.OnClick(button_named(frames, "Skip"))
				addon.module.set("smart_island", "enabled", false)
				addon.module.set("smart_island", "enabled", true)
				check("ending the session clears a skip without announcing the baseline", #addon.smart_island.view().notices == 0)
				state.quests[2].distance = 5000
				event("QUEST_LOG_UPDATE")
				check("the previously skipped quest can be suggested again", notice_key(addon, "next-quest").text == "Ready to return")
			end
			do
				local addon, env, event, state, _, tickers, frames = island_world()
				addon.module.set("smart_island", "enabled", true)
				local qualities = {}
				local function link(item_id, name)
					return "|cff0070dd|Hitem:" .. item_id .. "::::::::|h[" .. name .. "]|h|r"
				end
				local function receive(item_id, name, count)
					local item = link(item_id, name)
					if count then return "You receive loot: " .. item .. "x" .. count .. "." end
					return "You receive loot: " .. item .. "."
				end
				env.C_Item = { GetItemQualityByID = function(item_id) return qualities[item_id] end }
				addon.module.set("smart_island", "feed_loot", true)
				qualities[19019] = 3
				event("CHAT_MSG_LOOT", receive(19019, "Thunderfury"))
				check("loot without the self formats stays quiet", #addon.smart_island.view().notices == 0)
				env.LOOT_ITEM_SELF = "You receive loot: %s."
				env.LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
				addon.module.set("smart_island", "feed_loot", false)
				event("CHAT_MSG_LOOT", receive(19019, "Thunderfury"))
				check("rare loot stays quiet while the feed is off", #addon.smart_island.view().notices == 0)
				addon.module.set("smart_island", "feed_loot", true)
				qualities[19019] = 2
				event("CHAT_MSG_LOOT", receive(19019, "Thunderfury"))
				qualities[19019] = nil
				event("CHAT_MSG_LOOT", receive(19019, "Thunderfury"))
				local secret = secret_stat()
				env.issecretvalue = function(value) return rawequal(value, secret) end
				qualities[19019] = secret
				event("CHAT_MSG_LOOT", receive(19019, "Thunderfury"))
				event("CHAT_MSG_LOOT", secret)
				event("CHAT_MSG_LOOT", "Grom receives loot: " .. link(19019, "Thunderfury") .. ".")
				check("common, missing, secret and other players' loot are omitted", #addon.smart_island.view().notices == 0)
				qualities[19019] = 3
				local inspected = {}
				env.GameTooltip = {
					SetOwner = function() end,
					SetItemByID = function(_, item_id) inspected[#inspected + 1] = item_id end,
					Show = function() end,
				}
				event("CHAT_MSG_LOOT", receive(19019, "Thunderfury"))
				local loot = notice_key(addon, "loot:19019:1")
				check("confirmed rare loot is announced", loot and loot.text == "Thunderfury" and loot.detail == "Rare loot" and loot.item_id == 19019)
				button_named(frames, "Inspect").scripts.OnClick(button_named(frames, "Inspect"))
				check("inspect shows the item tooltip", inspected[1] == 19019)
				state.time = state.time + 1
				event("CHAT_MSG_LOOT", receive(19019, "Thunderfury"))
				loot = notice_key(addon, "loot:19019:1")
				check("the same item within two seconds stays one notice", loot and loot.text == "Thunderfury x2" and notice_key(addon, "loot:19019:2") == nil)
				state.time = state.time + 3
				event("CHAT_MSG_LOOT", receive(19019, "Thunderfury"))
				loot = notice_key(addon, "loot:19019:2")
				check("the same item after two seconds joins the live loot notice", loot and loot.text == "Thunderfury" and loot.count == 2 and notice_key(addon, "loot:19019:1") == nil)
				env.Enum = { ItemQuality = { Rare = 4 } }
				qualities[12345] = 3
				event("CHAT_MSG_LOOT", receive(12345, "Blue Gem"))
				check("quality below the rare enum is omitted", notice_key(addon, "loot:12345:1") == nil)
				qualities[12345] = 4
				event("CHAT_MSG_LOOT", receive(12345, "Blue Gem"))
				check("quality at the rare enum joins the live loot notice", notice_key(addon, "loot:12345:1").text == "Blue Gem" and notice_key(addon, "loot:12345:1").count == 3 and #addon.smart_island.view().notices == 1)
				env.LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
				env.LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."
				env.LOOT_ITEM_BONUS_ROLL_SELF = "You receive bonus loot: %s."
				env.LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE = "You receive bonus loot: %sx%d."
				qualities[19020] = 4
				event("CHAT_MSG_LOOT", "You receive item: " .. link(19020, "Bag Rare") .. ".")
				local pushed = notice_key(addon, "loot:19020:1")
				check("direct-to-bag rare loot is announced", pushed and pushed.text == "Bag Rare")
				event("CHAT_MSG_LOOT", "You receive item: " .. link(19020, "Bag Rare") .. "x3.")
				pushed = notice_key(addon, "loot:19020:1")
				check("direct-to-bag stacks combine", pushed and pushed.text == "Bag Rare x4")
				qualities[19021] = 4
				event("CHAT_MSG_LOOT", "You receive bonus loot: " .. link(19021, "Bonus Gem") .. ".")
				local bonus = notice_key(addon, "loot:19021:1")
				check("bonus rare loot is announced", bonus and bonus.text == "Bonus Gem")
				event("CHAT_MSG_LOOT", "You create: " .. link(19021, "Bonus Gem") .. ".")
				event("CHAT_MSG_LOOT", "Grom receives item: " .. link(19022, "Other Rare") .. ".")
				bonus = notice_key(addon, "loot:19021:1")
				check("crafted items and another player's pushed item stay quiet", bonus and bonus.text == "Bonus Gem" and notice_key(addon, "loot:19022:1") == nil)
				env.LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %1$sx%2$d."
				qualities[19023] = 4
				event("CHAT_MSG_LOOT", "You receive loot: " .. link(19023, "Positional") .. "x2.")
				local positional = notice_key(addon, "loot:19023:1")
				check("positional loot counts are announced", positional and positional.text == "Positional x2")
				env.LOOT_ITEM_SELF_MULTIPLE = nil
				qualities[19024] = 4
				event("CHAT_MSG_LOOT", receive(19024, "Single Only"))
				local single = notice_key(addon, "loot:19024:1")
				check("a missing multiple format still announces one item", single and single.text == "Single Only")
			end
			do
				local addon, env, event, state, _, tickers, frames = island_world()
				addon.module.set("smart_island", "enabled", true)
				local count, cooldown = 0, { 0, 0, true }
				env.C_Item = {
					GetItemCount = function(item_id) return item_id == 6948 and count or 0 end,
					GetItemCooldown = function(item_id)
						if item_id == 6948 then return cooldown[1], cooldown[2], cooldown[3] end
					end,
				}
				addon.module.set("smart_island", "feed_hearth", true)
				check("an empty hearth bag stays quiet", #addon.smart_island.view().notices == 0)
				count = 1
				event("BAG_UPDATE_DELAYED")
				check("a hearthstone that is already ready stays quiet", notice_key(addon, "hearth:ready") == nil)
				cooldown[1], cooldown[2], cooldown[3] = state.time, 1.5, true
				tickers[1].callback()
				cooldown[1], cooldown[2], cooldown[3] = 0, 0, true
				tickers[1].callback()
				check("a global cooldown does not announce the hearthstone", notice_key(addon, "hearth:ready") == nil)
				cooldown[1], cooldown[2] = state.time, 60
				tickers[1].callback()
				check("a hearthstone going on cooldown stays quiet", notice_key(addon, "hearth:ready") == nil)
				local restore = env.C_Item.GetItemCooldown
				env.C_Item.GetItemCooldown = function() end
				tickers[1].callback()
				check("an unreadable cooldown does not count as ready", notice_key(addon, "hearth:ready") == nil)
				env.C_Item.GetItemCooldown = restore
				cooldown[1], cooldown[2], cooldown[3] = 0, 0, false
				tickers[1].callback()
				cooldown[3] = 0
				tickers[1].callback()
				check("a disabled cooldown timer stays quiet", notice_key(addon, "hearth:ready") == nil)
				cooldown[3] = true
				tickers[1].callback()
				finish_animations(frames)
				local item = attribute_frame(frames, "item", "item:6948")
				local notice = notice_key(addon, "hearth:ready")
				check("a finished hearth cooldown announces a secure hearth", notice and notice.text == "Hearthstone ready" and notice.item_id == 6948
					and item and item.attributes.item == "item:6948" and item.scripts.OnClick == nil)
				button_named(frames, "Inspect").scripts.OnClick(button_named(frames, "Inspect"))
				cooldown[1], cooldown[2], cooldown[3] = state.time, 30, true
				tickers[1].callback()
				finish_animations(frames)
				check("going on cooldown dismisses the hearth notice", notice_key(addon, "hearth:ready") == nil)
				cooldown[1], cooldown[2], cooldown[3] = 0, 0, 1
				tickers[1].callback()
				finish_animations(frames)
				item = attribute_frame(frames, "item", "item:6948")
				check("a numeric cooldown enable still arms the hearth", notice_key(addon, "hearth:ready") ~= nil and item and item.attributes.item == "item:6948")
				env.InCombatLockdown = function() return true end
				event("PLAYER_REGEN_DISABLED")
				addon.module.set("smart_island", "feed_hearth", false)
				check("turning hearth off during combat leaves the armed card", item.parent.shown ~= false and notice_key(addon, "hearth:ready") ~= nil)
				env.InCombatLockdown = function() return false end
				event("PLAYER_REGEN_ENABLED")
				tickers[1].callback()
				finish_animations(frames)
				check("the hearth card leaves once combat ends", item.parent.shown == false and notice_key(addon, "hearth:ready") == nil)
			end
		end
		local function later_feed_tests()
			local function notice_key(addon, key)
				for _, notice in ipairs(addon.smart_island.view().notices) do
					if notice.key == key then return notice end
				end
			end
			do
				local addon, env, event, _, _, _, frames = island_world()
				addon.module.set("smart_island", "enabled", true)
				local factions = {
					{ factionID = 47, name = "Stormwind", reaction = 5, isHeader = false },
					{ factionID = 9, name = "Classic", reaction = 4, isHeader = true },
					{ factionID = 72, name = "Alliance", reaction = 4, isHeader = true, isHeaderWithRep = true },
				}
				env.C_Reputation = {
					GetNumFactions = function() return #factions end,
					GetFactionDataByIndex = function(index) return factions[index] end,
				}
				local opened
				env.ToggleCharacter = function(name) opened = name end
				env.FACTION_STANDING_LABEL6 = "Honored"
				check("reputation starts off", addon.module.get("smart_island", "feed_reputation") == false)
				addon.module.set("smart_island", "feed_reputation", true)
				check("the first reputation scan is quiet", #addon.smart_island.view().notices == 0)
				factions[1].reaction = 6
				factions[2].reaction = 6
				event("UPDATE_FACTION")
				local notice = notice_key(addon, "rep:47")
				check("a standing increase is announced once", notice and notice.text == "Stormwind" and notice.detail == "Honored" and notice_key(addon, "rep:9") == nil)
				button_named(frames, "Open reputation").scripts.OnClick(button_named(frames, "Open reputation"))
				check("open reputation uses the character pane", opened == "ReputationFrame")
				factions[3].reaction = 5
				event("UPDATE_FACTION")
				check("a header that tracks reputation can increase", notice_key(addon, "rep:72").text == "Alliance" and notice_key(addon, "rep:72").detail == "Standing increased")
				local secret = secret_stat()
				env.issecretvalue = function(value) return rawequal(value, secret) end
				factions[1].reaction = secret
				event("UPDATE_FACTION")
				factions[1].reaction = 6
				factions[1].currentStanding = 9999
				event("UPDATE_FACTION")
				check("secret or same-rank reputation does not add a standing", notice_key(addon, "rep:72").text == "Alliance" and notice_key(addon, "rep:72").detail == "Standing increased" and notice_key(addon, "rep:72").count == 2 and notice_key(addon, "rep:47") == nil and #addon.smart_island.view().notices == 1)
			end
			do
				local addon, env, event, state, _, _, frames = island_world()
				addon.module.set("smart_island", "enabled", true)
				local skills = { name = "Blacksmithing", skill = 20, line = 164 }
				env.GetProfessions = function() return 1 end
				env.GetProfessionInfo = function() return skills.name, nil, skills.skill, 300, 0, 0, skills.line end
				local opened
				env.ToggleProfessionsBook = function() opened = true end
				addon.module.set("smart_island", "feed_professions", true)
				check("the first profession scan is quiet", #addon.smart_island.view().notices == 0)
				skills.skill = 24
				event("SKILL_LINES_CHANGED")
				check("skill below the next 25 is quiet", #addon.smart_island.view().notices == 0)
				skills.skill = 60
				event("SKILL_LINES_CHANGED")
				local first = notice_key(addon, "professions:1")
				check("a skill jump announces the highest 25-point milestone", first and first.text == "Blacksmithing reached 50")
				state.time = state.time + 1
				event("NEW_RECIPE_LEARNED", 333)
				first = notice_key(addon, "professions:1")
				check("a recipe in the same burst updates that notice", first and first.text == "Blacksmithing reached 50. New recipe" and notice_key(addon, "professions:2") == nil)
				local secret = secret_stat()
				env.issecretvalue = function(value) return rawequal(value, secret) end
				event("NEW_RECIPE_LEARNED", secret)
				check("a secret recipe is omitted", notice_key(addon, "professions:1").text == "Blacksmithing reached 50. New recipe")
				state.time = state.time + 3
				skills.skill = 80
				event("SKILL_LINES_CHANGED")
				check("a later milestone joins the craft notice", notice_key(addon, "professions:2").text == "Blacksmithing reached 75" and notice_key(addon, "professions:2").count == 2 and notice_key(addon, "professions:1") == nil and #addon.smart_island.view().notices == 1)
				button_named(frames, "Open professions").scripts.OnClick(button_named(frames, "Open professions"))
				check("open professions uses the profession book", opened == true)
			end
			do
				local addon, env, event, state, _, tickers, frames = island_world()
				addon.module.set("smart_island", "enabled", true)
				local pending = true
				env.HasNewMail = function() return pending end
				addon.module.set("smart_island", "feed_mail", true)
				check("mail that is already waiting stays quiet", notice_key(addon, "mail:new") == nil)
				pending = false
				event("UPDATE_PENDING_MAIL")
				pending = true
				event("UPDATE_PENDING_MAIL")
				local mail = notice_key(addon, "mail:new")
				check("new mail becomes one notice", mail and mail.text == "New mail" and #addon.smart_island.view().notices == 1)
				button_named(frames, "Remind in five minutes").scripts.OnClick(button_named(frames, "Remind in five minutes"))
				check("remind dismisses the mail notice", notice_key(addon, "mail:new") == nil)
				state.time = state.time + 299
				tickers[1].callback()
				check("the reminder waits five minutes", notice_key(addon, "mail:new") == nil)
				state.time = state.time + 1
				tickers[1].callback()
				check("the reminder returns while mail is still waiting", notice_key(addon, "mail:new") ~= nil)
				pending = false
				event("UPDATE_PENDING_MAIL")
				check("read mail dismisses the notice", notice_key(addon, "mail:new") == nil)
			end
			do
				local addon, env, event, state, _, tickers, frames = island_world()
				addon.module.set("smart_island", "enabled", true)
				local buttons = {}
				env.CreateSettingsButtonInitializer = function(name, _, click)
					return { name = name, click = click }
				end
				local module
				for _, candidate in ipairs(addon.module.modules) do
					if candidate.id == "smart_island" then module = candidate end
				end
				for _, section in ipairs(addon.module.sections(module)) do
					if section.after then section.after({ AddInitializer = function(_, row) buttons[row.name] = row end }) end
				end
				check("session recap starts off", buttons["Session recap"] and buttons["Session recap"].click() == false and #addon.smart_island.view().notices == 0)
				addon.module.set("smart_island", "feed_recap", true)
				check("turning on the recap does not announce the baseline", #addon.smart_island.view().notices == 0)
				state.time = state.time + 1799
				tickers[1].callback()
				check("the recap waits thirty minutes", #addon.smart_island.view().notices == 0)
				state.time = state.time + 1
				tickers[1].callback()
				local recap = notice_key(addon, "session-recap")
				check("the half-hour recap expands a zero summary", recap and recap.interaction == "expand" and recap.text == "Session recap"
					and recap.detail:find("Quests completed: 0", 1, true) and recap.detail:find("XP gained: 0", 1, true)
					and recap.detail:find("Net money: 0c", 1, true) and recap.detail:find("Elapsed: 30 minutes", 1, true))
				state.xp = 600
				event("PLAYER_XP_UPDATE")
				state.level, state.xp, state.xp_max = 13, 10, 2000
				event("PLAYER_LEVEL_UP", 13)
				state.money = 22345
				event("PLAYER_MONEY")
				event("QUEST_TURNED_IN", 55)
				state.time = state.time + 1800
				tickers[1].callback()
				recap = notice_key(addon, "session-recap")
				check("the next recap keeps one row and records the gains", recap and recap.detail:find("Quests completed: 1", 1, true)
					and recap.detail:find("XP gained: 560", 1, true) and recap.detail:find("Net money: +1g", 1, true) and recap.money == nil)
				check("show recap publishes the current summary", buttons["Session recap"].click() == true and notice_key(addon, "session-recap") ~= nil)
			end
		end
		local function experience_ledger()
			local function open_world(setup)
				local addon, env, _, state = island_world()
				state.level, state.xp, state.xp_max = 10, 0, 1000
				state.guid, state.server, state.exhaustion = "Player-1-ABC", 1000800, nil
				env.GetServerTime = function() return state.server end
				env.UnitGUID = function() return state.guid end
				env.GetXPExhaustion = function() return state.exhaustion end
				env.GetMaxPlayerLevel = function() return 60 end
				env.COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience."
				env.COMBATLOG_XPGAIN_FIRSTPERSON_GROUP = "%s dies, you gain %d experience. (+%d group bonus)"
				env.COMBATLOG_XPGAIN_EXHAUSTION1 = "%s dies, you gain %d experience. (%s exp %s bonus)"
				env.COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED = "You gain %d experience."
				if setup then setup(state, env) end
				addon.module.set("smart_island", "enabled", true)
				return addon, env, state
			end
			local function joined(report)
				return table.concat(report.lines, "\n")
			end
			local addon, env, state = open_world()
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			local report = addon.island_experience.report()
			check("the first plain reading stores a baseline and adds 0",
				report.ready and report.hour.total == 0 and report.day.total == 0
				and env.EverlookDB.experience["Player-1-ABC"].baseline.xp == 0
				and joined(report):find("Hour  0", 1, true) and not joined(report):find("XP incomplete", 1, true))
			state.xp = 250
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			report = addon.island_experience.report()
			check("a same-level gain lands in the hour and the day",
				report.hour.total == 250 and report.day.total == 250 and report.hour.other == 250
				and report.hour.quest == 0 and report.hour.kill == 0
				and env.EverlookDB.experience["Player-1-ABC"].buckets["1000800"].total == 250)

			addon, env, state = open_world(function(state)
				state.xp, state.xp_max = 900, 1000
			end)
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			state.level, state.xp = 11, 10
			addon.island_experience.on_event("PLAYER_LEVEL_UP", 11)
			report = addon.island_experience.report()
			check("a one-level wrap counts the rest of the old bar and one level",
				report.day.total == 110 and report.day.levels == 1 and joined(report):find("Day  110   1 level", 1, true))

			addon, _, state = open_world(function(state)
				state.xp = 100
			end)
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			state.level, state.xp = 12, 0
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			report = addon.island_experience.report()
			check("a two-level jump marks the window incomplete and adds nothing",
				report.hour.total == 0 and report.hour.gap and joined(report):find("Hour  0   XP incomplete", 1, true))

			addon, _, state = open_world(function(state)
				state.xp = 100
			end)
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			state.xp = 40
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			report = addon.island_experience.report()
			check("a drop in experience marks the window incomplete and adds nothing",
				report.hour.total == 0 and report.hour.gap and joined(report):find("XP incomplete", 1, true))

			addon, _, state = open_world(function(state)
				state.level, state.xp, state.xp_max = 60, 0, 0
			end)
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			report = addon.island_experience.report()
			check("an empty bar at the level cap adds nothing and stays complete",
				report.hour.total == 0 and not report.hour.gap and not joined(report):find("XP incomplete", 1, true))

			addon, env, state = open_world(function(state)
				state.xp = 100
			end)
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			local hidden = secret_stat()
			env.issecretvalue = function(value) return rawequal(value, hidden) end
			state.xp = hidden
			local ok = pcall(function() addon.island_experience.on_event("PLAYER_XP_UPDATE") end)
			state.xp = 200
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			report = addon.island_experience.report()
			check("a secret bar waits, then counts the gain as unsorted",
				ok and report.hour.total == 100 and report.hour.unsorted == 100 and report.hour.split
				and joined(report):find("Unsorted 100   XP incomplete", 1, true))

			addon, _, state = open_world()
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			addon.island_experience.on_event("QUEST_TURNED_IN", 10, 1000, 0)
			state.xp = 1000
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			report = addon.island_experience.report()
			check("a quest amount followed by the same bar move is all quests",
				report.hour.total == 1000 and report.hour.quest == 1000 and report.hour.kill == 0
				and report.hour.other == 0 and not report.hour.split)

			addon, _, state = open_world()
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			state.xp = 1000
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			addon.island_experience.on_event("QUEST_TURNED_IN", 10, 1000, 0)
			report = addon.island_experience.report()
			check("a quest amount just after the bar move is all quests",
				report.hour.total == 1000 and report.hour.quest == 1000 and report.hour.other == 0)

			addon, _, state = open_world()
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			addon.island_experience.on_event("QUEST_TURNED_IN", 10, 5000, 0)
			state.xp = 1000
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			report = addon.island_experience.report()
			check("a quest amount larger than the bar does not raise the total",
				report.hour.total == 1000 and report.hour.quest == 1000 and report.hour.split)

			addon, _, state = open_world()
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			addon.island_experience.on_event("CHAT_MSG_COMBAT_XP_GAIN", "Wolf dies, you gain 44 experience.")
			state.xp = 44
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			report = addon.island_experience.report()
			check("a named kill line labels the bar move as kills",
				report.hour.total == 44 and report.hour.kill == 44 and report.hour.other == 0)
			addon.island_experience.on_event("CHAT_MSG_COMBAT_XP_GAIN", "Wolf dies, you gain 40 experience. (+10 group bonus)")
			state.xp = 84
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			check("the first number in a group kill line is the kill amount",
				addon.island_experience.report().hour.kill == 84)
			addon.island_experience.on_event("CHAT_MSG_COMBAT_XP_GAIN", "Wolf dies, you gain 44 experience. (22 exp Rested bonus)")
			state.xp = 128
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			check("a rested kill line keeps the gain and not the parenthetical",
				addon.island_experience.report().hour.kill == 128 and addon.island_experience.report().hour.total == 128)

			addon, _, state = open_world()
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			addon.island_experience.on_event("CHAT_MSG_COMBAT_XP_GAIN", "You gain 44 experience.")
			state.xp = 44
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			report = addon.island_experience.report()
			check("an unnamed experience line is not a kill",
				report.hour.kill == 0 and report.hour.other == 44 and report.hour.total == 44)

			addon, env, state = open_world()
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			hidden = secret_stat()
			env.issecretvalue = function(value) return rawequal(value, hidden) end
			ok = pcall(function() addon.island_experience.on_event("CHAT_MSG_COMBAT_XP_GAIN", hidden) end)
			state.xp = 44
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			report = addon.island_experience.report()
			check("a secret kill line leaves the bar move unsorted",
				ok and report.hour.total == 44 and report.hour.unsorted == 44 and report.hour.kill == 0 and report.hour.split)

			addon, env, state = open_world()
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			state.xp = 100
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			state.server = 1000800 + 7200
			report = addon.island_experience.report()
			check("a gain from two hours ago stays in the day and leaves the hour",
				report.hour.total == 0 and report.day.total == 100)
			state.server = 1000800 + 26 * 3600
			state.xp = 101
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			report = addon.island_experience.report()
			check("a gain older than 25 hours is dropped on the next commit",
				report.day.total == 1 and env.EverlookDB.experience["Player-1-ABC"].buckets["1000800"] == nil)

			addon, env, state = open_world()
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			state.xp = 250
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			-- A reload runs every file again into a new registry. Running only this
			-- one again leaves its extension registered once.
			local function reload_experience(world_env, world)
				local chunk = assert(loadfile(source("island_experience")))
				setfenv(chunk, world_env)
				local extend = world.module.extend
				world.module.extend = function() end
				chunk("Everlook_Island", world)
				world.module.extend = extend
			end
			reload_experience(env, addon)
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			check("loading the saved ledger does not count the baseline again",
				addon.island_experience.report().hour.total == 250)
			local again, again_env, again_state = open_world()
			again.island_experience.on_event("PLAYER_XP_UPDATE")
			again_state.xp = 250
			again.island_experience.on_event("PLAYER_XP_UPDATE")
			reload_experience(again_env, again)
			again_state.xp = 300
			again.island_experience.on_event("PLAYER_XP_UPDATE")
			report = again.island_experience.report()
			check("experience gained across a reload is unsorted",
				report.hour.total == 300 and report.hour.unsorted == 50 and report.hour.split)

			addon, env, state = open_world()
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			state.xp = 100
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			state.guid, state.xp = "Player-2-DEF", 0
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			state.xp = 50
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			check("a second character keeps a separate total",
				addon.island_experience.report().hour.total == 50
				and env.EverlookDB.experience["Player-2-DEF"].buckets["1000800"].total == 50)
			state.guid, state.xp = "Player-1-ABC", 100
			addon.island_experience.on_event("PLAYER_ENTERING_WORLD")
			check("returning to the first character restores that ledger",
				addon.island_experience.report().hour.total == 100
				and env.EverlookDB.experience["Player-1-ABC"].buckets["1000800"].total == 100)

			addon, env, state = open_world(function(state, env)
				local hidden_guid = secret_stat()
				env.issecretvalue = function(value) return rawequal(value, hidden_guid) end
				state.guid = hidden_guid
			end)
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			state.xp = 10
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			check("a secret character id keeps the hour in memory and writes nothing",
				addon.island_experience.report().hour.total == 10 and env.EverlookDB.experience == nil)

			addon, env, state = open_world()
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			state.xp = 80
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			addon.module.set("smart_island", "enabled", false)
			check("disabling Smart island leaves the saved ledger in place",
				addon.island_experience.report() == nil
				and env.EverlookDB.experience["Player-1-ABC"].buckets["1000800"].total == 80)

			addon, _, state = open_world()
			state.xp_max = 2000
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			state.xp = 1000
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			state.server = 1000800 + 59
			check("the pace line waits until a minute of gains",
				not joined(addon.island_experience.report()):find("to this level", 1, true))
			state.server = 1000800 + 60
			check("one minute of gains at this pace is about a minute",
				joined(addon.island_experience.report()):find("About a minute to this level", 1, true))
			state.server = 1000800 + 3600
			state.xp, state.xp_max = 3600, 6000
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			check("forty minutes of this pace stays in minutes",
				joined(addon.island_experience.report()):find("About 40 minutes to this level", 1, true))
			state.xp_max = 10800
			check("two hours of this pace is about two hours",
				joined(addon.island_experience.report()):find("About 2 hours to this level", 1, true))

			addon, _, state = open_world()
			addon.island_experience.on_event("PLAYER_XP_UPDATE")
			check("no exhaustion reads as not rested",
				joined(addon.island_experience.report()):find("Not rested", 1, true))
			state.exhaustion = 0
			check("zero exhaustion reads as not rested",
				joined(addon.island_experience.report()):find("Not rested", 1, true))
			state.xp_max, state.exhaustion = 10000, 14200
			check("rested leftover names one level and the remainder",
				joined(addon.island_experience.report()):find("Rested 1 level and 4,200", 1, true))
			state.exhaustion = 20000
			check("rested leftover names whole levels",
				joined(addon.island_experience.report()):find("Rested 2 levels", 1, true)
				and not joined(addon.island_experience.report()):find("and", 1, true))

			local ui, ui_env, ui_event, ui_state, _, _, ui_frames = island_world()
			ui_state.guid, ui_state.server = "Player-1-UI", 2000000
			ui_state.level, ui_state.xp, ui_state.xp_max = 12, 450, 1000
			ui_env.GetServerTime = function() return ui_state.server end
			ui_env.UnitGUID = function() return ui_state.guid end
			ui_env.GetXPExhaustion = function() return nil end
			ui_env.GetMaxPlayerLevel = function() return 60 end
			ui.module.set("smart_island", "enabled", true)
			ui_state.xp = 600
			ui_event("PLAYER_XP_UPDATE")
			local view = ui.smart_island.view()
			check("experience detail stays off the view until the option is on",
				view.experience == nil and view.mode == "closed" and view.level == 12
				and ui.island_experience.report().hour.total == 150)
			ui.module.set("smart_island", "feed_experience", true)
			view = ui.smart_island.view()
			local function hour_label()
				for _, object in ipairs(ui_frames) do
					for _, region in ipairs(object.regions or {}) do
						if region.text == "HOUR" and region.shown ~= false then return region end
					end
				end
			end
			local function money_chip()
				for _, object in ipairs(ui_frames) do
					for _, region in ipairs(object.regions or {}) do
						if region.text == "Money" and region.parent and region.parent.parent then
							return region.parent.parent
						end
					end
				end
			end
			check("the closed capsule stays a level chip while the hour is recorded",
				view.mode == "closed" and view.level == 12 and view.experience.hour.total == 150
				and (not hour_label() or hour_label().shown == false))
			ui_env.everlook_smart_island_key("down")
			local label, money = hour_label(), money_chip()
			check("the open island places the hour above money",
				label and label.shown ~= false and label.text == "HOUR"
				and money and money.point and label.point and label.point[5] > money.point[5])
			ui.module.set("smart_island", "size", 150)
			label, money = hour_label(), money_chip()
			check("a larger island keeps the hour above money",
				ui.smart_island.view().experience.hour.total == 150
				and label and label.shown ~= false and money and label.point and label.point[5] > money.point[5])
			ui.module.set("smart_island", "size", 100)
			local notices = #ui.smart_island.view().notices
			ui_event("QUEST_TURNED_IN", 9, 100, 0)
			ui_state.xp = 700
			ui_event("PLAYER_XP_UPDATE")
			view = ui.smart_island.view()
			check("a turned-in quest labels the next bar move on the open island",
				view.experience.hour.quest == 100 and view.experience.hour.total == 250
				and #view.notices == notices)
			ui.module.set("smart_island", "feed_experience", false)
			check("turning experience detail off hides the rows and keeps the hour",
				ui.smart_island.view().experience == nil and ui.island_experience.report().hour.total == 250)
		end
		experience_ledger()
		local function lifetime_tests()
			local function visible_marks(frames, text)
				local function shown_frame(frame)
					local current = frame
					while type(current) == "table" do
						if current.shown == false then return false end
						current = current.parent
					end
					return true
				end
				local count = 0
				for index = 1, #frames do
					for _, region in ipairs(frames[index].regions) do
						if region.text == text and region.shown ~= false and shown_frame(region.parent) then count = count + 1 end
					end
				end
				return count
			end
			do
				local addon, env, _, state, afters, _, frames = island_world()
				addon.module.set("smart_island", "enabled", true)
				local api = env.Everlook.island
				api.notify({ text = "Read me", duration = 4 })
				state.time = state.time + 1
				env.everlook_smart_island_key("down")
				state.time = state.time + 0.5
				env.everlook_smart_island_key("up")
				check("closing the island resumes the remaining lifetime", addon.smart_island.view().mode == "closed" and #addon.smart_island.view().notices == 1 and afters[#afters].delay == 3)
				fire_after(afters, 3)
				finish_animations(frames)
				check("the resumed clock removes the card and the row together", #addon.smart_island.view().toasts == 0 and #addon.smart_island.view().notices == 0)
			end
			do
				local addon, env, _, _, afters, _, frames = island_world()
				addon.module.set("smart_island", "enabled", true)
				local api = env.Everlook.island
				local first = api.notify({ source = "Coins", stack = "gain", text = "Money received", money = 100, duration = 4 })
				local restarted = #afters
				local second = api.notify({ source = "Coins", stack = "gain", text = "Money received", money = 250, duration = 4 })
				local view = addon.smart_island.view()
				local counted
				for _, frame in ipairs(frames) do
					for _, region in ipairs(frame.regions) do
						if region.text == "Money received ×2" then counted = true end
					end
				end
				check("the same source and stack join one notice", second == first and #view.notices == 1 and view.notices[1].count == 2 and view.notices[1].money == 350 and view.notices[1].text == "Money received" and counted)
				check("a timed stack restarts its full lifetime", #afters == restarted + 1 and afters[#afters].delay == 4)
				fire_after(afters, 4)
				check("the earlier stack timeout cannot remove the joined notice", #addon.smart_island.view().notices == 1 and #addon.smart_island.view().toasts == 1)
				local other = api.notify({ source = "Other", stack = "gain", text = "Other coins", money = 10 })
				check("a different source stays its own notice", other ~= first and #addon.smart_island.view().notices == 2)
				local keyed = api.notify({ source = "Work", key = "job", stack = "gain", text = "Job", money = 20 })
				local updated = api.notify({ source = "Work", key = "job", stack = "gain", text = "Job done", money = 5 })
				local job
				for _, notice in ipairs(addon.smart_island.view().notices) do
					if notice.id == keyed then job = notice end
				end
				check("a matching key updates that notice without adding a count", updated == keyed and job.text == "Job done" and job.money == 5 and job.count == 1)
				local huge = api.notify({ source = "Vault", stack = "gain", text = "Money received", money = 9007199254740991 })
				local rejected, reason = api.notify({ source = "Vault", stack = "gain", text = "Money received", money = 1 })
				local vault
				for _, notice in ipairs(addon.smart_island.view().notices) do
					if notice.id == huge then vault = notice end
				end
				check("stacked money past the display bound is rejected", rejected == nil and reason == "invalid_money" and vault.money == 9007199254740991 and vault.count == 1)
			end
			do
				local addon, env, _, _, afters, _, frames = island_world()
				addon.module.set("smart_island", "enabled", true)
				local api = env.Everlook.island
				api.notify({ text = "Ordinary news", duration = 4 })
				check("a timed row has no close mark", visible_marks(frames, "×") == 0)
				fire_after(afters, 4)
				finish_animations(frames)
				local handle = api.notify({ source = "Bags", text = "The bags are full", persist = true, severity = "warning", duration = 4,
					actions = { { id = "pin", label = "Pin", type = "callback", on_click = function() end } } })
				check("a persistent notice has no close mark", handle and visible_marks(frames, "×") == 0 and addon.smart_island.view().notices[1].persist == true)
				local dismissed = false
				for index = 1, #frames do
					local handler = frames[index].scripts and frames[index].scripts.OnMouseUp
					if not dismissed and handler and frames[index].shown ~= false and frames[index].mouse then
						handler(frames[index], "RightButton")
						dismissed = #addon.smart_island.view().notices == 0
					end
				end
				check("right-click dismisses a notice", dismissed)
				local staying = api.notify({ source = "Bags", key = "later", text = "Still full", persist = true, duration = 4 })
				while fire_after(afters, 4) do end
				finish_animations(frames)
				check("the read clock removes the card and leaves the row", staying and #addon.smart_island.view().notices == 1 and #addon.smart_island.view().toasts == 0)
				check("dismissing a persistent notice removes its row", api.dismiss(staying) and #addon.smart_island.view().notices == 0)
			end
			do
				local addon, env, _, _, afters, _, frames = island_world()
				addon.module.set("smart_island", "enabled", true)
				local api = env.Everlook.island
				api.notify({ text = "Stay one", persist = true })
				api.notify({ text = "Stay two", persist = true })
				api.notify({ text = "Stay three", persist = true })
				local waiting = api.notify({ text = "Waiting", duration = 4 })
				local view = addon.smart_island.view()
				check("a timed notice can wait behind persistent cards", #view.toasts == 3 and #view.queue == 1 and view.queue[1].id == waiting)
				api.notify({ text = "Broken axle", severity = "error" })
				local exiting = false
				for _, toast in ipairs(addon.smart_island.view().toasts) do
					if toast.phase == "exiting" then exiting = true end
				end
				check("an error leaves a persistent card in place", not exiting and #addon.smart_island.view().toasts == 3)
				while fire_after(afters, 4) do end
				finish_animations(frames)
				view = addon.smart_island.view()
				check("the read clock clears persistent cards and the waiting row", #view.notices == 3 and #view.queue == 0 and #view.toasts == 0)
			end
		end
		lifetime_tests()
		feed_tests()
		later_feed_tests()
	end
	island_action_tests()
	assert(loadfile(root .. "/tests/island_seam.lua"))()(root, check, island_world, quest_world, secret_stat)
	assert(loadfile(root .. "/tests/island_share.lua"))()(root, check, load_qol)

end
