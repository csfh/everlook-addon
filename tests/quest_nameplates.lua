-- The quest mark beside a nameplate: whom it marks, where it goes, and that it comes and goes with the plate.
return function(root, check, island_world)
	local addon, env, event = island_world()
	local function texture()
		local mark = { points = {}, shown = false }
		function mark:SetAtlas(atlas) self.atlas, self.path = atlas, nil end
		function mark:SetTexture(path) self.path, self.atlas = path, nil end
		function mark:SetSize(width, height) self.width, self.height = width, height end
		function mark:ClearAllPoints() self.points = {} end
		function mark:SetPoint(...) self.points[#self.points + 1] = { ... } end
		function mark:Show() self.shown = true end
		function mark:Hide() self.shown = false end
		return mark
	end
	local plates, made = {}, {}
	for _, unit in ipairs({ "nameplate1", "nameplate2", "nameplate3", "nameplate4" }) do
		local name, bar = { label = "name" }, { label = "bar" }
		local created = {}
		made[unit] = created
		plates[unit] = { namePlateUnitToken = unit, UnitFrame = { name = name, healthBar = bar,
			CreateTexture = function() local mark = texture(); created[#created + 1] = mark; return mark end } }
	end
	local related = { nameplate1 = true, nameplate2 = true, nameplate4 = false }
	env.C_NamePlate = { GetNamePlateForUnit = function(unit) return plates[unit] end,
		GetNamePlates = function() return { plates.nameplate1, plates.nameplate2, plates.nameplate3, plates.nameplate4 } end }
	env.UnitExists = function() return true end
	env.UnitIsPlayer = function(unit) return unit == "nameplate2" end
	env.C_QuestLog = env.C_QuestLog or {}
	env.C_QuestLog.UnitIsRelatedToActiveQuest = function(unit) return related[unit] == true end
	env.UnitIsQuestBoss = function(unit) return unit == "nameplate3" end

	addon.module.set("quest_nameplates", "enabled", true)
	event("NAME_PLATE_UNIT_ADDED", "nameplate1")
	local mark = made.nameplate1[1]
	check("a unit that is part of a quest you are on gets a mark", mark and mark.shown)
	check("it goes to the left of the name by default, a little off it", mark.points[1][1] == "RIGHT" and mark.points[1][2] == plates.nameplate1.UnitFrame.name and mark.points[1][3] == "LEFT" and mark.points[1][4] == -2)
	check("it is the size the setting says, and the quest boss badge's atlas or, without it, the badge's file", mark.width == 16 and mark.height == 16 and mark.path == "Interface\\TargetingFrame\\PortraitQuestBadge")
	event("NAME_PLATE_UNIT_ADDED", "nameplate2")
	check("a player gets none, quest or not", #made.nameplate2 == 0)
	event("NAME_PLATE_UNIT_ADDED", "nameplate3")
	check("a quest boss gets one", made.nameplate3[1] and made.nameplate3[1].shown)
	event("NAME_PLATE_UNIT_ADDED", "nameplate4")
	check("a unit that is not part of a quest gets none", #made.nameplate4 == 0)

	addon.module.set("quest_nameplates", "place", "name_right")
	check("the place can be the right of the name", mark.points[1][1] == "LEFT" and mark.points[1][2] == plates.nameplate1.UnitFrame.name and mark.points[1][3] == "RIGHT" and mark.points[1][4] == 2)
	addon.module.set("quest_nameplates", "place", "bar_left")
	check("or the left of the health bar", mark.points[1][1] == "RIGHT" and mark.points[1][2] == plates.nameplate1.UnitFrame.healthBar and mark.points[1][3] == "LEFT")
	addon.module.set("quest_nameplates", "size", 24)
	check("a larger mark is applied at once", mark.width == 24 and mark.height == 24)

	event("NAME_PLATE_UNIT_REMOVED", "nameplate1")
	check("the mark goes when the plate does", mark.shown == false)
	event("NAME_PLATE_UNIT_ADDED", "nameplate1")
	check("and the same mark comes back with it", #made.nameplate1 == 1 and mark.shown == true)

	related.nameplate4 = true
	event("QUEST_LOG_UPDATE")
	check("a change to your quests marks a unit that has become part of one", made.nameplate4[1] and made.nameplate4[1].shown)
	related.nameplate4 = false
	event("QUEST_LOG_UPDATE")
	check("and clears one that no longer is", made.nameplate4[1].shown == false)

	local secret = {}
	env.issecretvalue = function(value) return rawequal(value, secret) end
	env.C_QuestLog.UnitIsRelatedToActiveQuest = function() return secret end
	env.UnitIsQuestBoss = function() return secret end
	event("QUEST_LOG_UPDATE")
	check("a value the game keeps secret marks nothing, and does not fail", mark.shown == false)
	env.issecretvalue = nil

	env.C_QuestLog.UnitIsRelatedToActiveQuest = function(unit) return related[unit] == true end
	env.UnitIsQuestBoss = function() return false end
	event("QUEST_LOG_UPDATE")
	addon.module.set("quest_nameplates", "enabled", false)
	check("turning the module off takes every mark down", mark.shown == false and made.nameplate3[1].shown == false)
end
