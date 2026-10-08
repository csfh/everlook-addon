local addon_name = ...
local Everlook = Everlook
local kit = Everlook.island_feed_kit
local plain_number, now, option, dismiss, notify = kit.plain_number, kit.now, kit.option, kit.dismiss, kit.notify
local state = {}

-- A notice when a profession passes a 25-point mark or a recipe is learned.
local function profession_rows()
	if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then return nil end
	local slots = { GetProfessions() }
	local rows = {}
	for index = 1, #slots do
		local slot = plain_number(slots[index])
		if slot and slot % 1 == 0 and slot >= 1 then
			local name, _, skill, _, _, _, skill_line = GetProfessionInfo(slot)
			skill, skill_line = plain_number(skill), plain_number(skill_line)
			if skill and skill_line and skill >= 0 and skill_line % 1 == 0 then
				if type(name) ~= "string" or name == "" or (issecretvalue and issecretvalue(name)) then name = "Profession " .. skill_line end
				rows[#rows + 1] = { id = skill_line, name = name, skill = skill }
			end
		end
	end
	return rows
end

local function milestone(skill)
	if skill < 25 then return 0 end
	return math.floor(skill / 25) * 25
end

local function note_profession(id, line)
	local time = now()
	if not state.prof_at or time - state.prof_at > 2 then
		state.prof_lines, state.prof_ids = {}, {}
		state.prof_seq = (state.prof_seq or 0) + 1
	end
	state.prof_at = time
	state.prof_lines = state.prof_lines or {}
	state.prof_ids = state.prof_ids or {}
	local index = state.prof_ids[id]
	if index then state.prof_lines[index] = line else
		state.prof_lines[#state.prof_lines + 1] = line
		state.prof_ids[id] = #state.prof_lines
	end
	local text = table.concat(state.prof_lines, " · ")
	if #text > 512 then text = text:sub(1, 512) end
	state.prof_handle = notify({
		source = "everlook.professions", key = "professions:" .. state.prof_seq, kind = "profession", stack = "craft", text = text,
		actions = { { id = "open", label = "Open professions", type = "callback", on_click = function()
			if ToggleProfessionsBook then ToggleProfessionsBook() end
		end } },
	})
end

local function professions()
	if not option("feed_professions") then
		if dismiss(state.prof_handle) then state.prof_handle = nil end
		state.prof, state.prof_lines, state.prof_ids, state.prof_at = nil, nil, nil, nil
		return
	end
	local rows = profession_rows()
	if not rows then return end
	if not state.prof then
		state.prof = {}
		for index = 1, #rows do state.prof[rows[index].id] = milestone(rows[index].skill) end
		return
	end
	for index = 1, #rows do
		local row = rows[index]
		local reached = milestone(row.skill)
		local prior = state.prof[row.id]
		state.prof[row.id] = reached
		if prior and reached > prior then note_profession("skill:" .. row.id, row.name .. " reached " .. reached) end
	end
end

local function recipe(recipe_id)
	if not option("feed_professions") then return end
	recipe_id = plain_number(recipe_id)
	if not recipe_id or recipe_id < 1 or recipe_id % 1 ~= 0 then return end
	note_profession("recipe:" .. recipe_id, "New recipe")
end

local function poll()
	if not kit.due(state.slow_at) then return end
	state.slow_at = now()
	professions()
end

Everlook.module.extend("smart_island", {
	id = "professions", addon = addon_name, order = 50,
	options = {
		feed_professions = { name = "Professions", default = false, description = "Tells you when a profession reaches a higher 25-point mark, naming that profession and the highest mark it crossed, or Profession and its skill line number when the name is hidden, or says New recipe when you learn one, and lines from the same two seconds share one notice. The skills you already have stay quiet, and so do a drop, a gain inside the same 25 points, a profession the first time it appears, a skill or a recipe the client hides, skill marks stay quiet when the client cannot list professions, a learned recipe says New recipe, a later mark or recipe joins that notice while it is still up, and turning this off clears the notice.", presets = { Quiet = false, Standard = false, Informative = true } },
	},
	sections = { { name = "Notices", keys = { "feed_professions" } } },
	events = { "SKILL_LINES_CHANGED", "NEW_RECIPE_LEARNED", "PLAYER_ENTERING_WORLD" },
	on_event = function(event, ...)
		if event == "NEW_RECIPE_LEARNED" then recipe(...)
		elseif event == "PLAYER_ENTERING_WORLD" then poll()
		else professions() end
	end,
	apply = function(enabled)
		if not enabled then state = {}; return end
		state.slow_at = nil
		poll()
	end,
	refresh = function(force)
		if not force then poll() end
	end,
})
