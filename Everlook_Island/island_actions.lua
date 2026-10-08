local Everlook = Everlook

-- Private action contract for Smart Island notifications. Producers pass
-- actions through Everlook.island.notify. This module copies and checks them,
-- then binds the click that is allowed to run.
local actions = {}
Everlook.island_actions = actions

local INTERACTIONS = { buttons = true, expand = true, inbox = true }
local TYPES = { callback = true, item = true, spell = true }
local hooks = {}

local function usable(value)
	if issecretvalue and issecretvalue(value) then return false end
	return value ~= nil
end

local function plain(value, maximum)
	return usable(value) and type(value) == "string" and #value <= maximum and value:find("%S") ~= nil
end

local function integer(value)
	return usable(value) and type(value) == "number" and value == value and value >= 1
		and value <= 9007199254740991 and value % 1 == 0
end

local function identifier(value)
	return plain(value, 32) and value:find("^[%a_][%w_]*$") ~= nil
end

local function call(object, method, ...)
	local fn = object and object[method]
	if type(fn) == "function" then return fn(object, ...) end
end

function actions.use(next_hooks)
	hooks = next_hooks or {}
end

local function copy_action(action)
	if not usable(action) or type(action) ~= "table" or getmetatable(action) ~= nil then return nil, "invalid_action" end
	local id, label, kind = action.id, action.label, action.type
	local item_id, spell_id, on_click, allow = action.item_id, action.spell_id, action.on_click, action.allow_in_combat
	local enabled = action.enabled
	if issecretvalue then
		if issecretvalue(id) or issecretvalue(label) or issecretvalue(kind) or issecretvalue(item_id)
			or issecretvalue(spell_id) or issecretvalue(on_click) or issecretvalue(allow) or issecretvalue(enabled) then
			return nil, "invalid_action"
		end
	end
	if not identifier(id) then return nil, "invalid_action_id" end
	if not plain(label, 48) then return nil, "invalid_action_label" end
	if type(kind) ~= "string" or not TYPES[kind] then return nil, "invalid_action_type" end
	local fields = (on_click ~= nil and 1 or 0) + (item_id ~= nil and 1 or 0) + (spell_id ~= nil and 1 or 0)
	if fields ~= 1 then return nil, "invalid_action" end
	if allow ~= nil and type(allow) ~= "boolean" then return nil, "invalid_action" end
	if enabled ~= nil and type(enabled) ~= "boolean" then return nil, "invalid_action" end
	if kind == "callback" then
		if type(on_click) ~= "function" then return nil, "invalid_action_callback" end
		if item_id ~= nil or spell_id ~= nil then return nil, "invalid_action" end
		return { id = id, label = label, type = kind, callback = on_click, allow_in_combat = allow == true, enabled = enabled ~= false }
	end
	-- A protected button is armed by the secure card and cannot be greyed out from here.
	if allow ~= nil or enabled ~= nil then return nil, "invalid_action" end
	if kind == "item" then
		if not integer(item_id) then return nil, "invalid_action_item" end
		return { id = id, label = label, type = kind, item_id = item_id }
	end
	if not integer(spell_id) then return nil, "invalid_action_spell" end
	return { id = id, label = label, type = kind, spell_id = spell_id }
end

