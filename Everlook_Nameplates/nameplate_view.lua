local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local plates = Everlook.nameplates
local plain = plates.plain
local id = "nameplates"

-- One layout for every kind of nameplate, made by working on the game's own plate and not by replacing it. A
-- strategy is a function for a kind: it says which of the plate's parts it moves and which places it offers. The
-- places are a lead mark that stands left of the name and the health bar, and a subtitle line. What goes in them
-- comes from providers, other addons' functions that are asked about a unit and answer with a mark or a line.
--
--   plates.provide({ source = "mine", order = 10, kinds = { "friendly_npc" },
--       lead = function(unit, kind) return { atlas = "...", file = "..." } end,
--       subtitle = function(unit, kind) return { text = "<Gryphon Master>", color = { 0.1, 1, 0.1 } } end })
--
-- A kind with no strategy is left exactly as the game made it.

local providers = {}
local state = setmetatable({}, { __mode = "k" })
local hooked = setmetatable({}, { __mode = "k" })
local by_unit = {}

-- ---------------------------------------------------------------- providers

local function valid_kinds(kinds)
	if kinds == nil then return true end
	if type(kinds) ~= "table" then return false end
	local known = {}
	for _, kind in ipairs(plates.KINDS) do known[kind] = true end
	for _, kind in ipairs(kinds) do
		if not known[kind] then return false end
	end
	return true
end

