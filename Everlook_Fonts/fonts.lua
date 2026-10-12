local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "fonts"
local interface_font = "Interface\\AddOns\\Everlook_Fonts\\assets\\expressway.ttf"
-- Chat and names carry what players type. Manrope draws Latin, Cyrillic,
-- Greek and Vietnamese, and Expressway has no Greek.
local people_font = "Interface\\AddOns\\Everlook_Fonts\\assets\\manrope.ttf"
-- Each game font is a family with one member per alphabet, and SetFont
-- replaces only the member for the client's own alphabet. Korean and Chinese
-- text keeps the game's fonts that way, but on a Korean or Chinese client the
-- replaced member is one neither font can draw.
local unsupported_locales = { koKR = true, zhCN = true, zhTW = true }
local interface_globals = { "STANDARD_TEXT_FONT", "DAMAGE_TEXT_FONT" }
-- The engine draws names in the world with these. NAMEPLATE_FONT names a font
-- object rather than a file, so it stays.
local name_globals = { "UNIT_NAME_FONT", "UNIT_NAME_FONT_ROMAN" }
local people_font_names = {
	"ChatFontNormal", "ChatFontSmall", "ChatBubbleFont",
	"SystemFont_NamePlate", "SystemFont_NamePlate_Outlined", "SystemFont_NamePlateFixed",
	"SystemFont_LargeNamePlate", "SystemFont_LargeNamePlateFixed", "SystemFont_NamePlateCastBar",
	-- A tooltip's first line is the name of the unit, item or spell it describes.
	"GameTooltipHeaderText",
}
local originals = setmetatable({}, { __mode = "k" })
local constants = {}
local compact_names = setmetatable({}, { __mode = "k" })
local hooked = {}
-- A full pass walks every font and frame, so it runs only when something may
-- have changed: another addon loaded, a pass was blocked by combat, the size
-- changed, or the module was just turned on.
local stale = true
local passed_offset

local function font_object_of(object)
	if type(object.GetFontObject) ~= "function" then return nil end
	return object:GetFontObject()
end

-- Text that inherits one of these fonts changes along with it. SetFont on the
-- text itself would pin it at its current font and size.
local function follows(object, fonts)
	if fonts[object] then return true end
	local parent = font_object_of(object)
	return parent ~= nil and fonts[parent] == true
end

-- Text that inherits a font this module already replaced reports the
-- replacement, so what it had before is the font it inherited.
local function original_of(object, path, size, flags)
	local parent = font_object_of(object)
	local inherited = parent and originals[parent]
	if inherited and path == inherited.font and size == inherited.last_size then
		return { inherited[1], inherited[2], flags }
	end
	return { path, size, flags }
end

local function replace(object, font, offset)
	if not object or not object.GetFont or not object.SetFont then return end
	if object.IsForbidden and object:IsForbidden() then return end
	local path, size, flags = object:GetFont()
	if not path or not size then return end
	local original = originals[object]
	local seen_before = original ~= nil
	if not original then
		original = original_of(object, path, size, flags)
		originals[object] = original
	elseif original.last_size and size ~= original.last_size then
		original[2] = size
	end
	original.font = font
	original.last_size = math.max(6, original[2] + offset)
	-- A later pass leaves text it already set where it is.
	if seen_before and path == font and size == original.last_size then return end
	object:SetFont(font, original.last_size, flags)
end

-- A chat window's size belongs to its tab, so it stays. A window opened after
-- ChatFontNormal changed copied this module's font, and goes back to the font
-- ChatFontNormal had.
local function replace_chat(frame)
	if frame.IsForbidden and frame:IsForbidden() then return end
	local path, size, flags = frame:GetFont()
	if not path or not size then return end
	if not originals[frame] then
		local source = ChatFontNormal and originals[ChatFontNormal]
		originals[frame] = { path == people_font and source and source[1] or path, nil, flags }
	end
	frame:SetFont(people_font, size, flags)
end

