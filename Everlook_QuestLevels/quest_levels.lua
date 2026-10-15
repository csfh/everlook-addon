local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "quest_levels"

Everlook.quest_levels = {}

-- The level goes in front of a quest's title on the quest log list, where the game draws the title. It is done after
-- the game has drawn the list, on the text of each button, and nothing the game owns is replaced: the lookup that
-- gives a quest its title (`C_QuestLog.GetTitleForQuestID`) is left alone, since replacing it makes every caller of
-- it, the secure tracker among them, run with the addon's taint. Each text this changes is remembered, so turning
-- the module off puts back exactly that text and nothing else.
local hooked = false
local touched = setmetatable({}, { __mode = "k" })

function Everlook.quest_levels.decorate(title, level)
	if issecretvalue and issecretvalue(title) then
		return title
	end
	if type(title) ~= "string" or type(level) ~= "number" then
		return title
	end
	return "[" .. math.floor(level) .. "] " .. title
end

local function level_for(quest_id)
	local row = Everlook.world and Everlook.world.row and Everlook.world.row("quests", quest_id)
	if type(row) == "table" and type(row.level) == "number" then
		return row.level
	end
	if C_QuestLog and C_QuestLog.GetQuestDifficultyLevel then
		return C_QuestLog.GetQuestDifficultyLevel(quest_id)
	end
end

local function title_buttons()
	local scroll = _G.QuestScrollFrame
	local pool = type(scroll) == "table" and scroll.titleFramePool
	if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then
		return function() end
	end
	return pool:EnumerateActive()
end

-- Sets a text and keeps the button as tall as its text needs, since the game sized the button from the old one.
local function set_text(button, text)
	local region = button.Text
	local before = type(region.GetHeight) == "function" and region:GetHeight() or nil
	region:SetText(text)
	local after = type(region.GetHeight) == "function" and region:GetHeight() or nil
	if type(before) == "number" and type(after) == "number" and after ~= before
		and type(button.GetHeight) == "function" and type(button.SetHeight) == "function" then
		button:SetHeight(button:GetHeight() + (after - before))
		local contents = _G.QuestScrollFrame and _G.QuestScrollFrame.Contents
		if type(contents) == "table" and type(contents.MarkDirty) == "function" then contents:MarkDirty() end
	end
end

local function restore(button)
	local region = button.Text
	local record = type(region) == "table" and touched[region]
	if record and region:GetText() == record.shown then
		set_text(button, record.original)
	end
	touched[region] = nil
end

local function decorate_log()
	if not module.enabled(id) then return end
	for button in title_buttons() do
		local region = type(button) == "table" and button.Text
		if type(region) == "table" and type(region.GetText) == "function" and type(region.SetText) == "function" then
			local text = region:GetText()
			local record = touched[region]
			if type(text) == "string" and not (issecretvalue and issecretvalue(text)) and not (record and record.shown == text) then
				-- A title the game already gave a bracket, such as its own level for colour-blind players or the
				-- number of group mates on the quest, is left as it is.
				local level = not text:find("^%[%d+%]") and type(button.questID) == "number" and level_for(button.questID) or nil
				local shown = Everlook.quest_levels.decorate(text, level)
				if shown ~= text then
					touched[region] = { original = text, shown = shown }
					set_text(button, shown)
				end
			end
		end
	end
end

local function apply(enabled)
	if not enabled then
		for button in title_buttons() do
			if type(button) == "table" then restore(button) end
		end
		return
	end
	if not hooked and type(_G.QuestLogQuests_Update) == "function" and type(hooksecurefunc) == "function" then
		hooksecurefunc("QuestLogQuests_Update", decorate_log)
		hooked = true
	end
	decorate_log()
end

module.register({
	addon = addon_name, page = "quests", order = 10,
	id = id,
	name = "Quest levels",
	description = "Puts the level in brackets in front of a quest title on the quest log list, using a level you have recorded when there is one and the game's own level otherwise. A title the client hides, a title that already starts with a number in brackets, or a quest with no level stays as it is, the quest tracker and the map are left alone, nothing happens when the client has no quest log list, and turning this off puts the game's titles back.",
	apply = apply,
	events = { "ADDON_LOADED" }, on_event = function() apply(module.enabled(id)) end,
})
