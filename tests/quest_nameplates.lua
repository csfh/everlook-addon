-- The quest mark beside a nameplate: whom it marks, where it goes, that the name is left-aligned beside it and put
-- back, and that it all comes and goes with the plate.
return function(root, check, island_world)
	local addon, env, event = island_world()
	local function texture()
		local mark = { points = {}, shown = false }
		function mark:SetAtlas(atlas) self.atlas, self.path = atlas, nil end
		function mark:SetTexture(path) self.path, self.atlas = path, nil end
		function mark:SetSize(width, height) self.width, self.height = width, height end
		function mark:SetWidth(width) self.width, self.height = width, nil end
		function mark:ClearAllPoints() self.points = {} end
		function mark:SetPoint(...) self.points[#self.points + 1] = { ... } end
		function mark:Show() self.shown = true end
		function mark:Hide() self.shown = false end
		return mark
	end
	local plates, made = {}, {}
	for _, unit in ipairs({ "nameplate1", "nameplate2", "nameplate3", "nameplate4" }) do
		local name = { label = "name", justify = "CENTER" }
		function name:GetJustifyH() return self.justify end
		function name:SetJustifyH(value) self.justify = value end
		local bar = { label = "bar" }
		local created = {}
		made[unit] = created
		plates[unit] = { namePlateUnitToken = unit, UnitFrame = { name = name, HealthBarsContainer = bar,
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
	local function frame_of(unit) return plates[unit].UnitFrame end

	addon.module.set("quest_nameplates", "enabled", true)
	event("NAME_PLATE_UNIT_ADDED", "nameplate1")
	local mark = made.nameplate1[1]
	check("a unit that is part of a quest you are on gets a mark", mark and mark.shown)
	check("by default it spans both rows: from the top of the name to the bottom of the health bar, left of them",
		#mark.points == 2 and mark.points[1][1] == "TOPRIGHT" and mark.points[1][2] == frame_of("nameplate1").name and mark.points[1][3] == "TOPLEFT"
		and mark.points[2][1] == "BOTTOMRIGHT" and mark.points[2][2] == frame_of("nameplate1").HealthBarsContainer and mark.points[2][3] == "BOTTOMLEFT")
	check("it is the width the setting says, 26, and takes its height from the two rows", mark.width == 26 and mark.height == nil)
	check("it is the quest boss badge's atlas or, without it, the badge's file", mark.path == "Interface\\TargetingFrame\\PortraitQuestBadge")
	check("the name is left-aligned beside it", frame_of("nameplate1").name.justify == "LEFT")
	event("NAME_PLATE_UNIT_ADDED", "nameplate2")
	check("a player gets none, quest or not, and keeps its name where it was", #made.nameplate2 == 0 and frame_of("nameplate2").name.justify == "CENTER")
	event("NAME_PLATE_UNIT_ADDED", "nameplate3")
	check("a quest boss gets one", made.nameplate3[1] and made.nameplate3[1].shown)
	event("NAME_PLATE_UNIT_ADDED", "nameplate4")
	check("a unit that is not part of a quest gets none, and its name stays centred", #made.nameplate4 == 0 and frame_of("nameplate4").name.justify == "CENTER")

	addon.module.set("quest_nameplates", "layout", "name_right")
	check("the place can be the right of the name, square", #mark.points == 1 and mark.points[1][1] == "LEFT" and mark.points[1][2] == frame_of("nameplate1").name and mark.points[1][3] == "RIGHT" and mark.width == 26 and mark.height == 26)
	addon.module.set("quest_nameplates", "layout", "bar_left")
	check("or the left of the health bar", mark.points[1][1] == "RIGHT" and mark.points[1][2] == frame_of("nameplate1").HealthBarsContainer and mark.points[1][3] == "LEFT")
	addon.module.set("quest_nameplates", "layout", "name_left")
	check("or the left of the name", mark.points[1][1] == "RIGHT" and mark.points[1][2] == frame_of("nameplate1").name and mark.points[1][3] == "LEFT")
	addon.module.set("quest_nameplates", "layout", "rows")
	addon.module.set("quest_nameplates", "width", 34)
	check("a wider mark is applied at once, and the two rows are back", mark.width == 34 and #mark.points == 2)

	addon.module.set("quest_nameplates", "align_name", false)
	check("with left-aligning off the name goes back to how the game had it", frame_of("nameplate1").name.justify == "CENTER")
	addon.module.set("quest_nameplates", "align_name", true)
	check("and on, it is left again", frame_of("nameplate1").name.justify == "LEFT")

	event("NAME_PLATE_UNIT_REMOVED", "nameplate1")
	check("the mark goes when the plate does", mark.shown == false)
	check("and the plate gets its centred name back, for the next unit it is given", frame_of("nameplate1").name.justify == "CENTER")
	event("NAME_PLATE_UNIT_ADDED", "nameplate1")
	check("the same mark comes back with it, and the name is left again", #made.nameplate1 == 1 and mark.shown == true and frame_of("nameplate1").name.justify == "LEFT")

	related.nameplate4 = true
	event("QUEST_LOG_UPDATE")
	check("a change to your quests marks a unit that has become part of one", made.nameplate4[1] and made.nameplate4[1].shown and frame_of("nameplate4").name.justify == "LEFT")
	related.nameplate4 = false
	event("QUEST_LOG_UPDATE")
	check("and clears one that no longer is, with its name back", made.nameplate4[1].shown == false and frame_of("nameplate4").name.justify == "CENTER")

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
	check("turning the module off takes every mark down and every name back", mark.shown == false and frame_of("nameplate1").name.justify == "CENTER" and made.nameplate3[1].shown == false)
end