local function chat_frames()
	local list = {}
	if type(CHAT_FRAMES) ~= "table" then return list end
	for _, name in ipairs(CHAT_FRAMES) do
		local frame = _G[name]
		if type(frame) == "table" and type(frame.GetFont) == "function" and type(frame.SetFont) == "function" then
			list[#list + 1] = frame
		end
	end
	return list
end

-- Unit frame names inherit GameFontNormalSmall, which much other text shares,
-- so each name gets its own font.
local function name_texts()
	local list = {}
	local function add(text) if type(text) == "table" then list[#list + 1] = text end end
	add(PlayerName)
	add(PetName)
	for _, key in ipairs({ "TargetFrame", "FocusFrame" }) do
		local frame = _G[key]
		if type(frame) == "table" then
			local content = frame.TargetFrameContent
			local main = type(content) == "table" and content.TargetFrameContentMain
			if type(main) == "table" then add(main.Name) end
			if type(frame.totFrame) == "table" then add(frame.totFrame.Name) end
		end
	end
	local pool = type(PartyFrame) == "table" and PartyFrame.PartyMemberFramePool
	if type(pool) == "table" and type(pool.EnumerateActive) == "function" then
		for member in pool:EnumerateActive() do
			add(member.Name)
			if type(member.PetFrame) == "table" then add(member.PetFrame.Name) end
		end
	end
	for text in pairs(compact_names) do add(text) end
	return list
end

local function ready()
	if not module.enabled(id) or (InCombatLockdown and InCombatLockdown()) then return false end
	return not (GetLocale and unsupported_locales[GetLocale()])
end

local function refresh_names()
	if not ready() then
		stale = true
		return
	end
	local offset = module.get(id, "size_offset")
	for _, text in ipairs(name_texts()) do replace(text, people_font, offset) end
end

-- Party members and raid-style frames are made after login, so their names
-- change as each one is set up.
local function hook_name_frames()
	if not hooked.party and type(PartyFrame) == "table" and type(PartyFrame.InitializePartyMemberFrames) == "function" then
		hooksecurefunc(PartyFrame, "InitializePartyMemberFrames", refresh_names)
		hooked.party = true
	end
	if not hooked.compact and type(DefaultCompactUnitFrameSetup) == "function" then
		hooksecurefunc("DefaultCompactUnitFrameSetup", function(frame)
			if type(frame) ~= "table" or type(frame.name) ~= "table" then return end
			compact_names[frame.name] = true
			if ready() then replace(frame.name, people_font, module.get(id, "size_offset")) else stale = true end
		end)
		hooked.compact = true
	end
end

local function set_globals(keys, font)
	for _, key in ipairs(keys) do
		if type(_G[key]) == "string" then constants[key] = constants[key] or _G[key]; _G[key] = font end
	end
end

local function restore()
	for object, original in pairs(originals) do
		if not object.IsForbidden or not object:IsForbidden() then
			local _, size, flags = object:GetFont()
			if size and size ~= original.last_size then original[2] = size end
			object:SetFont(original[1], original[2], flags or original[3])
		end
	end
	for key, path in pairs(constants) do _G[key] = path end
	originals = setmetatable({}, { __mode = "k" })
	constants = {}
end

-- A pass over every frame is about thirteen thousand frames and close to a
-- hundred milliseconds, which would stall one frame. It runs as a scheduler
-- task in slices, `job` holding where it is. A slice may take a little more
-- than the scheduler's share, because the text is only wrong until it is done.
local SLICE_MS = 4
local job
local task

local function clock()
	if type(debugprofilestop) == "function" then return debugprofilestop() end
end

local function restyle_regions(frame, kept, people_fonts, names, offset, ...)
	for index = 1, select("#", ...) do
		local region = select(index, ...)
		if region.GetObjectType and region:GetObjectType() == "FontString"
			and not follows(region, kept) and not follows(region, people_fonts) then
			replace(region, names[region] and people_font or interface_font, offset)
			names[region] = nil
		end
	end
end

-- Sets the globals and the font objects, which is quick, and returns the pass.
local function begin_pass()
	hook_name_frames()
	local offset = module.get(id, "size_offset")
	passed_offset = offset
	stale = false
	set_globals(interface_globals, interface_font)
	set_globals(name_globals, people_font)
	local people_fonts = {}
	for _, name in ipairs(people_font_names) do
		local object = _G[name]
		if object then people_fonts[object] = true end
	end
	-- Tracker text follows shared fonts that SetTextSize points at other
	-- fonts. Chat lines follow their window's own copy of ChatFontNormal.
	local kept = {}
	if ObjectiveTrackerLineFont then kept[ObjectiveTrackerLineFont] = true end
	if ObjectiveTrackerHeaderFont then kept[ObjectiveTrackerHeaderFont] = true end
	for _, frame in ipairs(chat_frames()) do
		replace_chat(frame)
		local own = font_object_of(frame)
		if own and not people_fonts[own] then kept[own] = true end
	end
	for _, object in pairs(_G) do
		if (type(object) == "table" or type(object) == "userdata") and object.GetObjectType
			and (not object.IsForbidden or not object:IsForbidden()) and object:GetObjectType() == "Font" and not follows(object, kept) then
			replace(object, people_fonts[object] and people_font or interface_font, offset)
		end
	end
	local names = {}
	for _, text in ipairs(name_texts()) do names[text] = true end
	local trace = Everlook.trace
	if trace then trace.count("fonts_passes") end
	return { offset = offset, kept = kept, people_fonts = people_fonts, names = names, walked = 0, frame = false }
end

-- Walks frames until `limit_ms` is up, and says whether any are left.
local function walk(pass, limit_ms)
	if not EnumerateFrames then return false end
	local began = clock()
	local frame
	if pass.frame == false then frame = EnumerateFrames() else frame = EnumerateFrames(pass.frame) end
	local count = 0
	while frame do
		pass.walked = pass.walked + 1
		count = count + 1
		if not frame.IsForbidden or not frame:IsForbidden() then
			restyle_regions(frame, pass.kept, pass.people_fonts, pass.names, pass.offset, frame:GetRegions())
		end
		pass.frame = frame
		frame = EnumerateFrames(frame)
		if frame and began and count % 32 == 0 and clock() - began >= limit_ms then
			return true
		end
	end
	pass.frame = nil
	return false
end

local function finish(pass)
	-- Party members and raid-style frames hang under frames this walk can miss.
	for text in pairs(pass.names) do replace(text, people_font, pass.offset) end
	if Everlook.trace then Everlook.trace.count("fonts_frames", pass.walked) end
end

-- One slice of the pass. True while frames are left. Another request that
-- came in during the pass starts the next one when this one ends.
local function slice(limit_ms)
	if not module.enabled(id) or (GetLocale and unsupported_locales[GetLocale()]) then
		job = nil
		return false
	end
	if InCombatLockdown and InCombatLockdown() then
		return true
	end
	if not job then
		if not stale and passed_offset == module.get(id, "size_offset") then return false end
		job = begin_pass()
	end
	if walk(job, math.max(limit_ms or 0, SLICE_MS)) then return true end
	finish(job)
	job = nil
	return stale or passed_offset ~= module.get(id, "size_offset")
end

local function timed_slice(limit_ms)
	local trace = Everlook.trace
	if not trace then return slice(limit_ms) end
	return trace.span("fonts_pass", slice, limit_ms)
end

local function run_now()
	local guard = 0
	while timed_slice(1e9) and guard < 1000 and not (InCombatLockdown and InCombatLockdown()) do guard = guard + 1 end
end

local function restore_all()
	job = nil
	if InCombatLockdown and InCombatLockdown() then
		stale = true
		return
	end
	restore()
	stale, passed_offset = true, nil
end

-- Turning off puts the fonts back at once. Turning on, a new size, a loaded
-- addon or a blocked pass asks for a pass, and the requests in one burst of
-- loads are answered by one pass, a few milliseconds a frame.
local function apply(enabled)
	if not enabled then return restore_all() end
	if enabled and GetLocale and unsupported_locales[GetLocale()] then return end
	if not stale and passed_offset == module.get(id, "size_offset") and not job then return end
	stale = stale or passed_offset ~= module.get(id, "size_offset")
	if Everlook.sched and Everlook.sched.task and type(CreateFrame) == "function" and type(debugprofilestop) == "function" then
		task = task or Everlook.sched.task("fonts", { step = timed_slice, combat = "pause" })
		task.wake()
	else
		run_now()
	end
end

-- Zone changes and instance loading screens add no text this module has not
-- seen, so only a login or a reload walks everything again.
local function on_event(event, first, second)
	if event == "PLAYER_ENTERING_WORLD" and first == false and second == false then return end
	stale = true
	apply(true)
end

module.register({
	addon = addon_name, page = "interface", order = 20,
	id = id, name = "Fonts", description = "Sets chat, chat bubbles, nameplates, the names on unit frames, party frames, and raid-style frames, and the name at the top of a tooltip in Manrope, and the rest of the interface in Expressway. It waits while you are in combat. Text in another alphabet, such as Korean or Chinese, keeps the game's font for that alphabet, and a Korean or Chinese client keeps all of its fonts. Turning this off puts the previous fonts back once you are out of combat. A font the client forbids stays as it is, quest tracker lines and headers keep their shared font so Objective size still changes them, and names and damage text the engine draws in the world change after you log in again.",
	options = { size_offset = { name = "Font size adjustment", default = 0, min = -4, max = 8, step = 1, unit = " pt", description = "Adds this many points to each font this replaces, on top of that font's own size. Chat windows keep the size set on their tab. The shared line and header fonts are not given their own size, the tracker sizes they follow include this addition, and nothing is set under six points. The change waits until combat ends, and this number does nothing until Fonts is on." } },
	apply = apply, out_of_combat = true,
	events = { "ADDON_LOADED", "PLAYER_ENTERING_WORLD" }, on_event = on_event,
})
