local addon_name = ...
local Everlook = Everlook
-- Blizzard_ActionBar/Shared/ActionButton.lua (12.0.0) registers each button
-- with ActionBarButtonEventsFrame and writes HotKey in UpdateHotkeys.
local module = Everlook.module
local id = "action_shortcuts"
local hooked_buttons = setmetatable({}, { __mode = "k" })
local hooked_managers = setmetatable({}, { __mode = "k" })
local labels = setmetatable({}, { __mode = "k" })

local function readable(text)
	return not (issecretvalue and issecretvalue(text)) and type(text) == "string"
end

local function compact(button)
	local font = button.HotKey
	if not font or type(font.GetText) ~= "function" or type(font.SetText) ~= "function" then return end
	local text = font:GetText()
	if not readable(text) then return end
	local prefix, key = "", text
	while true do
		local modifier, rest = key:match("^([sSaA])%-(.+)$")
		if not modifier then break end
		prefix, key = prefix .. modifier:upper(), rest
	end
	local replacement = prefix .. key
	if replacement == text then return end
	labels[font] = { original = text, applied = replacement }
	font:SetText(replacement)
end

local function attach(button)
	if type(button.UpdateHotkeys) ~= "function" then return end
	if not hooked_buttons[button] then
		-- The mixin has already been copied onto existing buttons. Hook each
		-- button, so Blizzard's UPDATE_BINDINGS refresh keeps the short label.
		hooksecurefunc(button, "UpdateHotkeys", function(self)
			if module.enabled(id) then compact(self) end
		end)
		hooked_buttons[button] = true
	end
	compact(button)
end

local function apply(enabled)
	if not enabled then
		for font, state in pairs(labels) do
			local text = font:GetText()
			if readable(text) and text == state.applied then font:SetText(state.original) end
			labels[font] = nil
		end
		return
	end
	local manager = ActionBarButtonEventsFrame
	if not manager or type(manager.ForEachFrame) ~= "function"
		or type(manager.RegisterFrame) ~= "function" or type(hooksecurefunc) ~= "function" then return end
	if not hooked_managers[manager] then
		hooksecurefunc(manager, "RegisterFrame", function(_, button)
			if module.enabled(id) then attach(button) end
		end)
		hooked_managers[manager] = true
	end
	manager:ForEachFrame(attach)
end

module.register({
	addon = addon_name, page = "interface", order = 60,
	id = id,
	name = "Compact action shortcuts",
	description = "Shortens Shift and Alt on the default action bars, so s-4 and a-4 read as S4 and A4, and s-a-4 reads as SA4. Ctrl and a label with no Shift or Alt stay as they are, text the client hides stays as it is, a label another addon changed stays, a binding refresh or a new button on those bars keeps the short form, and turning this off puts back the label it last shortened while that button still shows the short form.",
	apply = apply,
	events = { "PLAYER_ENTERING_WORLD", "ADDON_LOADED" },
	on_event = function(event, name)
		if event ~= "ADDON_LOADED" or name == "Blizzard_ActionBar" then apply(module.enabled(id)) end
	end,
})