function plates.provide(spec)
	if type(spec) ~= "table" or getmetatable(spec) ~= nil then return nil, "invalid_spec" end
	if type(spec.source) ~= "string" or spec.source == "" or #spec.source > 64 then return nil, "invalid_source" end
	if spec.order ~= nil and (type(spec.order) ~= "number" or spec.order ~= spec.order) then return nil, "invalid_order" end
	if spec.lead ~= nil and type(spec.lead) ~= "function" then return nil, "invalid_lead" end
	if spec.subtitle ~= nil and type(spec.subtitle) ~= "function" then return nil, "invalid_subtitle" end
	if spec.lead == nil and spec.subtitle == nil then return nil, "invalid_spec" end
	if not valid_kinds(spec.kinds) then return nil, "invalid_kinds" end
	local entry = { source = spec.source, order = spec.order or 100, lead = spec.lead, subtitle = spec.subtitle }
	if spec.kinds then
		entry.kinds = {}
		for _, kind in ipairs(spec.kinds) do entry.kinds[kind] = true end
	end
	for index, existing in ipairs(providers) do
		if existing.source == spec.source then table.remove(providers, index); break end
	end
	providers[#providers + 1] = entry
	table.sort(providers, function(left, right)
		if left.order ~= right.order then return left.order < right.order end
		return left.source < right.source
	end)
	plates.refresh()
	return true
end

function plates.remove(source)
	for index, existing in ipairs(providers) do
		if existing.source == source then
			table.remove(providers, index)
			plates.refresh()
			return true
		end
	end
	return false
end

-- The first provider with an answer wins a place. A provider that fails is skipped, and the failure kept.
local function ask(place, unit, kind)
	for _, provider in ipairs(providers) do
		local fn = provider[place]
		if fn and (not provider.kinds or provider.kinds[kind]) then
			local ok, answer = pcall(fn, unit, kind)
			if ok then
				if type(answer) == "table" then return answer end
			else
				plates.last_error = provider.source .. ": " .. tostring(answer)
			end
		end
	end
end

-- ---------------------------------------------------------------- the plate's parts

local function parts(frame)
	return frame.name, frame.HealthBarsContainer or frame.healthBar
end

local function slot(plate)
	local held = state[plate]
	if not held then
		held = {}
		state[plate] = held
	end
	return held
end

local function put_back(plate)
	local held = state[plate]
	if not held then return end
	if held.lead then held.lead:Hide() end
	if held.subtitle then held.subtitle:Hide() end
	if held.name and held.name.SetJustifyH then held.name:SetJustifyH(held.justify) end
	held.name, held.justify = nil, nil
end

local function left_align(plate, name)
	if not (name and name.SetJustifyH and name.GetJustifyH) then return end
	local held = slot(plate)
	if not held.name then
		local justify = name:GetJustifyH()
		if plain(justify) then held.name, held.justify = name, justify end
	end
	name:SetJustifyH("LEFT")
end

local function art(texture, answer)
	if answer.atlas and texture.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(answer.atlas) then
		texture:SetAtlas(answer.atlas)
	elseif answer.file then
		texture:SetTexture(answer.file)
	else
		texture:SetTexture(nil)
	end
	if answer.tint and texture.SetVertexColor then
		texture:SetVertexColor(answer.tint[1] or 1, answer.tint[2] or 1, answer.tint[3] or 1, answer.tint[4] or 1)
	elseif texture.SetVertexColor then
		texture:SetVertexColor(1, 1, 1, 1)
	end
end

-- The lead mark, left of the name and the health bar, as tall as the two together (or one row when there is no bar).
local function place_lead(plate, frame, name, bar, answer, two_rows)
	local held = slot(plate)
	local width = module.get(id, "width")
	local layout = module.get(id, "layout")
	local texture = held.lead
	if not texture then
		texture = frame:CreateTexture(nil, "OVERLAY")
		held.lead = texture
	end
	texture:ClearAllPoints()
	if layout == "name_right" and (name or bar) then
		texture:SetSize(width, width)
		texture:SetPoint("LEFT", name or bar, "RIGHT", 2, 0)
	elseif layout == "bar_left" and (bar or name) then
		texture:SetSize(width, width)
		texture:SetPoint("RIGHT", bar or name, "LEFT", -2, 0)
	elseif layout == "name_left" and (name or bar) then
		texture:SetSize(width, width)
		texture:SetPoint("RIGHT", name or bar, "LEFT", -2, 0)
	elseif two_rows and name and bar then
		-- Both rows: from the top of the name to the bottom of the health bar, just left of the bar's left end,
		-- which is four in from where the name starts.
		texture:SetWidth(width)
		texture:SetPoint("TOPRIGHT", name, "TOPLEFT", -6, 0)
		texture:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", -2, 0)
	elseif name or bar then
		texture:SetSize(width, width)
		texture:SetPoint("RIGHT", name or bar, "LEFT", -2, 0)
	else
		texture:Hide()
		return
	end
	art(texture, answer)
	texture:Show()
end

-- The subtitle: a line in the name's face a little smaller, under the health bar or, on a plate with no bar, under the name.
local function place_subtitle(plate, frame, name, bar, answer, two_rows)
	if type(answer.text) ~= "string" or answer.text == "" then return end
	local held = slot(plate)
	local line = held.subtitle
	if not line then
		line = frame:CreateFontString(nil, "OVERLAY")
		held.subtitle = line
	end
	if name and name.GetFont then
		local path, size, flags = name:GetFont()
		if plain(path) and type(path) == "string" and plain(size) and type(size) == "number" then
			line:SetFont(path, math.max(8, math.floor(size * 0.8 + 0.5)), flags)
		end
	end
	local color = answer.color
	line:SetTextColor(color and color[1] or 0.8, color and color[2] or 0.8, color and color[3] or 0.8)
	line:ClearAllPoints()
	if two_rows and bar then
		line:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 4, -2)
	elseif name then
		line:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -1)
	else
		line:Hide()
		return
	end
	line:SetJustifyH("LEFT")
	line:SetText(answer.text)
	line:Show()
end

-- ---------------------------------------------------------------- strategies

-- A strategy is applied to one plate. The kinds it is for are listed with it; a kind that is in none is left alone.
local strategies = {
	full = { kinds = { "enemy_npc", "enemy_player", "friendly_npc", "friendly_player" }, two_rows = true },
	name_only = { kinds = { "name_only" }, two_rows = false },
}
local strategy_of = {}
for _, strategy in pairs(strategies) do
	for _, kind in ipairs(strategy.kinds) do strategy_of[kind] = strategy end
end
plates.strategy_of = strategy_of

local function apply(plate, unit)
	put_back(plate)
	if not (module.enabled(id) and type(plate) == "table") then return end
	local frame = plate.UnitFrame
	if type(frame) ~= "table" or not frame.CreateTexture then return end
	local kind = plates.kind_of(plate, unit)
	local strategy = kind and strategy_of[kind]
	if not strategy then return end
	local name, bar = parts(frame)
	if module.get(id, "align_name") then left_align(plate, name) end
	if unit then by_unit[unit] = plate end
	local lead = unit and ask("lead", unit, kind)
	if lead then place_lead(plate, frame, name, bar, lead, strategy.two_rows) end
	local subtitle = unit and ask("subtitle", unit, kind)
	if subtitle then place_subtitle(plate, frame, name, bar, subtitle, strategy.two_rows) end
