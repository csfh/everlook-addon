return function(_, check, load_qol)
	local function arm(env)
		env.LE_PARTY_CATEGORY_HOME = 1
		env.LE_PARTY_CATEGORY_INSTANCE = 2
		env.WorldFrame = {}
		env.GetTime = function() return 100 end
		env.GetCurrentKeyBoardFocus = function() end
		env.GetNormalizedRealmName = function() return "Realm" end
		env.UnitFullName = function(unit)
			if unit == "player" then return "Mira", "Realm" end
		end
		env.UnitExists = function() return false end
		env.UnitIsUnit = function() return false end
		env.UnitName = function() end
		env.IsInGroup = function(category)
			return category == nil or category == env.LE_PARTY_CATEGORY_HOME
		end
		env.GetMouseFoci = function() return {} end
		env.GameTooltipTextLeft1 = { GetText = function() end }
		env.GameTooltip = {
			IsShown = function() return false end,
			GetItem = function() end,
			GetSpell = function() end,
		}
		env.C_QuestLog = { GetTitleForQuestID = function() end }
		env.said, env.sent = {}, {}
		env.C_ChatInfo = {
			SendChatMessage = function(message, chat_type)
				env.said[#env.said + 1] = { message = message, chat_type = chat_type }
			end,
			SendAddonMessage = function(prefix, message, chat_type)
				env.sent[#env.sent + 1] = { prefix = prefix, message = message, chat_type = chat_type }
			end,
			RegisterAddonMessagePrefix = function() end,
		}
	end

	local function ready()
		local addon, env, event = load_qol()
		arm(env)
		addon.module.set("smart_island", "enabled", true)
		return addon, env, event
	end

	local function latest(addon)
		local notices = addon.smart_island.view().notices
		return notices[#notices]
	end

	local function point_at_unit(env, name)
		env.UnitExists = function(unit) return unit == "mouseover" end
		env.UnitName = function(unit)
			if unit == "mouseover" then return name end
		end
	end

	local addon, env, event = ready()
	check("sharing an alt-right-click starts on", addon.module.get("smart_island", "share_click") == true)

	point_at_unit(env, "Hogger")
	env.everlook_share_click()
	local row = latest(addon)
	check("a unit is said, shown, and sent to the party",
		row and row.text == "Hogger" and row.kind == "info" and row.source == "everlook" and row.key == "share:self"
		and #env.said == 1 and env.said[1].message == "Hogger" and env.said[1].chat_type == "SAY"
		and #env.sent == 1 and env.sent[1].prefix == "Everlook" and env.sent[1].chat_type == "PARTY"
		and env.sent[1].message == "1\tunit\tHogger")

	addon, env = ready()
	local link = "|cff1eff00|Hitem:118:::::::::|h[Minor Healing Potion]|h|r"
	env.GameTooltip.GetItem = function() return "Minor Healing Potion", link end
	env.everlook_share_click()
	row = latest(addon)
	check("an item says its link and the island keeps the plain name",
		row and row.text == "Minor Healing Potion" and row.kind == "loot" and row.item_id == 118
		and env.said[1].message == link and env.sent[1].message == "1\titem\tMinor Healing Potion\t118")

	addon, env = ready()
	env.GameTooltip.GetItem = function()
		return "Potion", "|Hitem:118|h[Potion]|h|Hspell:133|h[Fireball]|h"
	end
	env.everlook_share_click()
	check("a link that is not only an item is said as a name",
		env.said[1] and env.said[1].message == "Potion" and latest(addon).text == "Potion")

	addon, env = ready()
	local quest_row = { questID = 42 }
	env.GetMouseFoci = function() return { quest_row } end
	env.C_QuestLog.GetTitleForQuestID = function(id)
		if id == 42 then return "The People's Militia" end
	end
	env.everlook_share_click()
	row = latest(addon)
	check("a quest under the cursor is said and marked as a quest",
		row and row.text == "The People's Militia" and row.kind == "quest"
		and env.said[1].message == "The People's Militia"
		and env.sent[1].message == "1\tquest\tThe People's Militia")

	addon, env = ready()
	env.GameTooltip.GetSpell = function() return "Fireball", 133 end
	env.everlook_share_click()
	row = latest(addon)
	check("a spell is said and keeps its spell id",
		row and row.text == "Fireball" and row.kind == "info" and row.spell_id == 133
		and env.said[1].message == "Fireball" and env.sent[1].message == "1\tspell\tFireball\t133")

	addon, env = ready()
	env.GameTooltip.IsShown = function() return true end
	env.GameTooltipTextLeft1.GetText = function() return "Copper Vein" end
	env.everlook_share_click()
	row = latest(addon)
	check("a world tooltip names the object",
		row and row.text == "Copper Vein" and row.kind == "info"
		and env.said[1].message == "Copper Vein" and env.sent[1].message == "1\tobject\tCopper Vein")

	addon, env = ready()
	env.GetMouseFoci = function() return { {} } end
	env.GameTooltip.IsShown = function() return true end
	env.GameTooltipTextLeft1.GetText = function() return "Settings" end
	env.everlook_share_click()
	check("an interface tooltip title stays quiet", #env.said == 0 and #env.sent == 0 and #addon.smart_island.view().notices == 0)

	addon, env = ready()
	env.issecretvalue = function(value) return value == "secret" end
	env.UnitExists = function() return true end
	env.UnitName = function() return "secret" end
	env.everlook_share_click()
	check("a secret name stays quiet", #env.said == 0 and #env.sent == 0 and #addon.smart_island.view().notices == 0)

	addon, env = ready()
	env.UnitExists = function(unit) return unit == "mouseover" end
	env.UnitIsUnit = function(unit, other) return unit == "mouseover" and other == "player" end
	env.UnitName = function() return "Mira" end
	env.everlook_share_click()
	check("clicking yourself stays quiet", #env.said == 0 and #env.sent == 0 and #addon.smart_island.view().notices == 0)

	addon, env = ready()
	env.everlook_share_click()
	check("empty ground stays quiet", #env.said == 0 and #env.sent == 0 and #addon.smart_island.view().notices == 0)

	addon, env = ready()
	point_at_unit(env, "Hogger")
	env.GetCurrentKeyBoardFocus = function() return {} end
	env.everlook_share_click()
	check("a keyboard focus stays quiet", #env.said == 0 and #env.sent == 0 and #addon.smart_island.view().notices == 0)

	addon, env = ready()
	addon.module.set("smart_island", "share_click", false)
	point_at_unit(env, "Hogger")
	env.everlook_share_click()
	check("turning sharing off stays quiet", #env.said == 0 and #env.sent == 0 and #addon.smart_island.view().notices == 0)

	addon, env, event = ready()
	addon.module.set("smart_island", "enabled", false)
	point_at_unit(env, "Hogger")
	env.everlook_share_click()
	event("CHAT_MSG_ADDON", "Everlook", "1\tunit\tHogger", "PARTY", "Kor-Realm")
	check("a disabled island shares and receives nothing", #env.said == 0 and #env.sent == 0 and #addon.smart_island.view().notices == 0)

	addon, env = ready()
	point_at_unit(env, "Hogger")
	env.IsInGroup = function() return false end
	env.everlook_share_click()
	check("outside a group the name is still said and shown",
		#env.sent == 0 and env.said[1] and env.said[1].message == "Hogger" and latest(addon) and latest(addon).text == "Hogger")

	addon, env = ready()
	point_at_unit(env, "Hogger")
	env.IsInGroup = function(category) return category == env.LE_PARTY_CATEGORY_INSTANCE end
	env.everlook_share_click()
	check("an instance group uses the instance channel", env.sent[1] and env.sent[1].chat_type == "INSTANCE_CHAT")

	addon, env = ready()
	point_at_unit(env, "Hogger")
	local now = 100
	env.GetTime = function() return now end
	env.everlook_share_click()
	env.everlook_share_click()
	check("the same subject is ignored inside the repeat window", #env.said == 1 and #env.sent == 1)
	now = 100.5
	env.everlook_share_click()
	check("the same subject can be shared again after the window", #env.said == 2 and #env.sent == 2)

	addon, env = ready()
	point_at_unit(env, "Hogger")
	env.C_ChatInfo.SendChatMessage = nil
	env.SendChatMessage = function(message, chat_type)
		env.said[#env.said + 1] = { message = message, chat_type = chat_type }
	end
	env.everlook_share_click()
	check("say uses the older chat call when the namespaced one is missing",
		env.said[1] and env.said[1].message == "Hogger" and env.said[1].chat_type == "SAY" and #env.sent == 1)

	addon, env = ready()
	point_at_unit(env, "Hogger")
	env.C_ChatInfo.SendChatMessage = function() error("chat down") end
	env.everlook_share_click()
	check("a chat failure still shows the notice and tells the party",
		latest(addon) and latest(addon).text == "Hogger" and env.sent[1] and env.sent[1].message == "1\tunit\tHogger")

	addon, env, event = ready()
	event("CHAT_MSG_ADDON", "Everlook", "1\tunit\tHogger", "PARTY", "Kor")
	row = latest(addon)
	check("a party message becomes a notice from that player",
		row and row.text == "Kor: Hogger" and row.source == "everlook" and row.key == "share:Kor" and row.kind == "info")

	addon, env, event = ready()
	event("CHAT_MSG_ADDON", "Everlook", "1\titem\tMinor Healing Potion\t118", "PARTY", "Kor-Realm")
	row = latest(addon)
	check("a party item keeps the icon and drops your own realm",
		row and row.text == "Kor: Minor Healing Potion" and row.kind == "loot" and row.item_id == 118)

	addon, env, event = ready()
	event("CHAT_MSG_ADDON", "Everlook", "1\tunit\tHogger", "PARTY", "Mira-Realm")
	event("CHAT_MSG_ADDON", "Other", "1\tunit\tHogger", "PARTY", "Kor")
	event("CHAT_MSG_ADDON", "Everlook", "1\tunit\t|cff000000Hogger", "PARTY", "Kor")
	event("CHAT_MSG_ADDON", "Everlook", "1\tmount\tHogger", "PARTY", "Kor")
	event("CHAT_MSG_ADDON", "Everlook", "1\tunit\t", "PARTY", "Kor")
	check("your own message and a malformed party message stay quiet", #addon.smart_island.view().notices == 0)

	addon, env, event = ready()
	addon.module.set("smart_island", "share_click", false)
	event("CHAT_MSG_ADDON", "Everlook", "1\tunit\tHogger", "PARTY", "Kor")
	check("turning sharing off still shows a party notice", latest(addon) and latest(addon).text == "Kor: Hogger")
end