-- Returns a copied spec, or nil and a reason. An actionless payload returns
-- an empty spec so existing notices stay click-through.
function actions.read(payload)
	local interaction, list = payload.interaction, payload.actions
	local item_id, spell_id = payload.item_id, payload.spell_id
	if issecretvalue and issecretvalue(interaction) then return nil, "invalid_interaction" end
	if issecretvalue and issecretvalue(list) then return nil, "invalid_actions" end
	if issecretvalue and issecretvalue(item_id) then return nil, "invalid_item_id" end
	if issecretvalue and issecretvalue(spell_id) then return nil, "invalid_spell_id" end
	if item_id ~= nil and not integer(item_id) then return nil, "invalid_item_id" end
	if spell_id ~= nil and not integer(spell_id) then return nil, "invalid_spell_id" end
	if interaction ~= nil and (type(interaction) ~= "string" or not INTERACTIONS[interaction]) then
		return nil, "invalid_interaction"
	end
	local copied = {}
	if list ~= nil then
		if type(list) ~= "table" or getmetatable(list) ~= nil then return nil, "invalid_actions" end
		for index, action in ipairs(list) do
			if index > 2 then return nil, "invalid_actions" end
			local row, reason = copy_action(action)
			if not row then return nil, reason end
			for earlier = 1, index - 1 do
				if copied[earlier].id == row.id then return nil, "invalid_action_id" end
			end
			copied[index] = row
		end
		if #copied == 0 then return nil, "invalid_actions" end
	end
	if interaction == nil and #copied > 0 then interaction = "buttons" end
	if interaction == "buttons" and #copied == 0 then return nil, "invalid_actions" end
	return { interaction = interaction, actions = copied, item_id = item_id, spell_id = spell_id }
end

-- Turns one callback button of a showing notice on or off. Returns true when it
-- changed, or nil and a reason.
function actions.set_enabled(entry, action_id, enabled)
	if not entry or entry.removed then return nil, "unknown_handle" end
	if type(enabled) ~= "boolean" then return nil, "invalid_enabled" end
	for index = 1, #(entry.actions or {}) do
		local action = entry.actions[index]
		if action.id == action_id then
			if action.type ~= "callback" then return nil, "action_not_toggleable" end
			if (action.enabled ~= false) == enabled then return false end
			action.enabled = enabled
			if hooks.repaint then hooks.repaint() end
			return true
		end
	end
	return nil, "unknown_action"
end

function actions.protected(entry)
	for index = 1, #(entry.actions or {}) do
		local kind = entry.actions[index].type
		if kind == "item" or kind == "spell" then return true end
	end
	return false
end

local function same_action(left, right)
	return left.id == right.id and left.type == right.type and left.label == right.label
		and left.item_id == right.item_id and left.spell_id == right.spell_id
		and left.callback == right.callback and left.allow_in_combat == right.allow_in_combat
end

function actions.different(entry, spec)
	local current = entry.actions or {}
	if #current ~= #spec.actions or entry.interaction ~= spec.interaction then return true end
	if entry.item_id ~= spec.item_id or entry.spell_id ~= spec.spell_id then return true end
	for index = 1, #current do
		if not same_action(current[index], spec.actions[index]) then return true end
	end
	return false
end

function actions.summary(entry)
	local list = {}
	for index, action in ipairs(entry.actions or {}) do
		list[index] = { id = action.id, label = action.label, type = action.type,
			item_id = action.item_id, spell_id = action.spell_id, allow_in_combat = action.allow_in_combat or nil,
			enabled = action.enabled ~= false }
	end
	return list
end

local function combat()
	local locked = InCombatLockdown and InCombatLockdown()
	return not usable(locked) or locked == true
end

function actions.locked()
	return combat()
end

local function current_action(entry, snapshot, generation)
	if not entry or entry.removed or entry.action_generation ~= generation then return nil end
	for index = 1, #(entry.actions or {}) do
		local action = entry.actions[index]
		if action.id == snapshot.id and same_action(action, snapshot) then return action end
	end
end

local function report(action, err)
	local detail = plain(err, 1024) and err or "action failed"
	local handler = geterrorhandler and geterrorhandler()
	if type(handler) == "function" then handler("Everlook Smart Island (action " .. action.id .. "): " .. detail) end
end

function actions.invoke(entry, snapshot, generation)
	local action = current_action(entry, snapshot, generation)
	if not action or action.type ~= "callback" then return false end
	if action.enabled == false then return false end
	if combat() and not action.allow_in_combat then return false end
	local ok, err = pcall(action.callback, entry.id, action.id)
	if not ok then report(action, err) end
	return ok
end

-- The game's own button template brings its art, hover and press states and its
-- own label. Where the template is missing (the test world) a plain font string
-- stands in. Either way button.label takes SetText.
local BUTTON_TEMPLATE = "UIPanelButtonTemplate"