end

-- The game lays a plate out again from time to time, which can be often while plates move with the camera, and
-- puts the name back. Only the name is put right, which costs nothing: the marks and lines are anchored to the
-- plate's parts and the game's layout does not touch them, and nobody is asked anything again until a plate is
-- added, a provider says something changed, or an option does.
local function follow(frame)
	if hooked[frame] or type(frame.UpdateAnchors) ~= "function" or not hooksecurefunc then return end
	hooked[frame] = true
	hooksecurefunc(frame, "UpdateAnchors", function(laid_out)
		local plate = laid_out.namePlateFrame or (laid_out.GetParent and laid_out:GetParent())
		local held = plate and state[plate]
		if held and held.name then held.name:SetJustifyH("LEFT") end
	end)
end

local function show(unit)
	local plate = plates.plate_of(unit)
	if not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
	if plate.UnitFrame then follow(plate.UnitFrame) end
	apply(plate, unit)
end

local function hide(unit)
	local plate = by_unit[unit]
	by_unit[unit] = nil
	if plate then put_back(plate) end
end

local function refresh_all()
	for unit in pairs(by_unit) do hide(unit) end
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		local unit = plates.unit_of(plate)
		if unit then show(unit) end
	end
end

-- Providers change often in a burst, and each plate costs a few questions, so the plates are looked at once, a
-- moment after the last change.
local queued = false
function plates.refresh()
	if queued then return end
	if not (C_Timer and C_Timer.After) then refresh_all() return end
	queued = true
	C_Timer.After(0.25, function()
		queued = false
		refresh_all()
	end)
end

function plates.refresh_unit(unit)
	if type(unit) == "string" then show(unit) end
end

-- Quest marks used to place themselves. Anyone who had them on gets the nameplate view on with the same layout,
-- before the module's defaults are filled in, so the marks do not go away when this addon arrives.
function plates.migrate_saved()
	local saved = EverlookDB and EverlookDB.qol
	if type(saved) ~= "table" then return false end
	local old, new = saved.quest_nameplates, saved.nameplates
	if type(old) ~= "table" or old.enabled ~= true or new ~= nil then return false end
	saved.nameplates = { enabled = true }
	for _, key in ipairs({ "layout", "width", "align_name" }) do
		if old[key] ~= nil then saved.nameplates[key] = old[key] end
	end
	return true
end
EventUtil.ContinueOnAddOnLoaded(addon_name, plates.migrate_saved)

module.register({
	addon = addon_name, page = "interface", order = 44,
	id = id,
	name = "Nameplates",
	description = "Gives every kind of nameplate one layout: the name at the left end of its health bar, a mark to the left of the name and the health bar when another module has one for that unit, and a subtitle line under the bar. It works on the game's own plates and puts each back as the game had it when this is off or the plate goes. Plates that cannot be changed or that are not a name over a bar, such as a player's own, one with only widgets and a simplified one, are left as the game made them.",
	options = {
		layout = { name = "Where the mark goes", default = "rows", choices = { { "rows", "Left of the name and the health bar" }, { "name_left", "Left of the name" }, { "name_right", "Right of the name" }, { "bar_left", "Left of the health bar" } }, description = "Puts a mark to the left of both the name and the health bar, as tall as the two together, or beside only the name or only the health bar." },
		width = { name = "Mark width", default = 26, min = 12, max = 48, step = 2, description = "Sets how wide a mark is, from 12 to 48, in steps of 2. Beside both the name and the health bar it is as tall as the two together, and beside only one it is square." },
		align_name = { name = "Left-align every nameplate's name", default = true, description = "Moves the name on every nameplate this works on to the left end of its health bar, so that every plate reads alike, and puts each back as the game had it when this is turned off or the plate goes." },
	},
	apply = refresh_all,
	events = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_ENTERING_WORLD" },
	on_event = function(event, unit)
		if event == "NAME_PLATE_UNIT_ADDED" then
			if plain(unit) and type(unit) == "string" then show(unit) end
		elseif event == "NAME_PLATE_UNIT_REMOVED" then
			if plain(unit) and type(unit) == "string" then hide(unit) end
		else
			refresh_all()
		end
	end,
})
