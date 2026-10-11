-- The nameplate view: which kind a plate is, which kinds it works on, the places providers fill, and that a plate the
-- game lays out again keeps the layout.
return function(root, check, island_world)
	local addon, env, event, _, afters = island_world()
	local function settle()
		for _, after in ipairs(afters) do
			if after.delay == 0.25 and not after.done then after.done = true; after.callback() end
		end
	end
	local plates = env.Everlook.nameplates

	local function texture()
		local mark = { points = {}, shown = false }
		function mark:SetAtlas(atlas) self.atlas, self.path = atlas, nil end
		function mark:SetTexture(path) self.path, self.atlas = path, nil end
		function mark:SetSize(width, height) self.width, self.height = width, height end
		function mark:SetWidth(width) self.width, self.height = width, nil end
		function mark:SetVertexColor(...) self.tint = { ... } end
		function mark:ClearAllPoints() self.points = {} end
		function mark:SetPoint(...) self.points[#self.points + 1] = { ... } end
		function mark:Show() self.shown = true end
		function mark:Hide() self.shown = false end
		return mark
	end
	local function line()
		local text = { points = {}, shown = false }
		function text:SetFont(path, size, flags) self.path, self.size, self.flags = path, size, flags end
		function text:SetTextColor(...) self.color = { ... } end
		function text:SetText(value) self.text = value end
		function text:SetJustifyH(value) self.justify = value end
		function text:ClearAllPoints() self.points = {} end
		function text:SetPoint(...) self.points[#self.points + 1] = { ... } end
		function text:Show() self.shown = true end
		function text:Hide() self.shown = false end
		return text
	end

	-- A plate as the game builds it, with the switches that make it one kind or another.
	local made = {}
	local function plate(unit, flags)
		flags = flags or {}
		local name = { justify = "CENTER" }
		function name:GetJustifyH() return self.justify end
		function name:SetJustifyH(value) self.justify = value end
		function name:GetFont() return "Fonts\\Name.ttf", 17.5, "OUTLINE" end
		function name:GetStringWidth() return 100 end
		local frame = { name = name, HealthBarsContainer = { label = "bar" }, widgetsOnlyMode = flags.widgets or nil,
			textures = {}, lines = {} }
		function frame:CreateTexture() local mark = texture(); self.textures[#self.textures + 1] = mark; return mark end
		function frame:CreateFontString() local text = line(); self.lines[#self.lines + 1] = text; return text end
		for method, value in pairs({ IsShowOnlyName = flags.only_name, IsSimplified = flags.simplified, IsPlayer = flags.player, IsFriend = flags.friend, IsForbidden = flags.forbidden_frame }) do
			if value ~= nil then frame[method] = function() return value end end
		end
		function frame:UpdateAnchors() self.name.justify = "CENTER" end
		local holder = { GetUnit = function() return unit end, UnitFrame = frame }
		if flags.forbidden then holder.IsForbidden = function() return true end end
		frame.namePlateFrame = holder
		made[unit] = holder
		return holder
	end
	env.C_NamePlate = { GetNamePlateForUnit = function(unit) return made[unit] end, GetNamePlates = function()
		local list = {}
		for _, holder in pairs(made) do list[#list + 1] = holder end
		return list
	end }
	env.UnitExists = function() return true end
	env.UnitIsUnit = function(unit, other) return other == "player" and unit == "personal" end
	env.UnitIsPlayer = function() return false end
	env.UnitCanAttack = function() return false end

	-- Which kind each plate is.
	local cases = {
		{ "a1", { friend = false, player = false }, "enemy_npc" },
		{ "a2", { friend = false, player = true }, "enemy_player" },
		{ "a3", { friend = true, player = false }, "friendly_npc" },
		{ "a4", { friend = true, player = true }, "friendly_player" },
		{ "a5", { friend = true, player = true, only_name = true }, "name_only" },
		{ "a6", { friend = true, player = false, simplified = true }, "simplified" },
		{ "a7", { friend = true, player = false, widgets = true }, "widgets_only" },
		{ "a8", { forbidden = true }, "forbidden" },
		{ "personal", { friend = true, player = true }, "personal" },
	}
	for _, case in ipairs(cases) do
		check("the plate that is " .. case[3] .. " is told apart", plates.kind_of(plate(case[1], case[2]), case[1]) == case[3])
	end
	-- A plate that does not say who it is for is read from its unit, and one nothing can tell is unknown.
	env.UnitIsPlayer = function(unit) return unit == "b2" end
	env.UnitCanAttack = function(_, unit) return unit == "b1" or unit == "b2" end
	check("without the game's own answers, a plate is read from its unit", plates.kind_of(plate("b1", {}), "b1") == "enemy_npc" and plates.kind_of(plate("b2", {}), "b2") == "enemy_player")
	env.UnitIsPlayer, env.UnitCanAttack = nil, nil
	check("and one that cannot be told apart is unknown", plates.kind_of(plate("b3", {}), "b3") == nil)
	env.UnitIsPlayer = function() return false end
	env.UnitCanAttack = function() return false end

	-- The view works on the plate it knows how to lay out, and leaves the rest alone.
	addon.module.set("nameplates", "enabled", true)
	local mark = { atlas = "Test-Atlas", file = "Interface\\Test", tint = { 1, 0, 0 } }
	check("a provider is accepted", plates.provide({ source = "test", order = 5, lead = function() return mark end, subtitle = function(unit) return { text = "<Title>", color = { 0, 1, 0 } } end }) == true)
	for _, case in ipairs(cases) do plate(case[1], case[2]); event("NAME_PLATE_UNIT_ADDED", case[1]) end
	for _, case in ipairs({ "a1", "a2", "a3", "a4" }) do
		local frame = made[case].UnitFrame
		check("a full plate (" .. case .. ") gets a mark across both rows, a subtitle, and a left-aligned name",
			frame.textures[1] and frame.textures[1].shown and #frame.textures[1].points == 2 and frame.textures[1].points[1][1] == "TOPRIGHT"
			and frame.lines[1] and frame.lines[1].shown and frame.lines[1].text == "<Title>" and frame.name.justify == "LEFT")
	end
	local only = made.a5.UnitFrame
	check("a name-only plate keeps its name centred, since there is no bar to line up with", only.name.justify == "CENTER")
	check("its mark is beside the text itself, one row tall, and its subtitle centred under the name",
		only.textures[1].shown and #only.textures[1].points == 1 and only.textures[1].points[1][1] == "RIGHT" and only.textures[1].points[1][2] == only.name
		and only.textures[1].points[1][3] == "CENTER" and only.textures[1].points[1][4] == -52 and only.textures[1].width == 26 and only.textures[1].height == 26
		and only.lines[1].points[1][1] == "TOP" and only.lines[1].points[1][2] == only.name and only.lines[1].justify == "CENTER")
	for _, case in ipairs({ "a6", "a7", "a8", "personal" }) do
		local frame = made[case].UnitFrame
		check("the plate that is hands-off (" .. case .. ") is left exactly as the game made it", #frame.textures == 0 and #frame.lines == 0 and frame.name.justify == "CENTER")
	end
	check("the mark takes its art from the provider, with the tint", made.a1.UnitFrame.textures[1].atlas == nil and made.a1.UnitFrame.textures[1].path == "Interface\\Test" and made.a1.UnitFrame.textures[1].tint[1] == 1)
	check("and the subtitle is in the name's face, a little smaller, in the colour it asked for",
		made.a1.UnitFrame.lines[1].path == "Fonts\\Name.ttf" and made.a1.UnitFrame.lines[1].size == 14 and made.a1.UnitFrame.lines[1].color[2] == 1)

	-- The game lays a plate out again, and its name goes back to centred. Ours comes back.
	made.a1.UnitFrame:UpdateAnchors()
	check("when the game lays a plate out again the left alignment follows it", made.a1.UnitFrame.name.justify == "LEFT")

	-- Providers: the first with an answer wins, one that fails is skipped, an invalid one is refused.
	plates.provide({ source = "failing", order = 1, lead = function() error("provider failed") end })
	plates.provide({ source = "later", order = 50, lead = function() return { file = "Interface\\Later" } end })
	settle()
	check("a provider that fails is skipped, and the next answers... the first with an answer wins", made.a1.UnitFrame.textures[1].path == "Interface\\Test")
	check("the failure is kept", type(plates.last_error) == "string" and plates.last_error:find("provider failed", 1, true) ~= nil)
	plates.remove("test")
	settle()
	check("with the first provider gone the next one's mark shows", made.a1.UnitFrame.textures[1].path == "Interface\\Later")
	local _, why = plates.provide({ source = "x" })
	check("a provider with nothing to offer is refused", why == "invalid_spec")
	_, why = plates.provide({ source = "", lead = function() end })
	check("one with no name is refused", why == "invalid_source")
	_, why = plates.provide({ source = "x", lead = function() end, kinds = { "hostile" } })
	check("one that names a kind that does not exist is refused", why == "invalid_kinds")
	plates.provide({ source = "only_npcs", order = 0, kinds = { "friendly_npc" }, lead = function() return { file = "Interface\\Npc" } end })
	settle()
	check("a provider for some kinds is asked only for those", made.a3.UnitFrame.textures[1].path == "Interface\\Npc" and made.a1.UnitFrame.textures[1].path == "Interface\\Later")

	-- The game lays a plate out again over and over as it moves. Nobody is asked anything again for it.
	local asked = 0
	plates.provide({ source = "counter", order = 0, lead = function() asked = asked + 1 return { file = "Interface\\Counted" } end })
	settle()
	local before = asked
	for _ = 1, 50 do made.a1.UnitFrame:UpdateAnchors() end
	check("laying a plate out fifty times asks no provider anything", asked == before and made.a1.UnitFrame.name.justify == "LEFT")
	plates.remove("counter")
	settle()

	-- Anyone who had quest marks on keeps them, with the layout they chose, when the nameplate view arrives.
	env.EverlookDB.qol = { quest_nameplates = { enabled = true, layout = "name_left", width = 30, align_name = false } }
	check("the saved quest mark settings are carried to the nameplate view", plates.migrate_saved() == true
		and env.EverlookDB.qol.nameplates.enabled == true and env.EverlookDB.qol.nameplates.layout == "name_left"
		and env.EverlookDB.qol.nameplates.width == 30 and env.EverlookDB.qol.nameplates.align_name == false)
	check("and they are read as the nameplate view's own", addon.module.get("nameplates", "layout") == "name_left" and addon.module.enabled("nameplates"))
	env.EverlookDB.qol = { quest_nameplates = { enabled = true, layout = "bar_left" }, nameplates = { enabled = false } }
	check("a view that already has settings is left as it is", plates.migrate_saved() == false and env.EverlookDB.qol.nameplates.enabled == false)
	env.EverlookDB.qol = { quest_nameplates = { enabled = false, layout = "bar_left" } }
	check("and quest marks that were off bring nothing", plates.migrate_saved() == false and env.EverlookDB.qol.nameplates == nil)
	env.EverlookDB.qol = { npc_titles = { enabled = true } }
	check("anyone who had NPC titles on gets the nameplate view on too", plates.migrate_saved() == true and env.EverlookDB.qol.nameplates.enabled == true)
	env.EverlookDB.qol = { nameplates = { enabled = true } }

	-- A friendly player shown by name only can be given a bar, and the game's own setting is put back.
	local cvars = { nameplateShowOnlyNameForFriendlyPlayerUnits = "1" }
	local set_calls = 0
	env.GetCVar = function(name) return cvars[name] end
	env.SetCVar = function(name, value) cvars[name] = value; set_calls = set_calls + 1 end
	env.InCombatLockdown = function() return false end
	addon.module.set("nameplates", "player_bars", true)
	check("health bars on friendly players turn the game's name-only setting off", cvars.nameplateShowOnlyNameForFriendlyPlayerUnits == "0")
	check("and the setting it was is kept", env.EverlookDB.nameplates_cvars and env.EverlookDB.nameplates_cvars.nameplateShowOnlyNameForFriendlyPlayerUnits == "1")
	addon.module.set("nameplates", "player_bars", false)
	check("turning them off puts the setting back as it was", cvars.nameplateShowOnlyNameForFriendlyPlayerUnits == "1" and env.EverlookDB.nameplates_cvars == nil)
	env.InCombatLockdown = function() return true end
	set_calls = 0
	addon.module.set("nameplates", "player_bars", true)
	check("in combat the game's setting is left alone", set_calls == 0 and cvars.nameplateShowOnlyNameForFriendlyPlayerUnits == "1")
	addon.module.set("nameplates", "player_bars", false)
	env.InCombatLockdown = function() return false end

	-- Stacking: the game is told to push plates apart with the spacing chosen, and gets its own settings back.
	cvars.nameplateMotion, cvars.nameplateOverlapH, cvars.nameplateOverlapV = "0", "0.8", "1.1"
	addon.module.set("nameplates", "spacing_v", 1.5)
	check("stacking is on by default and sets motion and both spacings", cvars.nameplateMotion == "1" and cvars.nameplateOverlapH == "0.8" and cvars.nameplateOverlapV == "1.5" or false)
	addon.module.set("nameplates", "spacing_h", 0.4)
	check("a changed spacing is applied at once", cvars.nameplateOverlapH == "0.4")
	addon.module.set("nameplates", "stacking", false)
	check("turning stacking off puts motion and both spacings back as the game had them", cvars.nameplateMotion == "0" and cvars.nameplateOverlapH == "0.8" and cvars.nameplateOverlapV == "1.1")
	check("and nothing is kept for them", env.EverlookDB.nameplates_cvars == nil)
	addon.module.set("nameplates", "stacking", true)
	cvars.nameplateOverlapV = nil
	addon.module.set("nameplates", "spacing_v", 2)
	check("a setting this client does not have is left alone, and the others still apply", cvars.nameplateOverlapV == nil and cvars.nameplateMotion == "1" and cvars.nameplateOverlapH == "0.4")
	addon.module.set("nameplates", "stacking", false)

	-- Off puts everything back.
	addon.module.set("nameplates", "enabled", false)
	check("turning the view off puts every name back and hides every mark", made.a1.UnitFrame.name.justify == "CENTER" and made.a3.UnitFrame.textures[1].shown == false and made.a1.UnitFrame.lines[1].shown == false)
end