local function skin(button)
	if type(button.SetText) == "function" then
		button.label = { SetText = function(_, text) button:SetText(text) end }
	else
		local label = call(button, "CreateFontString", nil, "OVERLAY", "GameFontHighlightSmall")
		call(label, "SetPoint", "CENTER")
		button.label = label
	end
end

local function ensure_button(node, index)
	node.action_buttons = node.action_buttons or {}
	local button = node.action_buttons[index]
	if button then return button end
	button = CreateFrame("Button", nil, node.frame, BUTTON_TEMPLATE)
	call(button, "SetSize", 120, 22)
	-- Above everything else on the card, so nothing drawn there takes the click.
	call(button, "SetFrameLevel", (call(node.frame, "GetFrameLevel") or 51) + 4)
	call(button, "RegisterForClicks", "LeftButtonUp", "RightButtonUp")
	skin(button)
	node.action_buttons[index] = button
	return button
end

local function hide_buttons(node)
	for _, button in ipairs(node.action_buttons or {}) do call(button, "Hide") end
end

local function bind_hover(target, entry, generation)
	call(target, "SetScript", "OnEnter", function()
		if target.bound_entry == entry and entry.action_generation == generation and not entry.removed and hooks.hover then
			hooks.hover(entry, true)
		end
	end)
	call(target, "SetScript", "OnLeave", function()
		if target.bound_entry == entry and hooks.hover then hooks.hover(entry, false) end
	end)
end

