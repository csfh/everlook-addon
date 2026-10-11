-- The quest mark beside a nameplate: whom it marks, where it goes, that the name is left-aligned beside it and put
-- back, and that it all comes and goes with the plate.
return function(root, check, island_world)
	local addon, env, event, _, afters = island_world()
	-- A burst of quest log events is looked at once, a moment after the last.
	local function settle()
		for _, after in ipairs(afters) do
			if after.delay == 0.25 and not after.done then after.done = true; after.callback() end
		end
	end
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
		-- The game's own accessor gives the unit; the field the token is kept in has differed between clients.
		plates[unit] = { GetUnit = function() return unit end, UnitFrame = { name = name, HealthBarsContainer = bar,
			CreateTexture = function() local mark = texture(); created[#created + 1] = mark; return mark end } }
	end
	local related = { nameplate1 = true, nameplate2 = true, nameplate4 = false }
	env.C_NamePlate = { GetNamePlateForUnit = function(unit) return plates[unit] end,
		GetNamePlates = function() return { plates.nameplate1, plates.nameplate2, plates.nameplate3, plates.nameplate4 } end }
	env.UnitExists = function() return true end
	env.UnitCanAttack = function() return false end
	env.UnitIsUnit = function() return false end
	env.UnitIsPlayer = function(unit) return unit == "nameplate2" end
	env.C_QuestLog = env.C_QuestLog or {}
	env.C_QuestLog.UnitIsRelatedToActiveQuest = function(unit) return related[unit] == true end
	env.UnitIsQuestBoss = function(unit) return unit == "nameplate3" end
	local function frame_of(unit) return plates[unit].UnitFrame end

	addon.module.set("nameplates", "enabled", true)
	addon.module.set("quest_nameplates", "enabled", true)
	settle()
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
	check("a player gets no mark, quest or not, and its name is left-aligned like every other", #made.nameplate2 == 0 and frame_of("nameplate2").name.justify == "LEFT")
	event("NAME_PLATE_UNIT_ADDED", "nameplate3")
	check("a quest boss gets one", made.nameplate3[1] and made.nameplate3[1].shown)
	event("NAME_PLATE_UNIT_ADDED", "nameplate4")
	check("a unit that is not part of a quest gets no mark, and its name is left-aligned too", #made.nameplate4 == 0 and frame_of("nameplate4").name.justify == "LEFT")

	addon.module.set("nameplates", "layout", "name_right")
	check("the place can be the right of the name, square", #mark.points == 1 and mark.points[1][1] == "LEFT" and mark.points[1][2] == frame_of("nameplate1").name and mark.points[1][3] == "RIGHT" and mark.width == 26 and mark.height == 26)
	addon.module.set("nameplates", "layout", "bar_left")
	check("or the left of the health bar", mark.points[1][1] == "RIGHT" and mark.points[1][2] == frame_of("nameplate1").HealthBarsContainer and mark.points[1][3] == "LEFT")
	addon.module.set("nameplates", "layout", "name_left")
	check("or the left of the name", mark.points[1][1] == "RIGHT" and mark.points[1][2] == frame_of("nameplate1").name and mark.points[1][3] == "LEFT")
	addon.module.set("nameplates", "layout", "rows")
	addon.module.set("nameplates", "width", 34)
	check("a wider mark is applied at once, and the two rows are back", mark.width == 34 and #mark.points == 2)

	addon.module.set("nameplates", "align_name", false)
	check("with left-aligning off every name goes back to how the game had it", frame_of("nameplate1").name.justify == "CENTER" and frame_of("nameplate2").name.justify == "CENTER" and frame_of("nameplate4").name.justify == "CENTER")
	addon.module.set("nameplates", "align_name", true)
	check("and on, they are left again", frame_of("nameplate1").name.justify == "LEFT" and frame_of("nameplate2").name.justify == "LEFT")

	event("NAME_PLATE_UNIT_REMOVED", "nameplate1")
	check("the mark goes when the plate does", mark.shown == false)
	check("and the plate gets its centred name back, for the next unit it is given", frame_of("nameplate1").name.justify == "CENTER")
	event("NAME_PLATE_UNIT_ADDED", "nameplate1")
	check("the same mark comes back with it, and the name is left again", #made.nameplate1 == 1 and mark.shown == true and frame_of("nameplate1").name.justify == "LEFT")

	related.nameplate4 = true
	event("QUEST_LOG_UPDATE")
	event("QUEST_LOG_UPDATE")
	local waiting = 0
	for _, after in ipairs(afters) do if after.delay == 0.25 and not after.done then waiting = waiting + 1 end end
	check("two quest log updates in a burst wait for one look, not two", waiting == 1)
	settle()
	check("a change to your quests marks a unit that has become part of one", made.nameplate4[1] and made.nameplate4[1].shown and frame_of("nameplate4").name.justify == "LEFT")
	related.nameplate4 = false
	event("QUEST_LOG_UPDATE")
	settle()
	check("and clears one that no longer is, its name staying left like the rest", made.nameplate4[1].shown == false and frame_of("nameplate4").name.justify == "LEFT")

	local secret = {}
	env.issecretvalue = function(value) return rawequal(value, secret) end
	env.C_QuestLog.UnitIsRelatedToActiveQuest = function() return secret end
	env.UnitIsQuestBoss = function() return secret end
	event("QUEST_LOG_UPDATE")
	settle()
	check("a value the game keeps secret marks nothing, and does not fail", mark.shown == false)
	env.issecretvalue = nil

	env.C_QuestLog.UnitIsRelatedToActiveQuest = function(unit) return related[unit] == true end
	env.UnitIsQuestBoss = function() return false end
	event("QUEST_LOG_UPDATE")
	settle()

	-- A creature to kill or loot: the game's own answer says nothing, and its tooltip lists the quest and an objective.
	local lines = {}
	env.C_TooltipInfo = { GetUnit = function(unit) return lines[unit] end }
	lines.nameplate4 = { lines = { { type = 2, leftText = "Defias Bandit" }, { type = 17, leftText = "Collecting Memories" }, { type = 8, leftText = "Bandits slain: 3/8" } } }
	event("NAME_PLATE_UNIT_ADDED", "nameplate4")
	check("a creature whose tooltip lists a quest of yours is marked, though the game says nothing of it", made.nameplate4[1].shown == true and frame_of("nameplate4").name.justify == "LEFT")
	lines.nameplate4 = { lines = { { type = 2, leftText = "Defias Bandit" }, { type = 7, leftText = "Threat" } } }
	event("NAME_PLATE_UNIT_ADDED", "nameplate4")
	check("one whose tooltip has no quest line is not", made.nameplate4[1].shown == false)
	lines.nameplate4 = { lines = { { type = 8, leftText = secret } } }
	env.issecretvalue = function(value) return rawequal(value, secret) end
	event("NAME_PLATE_UNIT_ADDED", "nameplate4")
	check("a tooltip the game keeps secret is read without failing", made.nameplate4[1].shown == true)
	lines.nameplate4 = { lines = { { type = secret } } }
	event("NAME_PLATE_UNIT_ADDED", "nameplate4")
	check("and a secret kind of line is skipped", made.nameplate4[1].shown == false)
	env.issecretvalue = nil
	env.C_TooltipInfo = nil
	event("NAME_PLATE_UNIT_ADDED", "nameplate4")
	check("with no tooltip to read, only the game's own answer is used", made.nameplate4[1].shown == false)

	-- A hostile creature stops being marked when its objective is done, though the quest is still in your log.
	env.UnitCanAttack = function(_, unit) return unit == "nameplate4" end
	related.nameplate4 = true
	local function objective(text, extra)
		local row = { type = 8, leftText = text }
		for key, value in pairs(extra or {}) do row[key] = value end
		return { lines = { { type = 2, leftText = "Defias Bandit" }, { type = 17, leftText = "Collecting Memories" }, row } }
	end
	local function marked_hostile()
		event("NAME_PLATE_UNIT_ADDED", "nameplate4")
		return made.nameplate4[1].shown == true
	end
	env.C_TooltipInfo = { GetUnit = function(unit) return lines[unit] end }
	lines.nameplate4 = objective("Bandits slain: 3/8")
	check("a hostile creature with an objective still open is marked", marked_hostile())
	lines.nameplate4 = objective("Bandits slain: 8/8")
	check("and not when that objective is done, though the game still ties it to the quest", marked_hostile() == false)
	lines.nameplate4 = objective("Bandits slain", { completed = true })
	check("a line the game says is completed is done", marked_hostile() == false)
	lines.nameplate4 = objective("Wolf pelts: 40%")
	check("a percentage that is not full is open", marked_hostile())
	lines.nameplate4 = objective("Wolf pelts: 100%")
	check("and a full one is done", marked_hostile() == false)
	lines.nameplate4 = { lines = { { type = 17, leftText = "Collecting Memories" } } }
	check("a quest title with no objective under it is done", marked_hostile() == false)
	lines.nameplate4 = objective("Do something")
	check("an objective line that says nothing about progress is taken as open", marked_hostile())
	env.C_TooltipInfo = nil
	check("with no tooltip to read, the game's own answer is used for a hostile creature", marked_hostile())
	env.C_TooltipInfo = { GetUnit = function(unit) return lines[unit] end }
	-- Someone you cannot attack is still marked by the game's answer: a quest giver or a hand-in has no objective line.
	env.UnitCanAttack = function() return false end
	lines.nameplate4 = { lines = { { type = 2, leftText = "Brother Paxton" } } }
	check("a friendly unit the game ties to a quest is marked with no objective line at all", marked_hostile())

	addon.module.set("quest_nameplates", "enabled", false)
	settle()
	check("turning the quest marks off takes every mark down, and the names stay left", mark.shown == false and made.nameplate3[1].shown == false and frame_of("nameplate1").name.justify == "LEFT")
	addon.module.set("nameplates", "enabled", false)
	check("turning the nameplates off takes every name back", mark.shown == false and frame_of("nameplate1").name.justify == "CENTER" and frame_of("nameplate2").name.justify == "CENTER" and frame_of("nameplate4").name.justify == "CENTER" and made.nameplate3[1].shown == false)
end
