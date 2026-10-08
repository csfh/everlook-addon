local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "unit_names"
local states = {}

-- PlayerName and the target's Name are GameFontNormalSmall, 10 points in a
-- 12-point-tall region. A larger font is clipped unless the region grows.
-- Another addon can replace the font file afterwards. A size this module did
-- not write becomes the new base, so that file stays and the extra size is
-- added on top of it.
local function names()
	local list = {}
	if type(PlayerName) == "table" then list[#list + 1] = PlayerName end
	local frame = TargetFrame
	local content = type(frame) == "table" and frame.TargetFrameContent
	local main = type(content) == "table" and content.TargetFrameContentMain
	local name = type(main) == "table" and main.Name
	if type(name) == "table" then list[#list + 1] = name end
	return list
end

local function state_for(font)
	local path, size, flags = font:GetFont()
	if type(path) ~= "string" or type(size) ~= "number" then return end
	local state = states[font]
	if not state then
		local height = type(font.GetHeight) == "function" and font:GetHeight() or nil
		state = { base = size, height = type(height) == "number" and height or nil }
		states[font] = state
	else
		if size ~= state.applied then state.base = size end
		local height = type(font.GetHeight) == "function" and font:GetHeight() or nil
		if type(height) == "number" and height ~= state.applied_height then state.height = height end
	end
	return state, path, flags
end

local function resize(font, extra)
	if type(font) ~= "table" or type(font.GetFont) ~= "function" or type(font.SetFont) ~= "function" then return end
	local state, path, flags = state_for(font)
	if not state then return end
	local next_size = state.base + extra
	font:SetFont(path, next_size, flags)
	state.applied = next_size
	if type(state.height) == "number" and type(font.SetHeight) == "function" then
		state.applied_height = math.max(state.height, next_size)
		font:SetHeight(state.applied_height)
	end
end

local function restore(font)
	local state = states[font]
	states[font] = nil
	if not state or type(font) ~= "table" or type(font.GetFont) ~= "function" or type(font.SetFont) ~= "function" then return end
	local path, size, flags = font:GetFont()
	if type(path) == "string" and size == state.applied then font:SetFont(path, state.base, flags) end
	if type(font.GetHeight) == "function" and type(font.SetHeight) == "function"
		and state.applied_height ~= nil and font:GetHeight() == state.applied_height then
		font:SetHeight(state.height)
	end
end

local function apply(enabled)
	if type(InCombatLockdown) ~= "function" or InCombatLockdown() then return end
	local list = names()
	if not enabled then
		for font in pairs(states) do restore(font) end
		return
	end
	local extra = module.get(id, "extra")
	for index = 1, #list do resize(list[index], extra) end
end

module.register({
	addon = addon_name, page = "interface", order = 30,
	id = id,
	name = "Unit frame names",
	description = "Adds the points on Extra points to the player and target names on the default unit frames, and grows each name's region so the larger text is not clipped. Focus, target of target, and boss names stay as they are, the change waits until combat ends, a missing name is skipped, a font another addon set stays and the extra points sit on top of it, and turning this off puts back the size and the region height while each still shows what this set.",
	options = {
		extra = { name = "Extra points", default = 4, min = 1, max = 12, step = 1, description = "Adds this many points, from 1 to 12, to the player and target names, and grows each name's region so the larger text is not clipped. A missing name is skipped, Focus, target of target, and boss names stay as they are, a font another addon set stays and these points sit on top of it, the change waits until combat ends, and this number does nothing until Unit frame names is on." },
	},
	apply = apply,
	out_of_combat = true,
	events = { "PLAYER_ENTERING_WORLD" },
	on_event = function() apply(module.enabled(id)) end,
})

if CreateFrame then
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("ADDON_LOADED")
	watcher:SetScript("OnEvent", function(_, _, name)
		if name == "Blizzard_UnitFrame" then apply(module.enabled(id)) end
	end)
end