-- Toast and inbox rows call this after measuring text. Item and spell clicks
-- are owned by the secure card, so those buttons stay hidden here.
function actions.paint(node, entry, compact)
	if not node or not node.frame or not CreateFrame then return 0 end
	local show = entry.actions and #entry.actions > 0 and (not compact or entry.interaction == "buttons")
	local callbacks = {}
	if show then
		for index = 1, #entry.actions do
			if entry.actions[index].type == "callback" then callbacks[#callbacks + 1] = { action = entry.actions[index], at = index } end
		end
	end
	if #callbacks == 0 then
		hide_buttons(node)
		if compact and node.group then
			local clickable = entry.interaction == "expand"
			call(node.frame, "EnableMouse", clickable)
			if clickable then
				local generation = entry.action_generation
				call(node.frame, "RegisterForClicks", "LeftButtonUp")
				call(node.frame, "SetScript", "OnClick", function()
					if node.entry == entry and entry.action_generation == generation and not entry.removed and hooks.open then
						hooks.open(entry)
					end
				end)
				bind_hover(node.frame, entry, generation)
				node.frame.bound_entry = entry
			else
				call(node.frame, "SetScript", "OnClick", nil)
				call(node.frame, "SetScript", "OnEnter", nil)
				call(node.frame, "SetScript", "OnLeave", nil)
				node.frame.bound_entry = nil
			end
		end
		return 0
	end
	local generation = entry.action_generation
	if compact and node.group then
		call(node.frame, "EnableMouse", true)
		call(node.frame, "SetScript", "OnClick", nil)
		node.frame.bound_entry = entry
		bind_hover(node.frame, entry, generation)
	end
	for index = 1, #callbacks do
		local action = callbacks[index].action
		local button = ensure_button(node, index)
		button.bound_entry, button.action_id = entry, action.id
		call(button.label, "SetText", action.label)
		call(button, "ClearAllPoints")
		call(button, "SetPoint", "BOTTOMLEFT", node.frame, "BOTTOMLEFT", 40 + (callbacks[index].at - 1) * 128, 8)
		call(button, "SetEnabled", action.enabled ~= false)
		call(button, "SetAlpha", action.enabled ~= false and 1 or 0.5)
		call(button, "Show")
		call(button, "SetScript", "OnClick", function(_, button_name)
			if button_name == "RightButton" then
				if hooks.dismiss and not entry.removed then hooks.dismiss(entry.id) end
				return
			end
			actions.invoke(entry, action, generation)
		end)
		bind_hover(button, entry, generation)
	end
	for index = #callbacks + 1, #(node.action_buttons or {}) do call(node.action_buttons[index], "Hide") end
	return 30
end

local pool = {}

local function release_card(card)
	if not card or combat() then return false end
	card.armed, card.entry = false, nil
	call(card.frame, "Hide")
	for index = 1, #card.buttons do
		call(card.buttons[index], "Hide")
		call(card.buttons[index], "SetAttribute", "type", nil)
		call(card.buttons[index], "SetAttribute", "item", nil)
		call(card.buttons[index], "SetAttribute", "spell", nil)
		card.buttons[index].bound_generation = nil
	end
	return true
end

local function acquire_card()
	for index = 1, #pool do
		if not pool[index].entry then return pool[index] end
	end
	if not CreateFrame or not UIParent then return nil end
	local frame = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
	call(frame, "SetFrameStrata", "HIGH")
	call(frame, "SetFrameLevel", 80)
	call(frame, "Hide")
	local buttons = {}
	for index = 1, 2 do
		local button = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate, " .. BUTTON_TEMPLATE)
		call(button, "SetSize", 120, 22)
		call(button, "RegisterForClicks", "LeftButtonUp")
		skin(button)
		buttons[index] = button
	end
	local card = { frame = frame, buttons = buttons }
	local function dismiss_right(_, button)
		if button ~= "RightButton" then return end
		local entry = card.entry
		if not entry or entry.removed then return end
		entry.secure_dismissed = true
		if combat() then return end
		if hooks.dismiss then hooks.dismiss(entry.id) end
	end
	call(frame, "RegisterForClicks", "RightButtonUp")
	call(frame, "SetPassThroughButtons", "LeftButton")
	if frame.HookScript then
		frame:HookScript("OnMouseUp", dismiss_right)
		frame:HookScript("OnClick", dismiss_right)
	else
		call(frame, "SetScript", "OnMouseUp", dismiss_right)
	end
	pool[#pool + 1] = card
	return card
end

function actions.place(entry, origin)
	if not entry or entry.removed or not actions.protected(entry) then return end
	if entry.frozen or combat() then
		if not (entry.secure_card and entry.secure_card.armed) then entry.deferred = true end
		return
	end
	local card = entry.secure_card or acquire_card()
	if not card or not origin then return end
	entry.secure_card, entry.deferred = card, nil
	card.entry, card.armed = entry, true
	call(card.frame, "SetScale", origin.scale or 1)
	call(card.frame, "ClearAllPoints")
	call(card.frame, "SetPoint", "TOP", UIParent, "TOP", origin.x or 0, origin.y or 0)
	call(card.frame, "SetSize", origin.width or 64, origin.height or 44)
	call(card.frame, "Show")
	for index = 1, #entry.actions do
		local action = entry.actions[index]
		local button = card.buttons[index]
		if button then call(button, "Hide") end
		if button and (action.type == "item" or action.type == "spell") then
			if button.bound_generation ~= entry.action_generation or button.bound_id ~= action.id then
				call(button, "SetAttribute", "type", action.type)
				if action.type == "item" then
					call(button, "SetAttribute", "item", "item:" .. action.item_id)
					call(button, "SetAttribute", "spell", nil)
				else
					call(button, "SetAttribute", "spell", action.spell_id)
					call(button, "SetAttribute", "item", nil)
				end
				button.bound_generation, button.bound_id = entry.action_generation, action.id
			end
			button.action_id = action.id
			call(button.label, "SetText", action.label)
			call(button, "ClearAllPoints")
			call(button, "SetPoint", "BOTTOMLEFT", card.frame, "BOTTOMLEFT", 40 + (index - 1) * 128, 8)
			call(button, "Show")
		end
	end
end

function actions.release(entry)
	if not entry or not entry.secure_card then return true end
	if entry.frozen or combat() then return false end
	local card = entry.secure_card
	entry.secure_card = nil
	return release_card(card)
end

local function freeze_entry(entry)
	if not entry or entry.removed or not entry.secure_card or not entry.secure_card.armed then
		if entry and actions.protected(entry) and not entry.removed then entry.deferred = true end
		return
	end
	entry.frozen = true
	entry.deferred = nil
	local now = hooks.now and hooks.now() or 0
	local remaining = entry.remaining
	if entry.expires_at then remaining = entry.expires_at - now end
	if type(remaining) == "number" then
		entry.remaining = math.max(0, remaining)
		entry.frozen_until = now + entry.remaining
	end
	entry.timer, entry.expires_at = nil, nil
end

function actions.freeze()
	local seen = {}
	local function once(entry)
		if not entry or seen[entry] then return end
		seen[entry] = true
		freeze_entry(entry)
	end
	if hooks.each then hooks.each(once) end
	for index = 1, #pool do once(pool[index].entry) end
	if hooks.repaint then hooks.repaint() end
end

-- While the pointer is on a toast, the toast stays: its clock stops, and a toast
-- already on its way out comes back. When the pointer leaves, the clock starts
-- again from the toast's full time, not from what was left.
function actions.hover(entry, inside, now, open, schedule)
	if not entry or entry.removed then return end
	entry.hover_count = entry.hover_count or 0
	if inside then
		entry.hover_count = entry.hover_count + 1
		if entry.hover_count > 1 then return end
		entry.timer, entry.expires_at, entry.remaining = nil, nil, nil
		if entry.phase == "exiting" and hooks.revive then hooks.revive(entry) end
		return
	end
	entry.hover_count = math.max(0, entry.hover_count - 1)
	if entry.hover_count > 0 or not entry.node or entry.phase == "exiting" or open then return end
	schedule(entry, entry.duration)
end

function actions.hold(entries, now)
	for index = 1, #entries do
		local entry = entries[index]
		local basis = entry.expires_at or (entry.remaining and now + entry.remaining)
		entry.remaining = math.max(0, (basis or now + entry.duration) - now)
		entry.timer, entry.expires_at = nil, nil
		entry.hover_count = 0
	end
end

function actions.unhold(entries, schedule)
	for index = 1, #entries do
		local entry = entries[index]
		schedule(entry, entry.remaining or entry.duration)
	end
end

function actions.arm(entry, seconds, open, now, start)
	seconds = seconds or entry.duration
	entry.timer, entry.expires_at = nil, nil
	if (entry.hover_count and entry.hover_count > 0) or open then
		entry.remaining = seconds
		return
	end
	entry.remaining = nil
	local token = {}
	entry.timer, entry.expires_at = token, now + seconds
	start(token, seconds)
end

function actions.sync(entry, open, phase, motion, origin)
	if not entry or entry.removed or entry.frozen or not actions.protected(entry) then return end
	if open or phase ~= "visible" then
		actions.release(entry)
	elseif not motion then
		actions.place(entry, origin)
	end
end

function actions.reconcile()
	if combat() then return end
	local pending, seen = {}, {}
	local function collect(entry)
		if not entry or seen[entry] then return end
		seen[entry] = true
		if entry.frozen or entry.deferred or entry.secure_dismissed then pending[#pending + 1] = entry end
	end
	if hooks.each then hooks.each(collect) end
	for index = 1, #pool do collect(pool[index].entry) end
	for index = 1, #pending do
		local entry = pending[index]
		local now = hooks.now and hooks.now() or 0
		local expired = entry.frozen_until and now >= entry.frozen_until
		local drop = entry.secure_dismissed or entry.removed or expired or (hooks.enabled and not hooks.enabled())
		local card = entry.secure_card
		entry.frozen, entry.frozen_until, entry.deferred = nil, nil, nil
		if drop then
			entry.secure_card, entry.secure_dismissed = nil, nil
			if card then release_card(card) end
			if hooks.dismiss and not entry.removed then hooks.dismiss(entry.id) end
		elseif hooks.resume then
			hooks.resume(entry)
		end
	end
	if hooks.repaint then hooks.repaint() end
end

if CreateFrame then
	local watcher = CreateFrame("Frame")
	call(watcher, "RegisterEvent", "PLAYER_REGEN_DISABLED")
	call(watcher, "RegisterEvent", "PLAYER_REGEN_ENABLED")
	call(watcher, "SetScript", "OnEvent", function(_, event)
		if event == "PLAYER_REGEN_DISABLED" then actions.freeze() else actions.reconcile() end
	end)
end
