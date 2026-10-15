local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "reward_marks"

-- The game's own coin, drawn in the corner of the reward choice a vendor pays the most for. It is drawn on
-- Blizzard's reward buttons after the game has filled them, and never moves or replaces one.
local COIN = "Interface\\MoneyFrame\\UI-GoldIcon"
-- An item the client has not cached has no price yet. The pass asks again a few times, then gives up.
local RETRIES, WAIT = 6, 0.3

local hooked = false
-- Every pass belongs to one showing of the rewards. A newer showing, or turning the module off, ends the older.
local generation = 0
local marks = setmetatable({}, { __mode = "k" })

local function choice_buttons()
	local frame = QuestInfoFrame and QuestInfoFrame.rewardsFrame
	local list = {}
	for _, button in ipairs(frame and frame.RewardButtons or {}) do
		if button.type == "choice" and button.objectType == "item" and button:IsShown() then list[#list + 1] = button end
	end
	return list
end

-- What a vendor pays for the whole stack of one choice, or nil while the client does not know it yet.
local function price_of(index)
	local in_log = QuestInfoFrame.questLog
	local info = in_log and GetQuestLogChoiceInfo or GetQuestItemInfo
	local name, _, count, _, _, item_id
	if in_log then name, _, count, _, _, item_id = info(index) else name, _, count, _, _, item_id = info("choice", index) end
	local link = (in_log and GetQuestLogItemLink or GetQuestItemLink)("choice", index)
	if not name or not (link or item_id) or not C_Item or not C_Item.GetItemInfo then return nil end
	local sell = select(11, C_Item.GetItemInfo(link or item_id))
	if type(sell) ~= "number" or (issecretvalue and issecretvalue(sell)) then return nil end
	return sell * (type(count) == "number" and count > 0 and count or 1)
end

local function mark_of(button)
	local mark = marks[button]
	if not mark then
		mark = button:CreateTexture(nil, "OVERLAY")
		mark:SetTexture(COIN)
		mark:SetSize(14, 14)
		mark:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -2)
		marks[button] = mark
	end
	return mark
end

local function show_only(buttons, best)
	for _, button in ipairs(buttons) do
		if button == best then mark_of(button):SetShown(true) elseif marks[button] then marks[button]:SetShown(false) end
	end
end

local function pass(attempt, token)
	if token ~= generation or not module.enabled(id) or not QuestInfoFrame then return end
	local buttons = choice_buttons()
	if #buttons < 2 then
		show_only(buttons, nil)
		return
	end
	local best, best_price, tied, unknown = nil, 0, false, false
	for _, button in ipairs(buttons) do
		local price = price_of(button:GetID())
		if price == nil then
			unknown = true
		elseif price > best_price then
			best, best_price, tied = button, price, false
		elseif price == best_price and price > 0 then
			tied = true
		end
	end
	if unknown then
		-- A mark on a partial answer could be wrong, so none is drawn until every price is known.
		show_only(buttons, nil)
		if attempt < RETRIES and C_Timer and C_Timer.After then
			C_Timer.After(WAIT, function() pass(attempt + 1, token) end)
		end
		return
	end
	show_only(buttons, (not tied and best_price > 0) and best or nil)
end

local function schedule()
	generation = generation + 1
	local token = generation
	if C_Timer and C_Timer.After then C_Timer.After(0, function() pass(0, token) end) end
end

local function apply(enabled)
	if not enabled then
		generation = generation + 1
		for _, mark in pairs(marks) do mark:SetShown(false) end
		return
	end
	if hooked or type(hooksecurefunc) ~= "function" or type(QuestInfo_ShowRewards) ~= "function" then return end
	hooksecurefunc("QuestInfo_ShowRewards", schedule)
	hooked = true
end

module.register({
	addon = addon_name, page = "quests", order = 60,
	id = id, name = "Reward marks",
	description = "Puts a small coin in the corner of the quest reward choice that a vendor pays the most for, on the quest window and in the quest log. A single reward, a tie for the best price, rewards a vendor does not buy, and a choice whose price the game has not loaded yet get no coin, the coin never changes what the window offers, and turning this off takes the coin away.",
	apply = apply,
})
