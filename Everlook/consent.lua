local _, Everlook = ...

Everlook.consent = {}

-- Everlook records nothing until the player has said yes. The question is one
-- stock dialog, asked once per install, and it never interrupts: not in combat,
-- not during a cinematic, not over another dialog. Escape and the No button
-- both mean no. A dialog that something else closes (a cinematic, another
-- dialog) is not an answer, so it comes back at the next login.
local SETTLE = 6
local RETRY = 8
local TRIES = 10

local DIALOG = "EVERLOOK_COLLECT"
local TEXT = "Everlook can record what you see while you play: creatures, items, quests, vendors and where you saw them. It saves them to a file on your computer, with no character name, realm or guild. If you are signed in to the Everlook app, the app sends that file to everlook.ing, where facts from many players are checked against each other and shown to everyone.\n\nRecord what you see?\n\nYou can change this at any time. Type /everlook and turn Record world data on or off."

local function in_cinematic()
	if type(InCinematic) == "function" and InCinematic() then return true end
	return type(CinematicFrame) == "table" and type(CinematicFrame.IsShown) == "function" and CinematicFrame:IsShown() or false
end

local function another_dialog_shown()
	if type(StaticPopup_ForEachShownDialog) ~= "function" then return false end
	local found = false
	StaticPopup_ForEachShownDialog(function(dialog)
		if dialog and dialog.which ~= DIALOG then found = true end
	end)
	return found
end

-- Why the question cannot be shown now, or nil when it can.
function Everlook.consent.blocked()
	if type(StaticPopup_Show) ~= "function" or type(StaticPopupDialogs) ~= "table" then return "no dialogs" end
	if type(InCombatLockdown) == "function" and InCombatLockdown() then return "combat" end
	if in_cinematic() then return "cinematic" end
	if another_dialog_shown() then return "dialog" end
	return nil
end

local function answer(on)
	Everlook.config.set_collecting(on)
	if Everlook.say then
		Everlook.say(on and "Recording is on. Turn it off with /everlook." or "Recording is off. Turn it on with /everlook.")
	end
end

local function define()
	StaticPopupDialogs[DIALOG] = {
		text = TEXT,
		button1 = "Record",
		button2 = "Don't record",
		OnAccept = function() answer(true) end,
		OnCancel = function(_, _, reason)
			-- "override" is the game closing it for something else, not the player's answer.
			if reason == "clicked" or reason == nil then answer(false) end
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
end

function Everlook.consent.show()
	if Everlook.consent.blocked() then return false end
	define()
	StaticPopup_Show(DIALOG)
	return true
end

-- Asks once the first time the player is in the world, then waits for a quiet moment.
local function ask(tries)
	if Everlook.config.asked() then return end
	if not Everlook.consent.show() and tries > 1 and type(C_Timer) == "table" and type(C_Timer.After) == "function" then
		C_Timer.After(RETRY, function() ask(tries - 1) end)
	end
end

function Everlook.consent.start()
	if Everlook.config.asked() or type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then return end
	C_Timer.After(SETTLE, function() ask(TRIES) end)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	Everlook.consent.start()
	-- The journey starts from here too, so it listens to nothing until the player is in the world and has said yes.
	if Everlook.journey then
		Everlook.journey.start()
	end
end)
