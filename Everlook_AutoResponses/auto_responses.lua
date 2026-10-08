local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "auto_responses"
local hooked

local resurrection_popups = { "RESURRECT", "RESURRECT_NO_SICKNESS", "RESURRECT_NO_TIMER" }

-- Summons into a starting area or a scenario change where you are, so those
-- stay with the player. The default UI shows its own popup first, so this
-- answers it and closes it.
local function accept_summon(summon_type, skip_starting_area)
	if skip_starting_area or not (Enum and Enum.SummonReason) or summon_type == Enum.SummonReason.Scenario then return end
	if (InCombatLockdown and InCombatLockdown()) or not (C_SummonInfo and C_SummonInfo.ConfirmSummon) then return end
	C_SummonInfo.ConfirmSummon()
	if StaticPopup_Hide then StaticPopup_Hide("CONFIRM_SUMMON") end
end

local function accept_resurrection()
	if not AcceptResurrect then return end
	AcceptResurrect()
	if StaticPopup_Hide then
		for _, popup in ipairs(resurrection_popups) do StaticPopup_Hide(popup) end
	end
end

-- The delete popup enables its Yes button when the edit box holds the
-- confirmation word, so typing it into the box is enough. Yes is still a click.
local function install()
	if hooked or not (StaticPopupDialogs and StaticPopupDialogs.DELETE_GOOD_ITEM and hooksecurefunc) then return end
	hooksecurefunc(StaticPopupDialogs.DELETE_GOOD_ITEM, "OnShow", function(dialog)
		if module.enabled(id) and module.get(id, "easy_delete") and not module.paused() then
			dialog:GetEditBox():SetText(DELETE_ITEM_CONFIRM_STRING)
		end
	end)
	hooked = true
end

module.register({
	addon = addon_name, page = "social", order = 20,
	id = id, name = "Auto responses",
	description = "When a summon confirmation, a resurrection offer, or a good item's delete confirmation appears, this accepts the summon or the resurrection and closes it, or types the delete word, if that choice below is on. This stays quiet while you hold Shift, combat pauses a summon, a starting area or scenario summon stays for you, a resurrection is accepted in combat, releasing your spirit and a spirit healer stay for you, you still click Yes to delete, one already showing waits for the next, a guild invite stays under Block guild invites in Options, Social, and turning this off leaves each of these for you.",
	options = {
		accept_summons = { name = "Accept summons", default = true, description = "Accepts the summon confirmation and closes it while Auto responses is on. Starting area and scenario summons stay for you to answer, every summon stays when the client has no summon reasons, this stays quiet in combat or while you hold Shift, one already showing waits for the next, nothing happens when the client cannot accept it, and turning this off leaves the next one for you." },
		accept_resurrections = { name = "Accept resurrections", default = true, description = "Accepts a resurrection another player offers, including during combat, and closes the offer while Auto responses is on. Releasing your spirit and using a spirit healer stay manual, this stays quiet while you hold Shift, one already showing waits for the next, nothing happens when the client cannot accept it, and turning this off leaves the next one for you." },
		easy_delete = { name = "Fill in the delete confirmation", default = false, description = "When the delete confirmation for a good item appears, this types the confirmation word into the box while Auto responses is on, which removes that safety step. You still click Yes, this stays quiet while you hold Shift, one already showing waits for the next, a delete that does not ask for the word stays as it is, nothing happens when the client has no such box, and turning this off leaves the next one for you." },
	},
	events = { "CONFIRM_SUMMON", "RESURRECT_REQUEST" },
	on_event = function(event, summon_type, skip_starting_area)
		if module.paused() then return end
		if event == "CONFIRM_SUMMON" and module.get(id, "accept_summons") then
			accept_summon(summon_type, skip_starting_area)
		elseif event == "RESURRECT_REQUEST" and module.get(id, "accept_resurrections") then
			accept_resurrection()
		end
	end,
	apply = function(enabled) if enabled then install() end end,
})
