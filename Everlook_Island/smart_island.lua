local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "smart_island"
local grid = Everlook.island_grid
local island_section = Everlook.island_section
local island_blocks = Everlook.island_blocks
local island_reaction = Everlook.island_reaction
local island_capsule = Everlook.island_capsule
local island_summary = Everlook.island_summary
local island_row = Everlook.island_row

BINDING_HEADER_EVERLOOK = BINDING_HEADER_EVERLOOK or "Everlook"
BINDING_NAME_EVERLOOK_SMART_ISLAND = "Open smart island"
BINDING_NAME_EVERLOOK_SMART_ISLAND_DISMISS = "Dismiss top island notice"

local ACTION = "EVERLOOK_SMART_ISLAND"
local HOLD = 0.2
local LIST_MAX, STATUS_MAX = 30, 10 -- LIST_MAX sizes the pooled inbox rows; the inbox size option sets how many show.
local CLOSED_W, CLOSED_H = 64, 36
local QUEUE_MAX = 5
local TOAST_GAP = 6
local MOTION = { enter = 0.2, exit = 0.15, open = 0.15, close = 0.125, handoff = 0.125, complete = 0.15 }
local ENTER_TIME, EXIT_TIME = MOTION.enter, MOTION.exit
-- Two columns when there is a quest to show beside the notifications, one when there is not.
local OPEN_W, NARROW_W = grid.widths.two, grid.widths.one
local COLORS = {
	primary = { 245 / 255, 247 / 255, 250 / 255, 1 },
	secondary = { 174 / 255, 182 / 255, 195 / 255, 1 },
	accent = { 173 / 255, 118 / 255, 239 / 255, 1 },
	success = { 0.5, 0.9, 0.65, 1 },
	-- Amber, so a warning is not mistaken for the gold of a quest.
	warning = { 1, 0.62, 0.25, 1 },
	error = { 1, 0.5, 0.5, 1 },
	muted = { 136 / 255, 145 / 255, 160 / 255, 1 },
}
-- WoW fonts have one weight, so a role is a size and a tone. Display is the
-- level, a title names a thing, text lists things, body explains it, a caption names a figure and
-- a heading names a section. Headings are set in capitals through shell.heading.
local ROLES = {
	display = { "GameFontHighlightLarge", COLORS.primary },
	title = { "GameFontHighlightMedium", COLORS.primary },
	text = { "GameFontHighlight", COLORS.primary },
	body = { "GameFontHighlight", COLORS.secondary },
	caption = { "GameFontHighlightSmall", COLORS.secondary },
	heading = { "GameFontHighlightSmall", COLORS.muted },
}
local ART = "Interface\\AddOns\\Everlook_Island\\assets\\"
local EMPTY_HINT = "Loot, mail, quests and warnings from Everlook and other addons collect here."

local island = {}
Everlook.smart_island = island

local frame, summary, closed_text, surface
local inbox, inbox_content, footer, empty_text, unread_text
local quest_scroll, quest_content
local clear_button, undo_button, new_button
local scroll_offset, scroll_height, content_height = 0, 0, 0
local undo_state, close_token
local scroll_anchor, follow_end
local inspect_rows
local history_nodes = {}
local summary_height = 0
local ticker
-- What the last paint showed, so the once-a-second tick repaints only when it changed.
local painted = {}
local pinned, hovering, holding, hold_was_pinned, hold_at
local was_open
local active_toasts, toast_queue, toast_pool = {}, {}, {}
local paint
local mark_removed
local next_notice_id = 0
-- Sections share the notices' counter, so one number names one thing.
local sections = island_section.new_store(function()
	next_notice_id = next_notice_id + 1
	return next_notice_id
end)
local notices = {}
local statuses = {}
local status_node
local status_height = 0
local root_hover = {}
local expanded, expanded_surface, resting
local preview_group, preview_fade
local preview_targets, preview_translations, preview_controls = {}, {}, {}
local preview = { phase = "settled", y = 0, alpha = 0, open = false }
local readout = {}
local quest_context = Everlook.island_quests
local vitals = Everlook.island_vitals
local actions = Everlook.island_actions
local compact_api = Everlook.island_capsule
local island_surface = Everlook.island_surface
local island_notice = Everlook.island_notice
local island_inbox = Everlook.island_inbox
local island_toasts = Everlook.island_toasts
local shell = { quest_offset = 0, quest_height = 0, stats = Everlook.island_stats, scroll_api = Everlook.island_scroll, width = CLOSED_W, height = CLOSED_H, from_w = CLOSED_W, to_w = CLOSED_W, from_h = CLOSED_H, to_h = CLOSED_H }
local resting_slots = {}
-- Background statuses: they hold the capsule when nothing with more to say does, and are never history, a toast or timed.
shell.backgrounds = {}
shell.resting = {}
-- The open summary spaces everything from these steps. A gap inside a group is
-- `within`, a gap between siblings `near`, and a gap between groups `section`,
-- which is at least twice the one inside. `edge` is the inset the rows below share.
-- `lead` is the gap between a 16 mark and its text, so every text column sits 22 from the
-- content edge, as the capsule's does. `block` is the space between a header and what it
-- heads, `control` a button's height, `link` a small button's, `row` a line of a list (a row with a
-- button is `link` high), and `step` a wheel notch.
shell.space = { within = 4, near = 8, section = 16, edge = 12, ring = 28, icon = 14, mark = 16, capsule_ring = 14, head = 32, pane_min = 48, pane_max = 360, pane_floor = 200,
	lead = 6, block = 24, control = 28, link = 24, row = 20, step = 40 }
-- The surface's corner radius: the capsule, a card or panel, and a control.
shell.radius = { capsule = 14, panel = 12, control = 8 }
-- A notice card, as a toast or an inbox row. The text column is the inset, the icon and the
-- gap `near` between them.
shell.card = { inset = 12, icon = 20, text = 40, icon_top = 12, label_top = 10, accent_x = 6, accent_top = 9, bar = 3,
	wash_x = 4, wash_y = 2, min_height = 44, after_detail = 4, after_meta = 10, after_routine = 6, after_bar = 8 }
-- The quest card and plan are sections the quest source pushes. A refresh pushes them again if what
-- they say has changed, and returns whether it did, which is when an open island has been redrawn.
local function refresh_quests(force)
	shell.quest_pushed = false
	quest_context.refresh(force)
	return shell.quest_pushed
end

-- The quest events arrive in bursts. The first one scans at once, and the rest
-- inside the window collapse into one scan when it ends.
local QUEST_SCAN_WINDOW = 0.5
local last_quest_scan, quest_scan_waiting
local function refresh_quests_from_event()
	local time = GetTime and GetTime() or 0
	if not last_quest_scan or time - last_quest_scan >= QUEST_SCAN_WINDOW or not (C_Timer and C_Timer.After) then
		last_quest_scan = time
		refresh_quests(true)
		return true
	end
	if quest_scan_waiting then return false end
	quest_scan_waiting = true
	C_Timer.After(QUEST_SCAN_WINDOW - (time - last_quest_scan), function()
		quest_scan_waiting = nil
		if not module.enabled(id) then return end
		last_quest_scan = GetTime and GetTime() or 0
		refresh_quests(true)
		if paint then paint() end
	end)
	return false
end
function island.pin_quest(quest_id)
	local changed = quest_context.pin(quest_id)
	if changed then shell.push_quests() end
	if changed and paint then paint() end
	return changed
end

local function usable(value)
	if issecretvalue and issecretvalue(value) then return false end
	return value ~= nil
end

local function finite(value)
	return usable(value) and type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function call(object, method, ...)
	local fn = object and object[method]
	if type(fn) == "function" then return fn(object, ...) end
end

-- Headings are set in capitals, which a font cannot do for us.
-- Sets a label to a font role: its font and its tone.
shell.role = function(label, role)
	local font, tone = unpack(ROLES[role] or ROLES.text)
	call(label, "SetFontObject", font)
	call(label, "SetTextColor", unpack(tone))
end

shell.heading = function(label, text, marker)
	call(label, "SetText", (marker or "") .. string.upper(text))
end

-- A colour as the inline code a font string reads.
shell.tone = function(color)
	return string.format("|cff%02x%02x%02x", math.floor(color[1] * 255 + 0.5), math.floor(color[2] * 255 + 0.5), math.floor(color[3] * 255 + 0.5))
end

-- A ring that fills clockwise to a fraction, in place of a bar. The track is the
-- whole ring, dim. The fill is a cooldown held at a percentage, as the game's own
-- honor ring is, so it needs no art but the ring.
shell.make_ring = function(parent, size)
	local ring = { size = size }
	ring.track = call(parent, "CreateTexture", nil, "BACKGROUND")
	-- A small ring has its own art, drawn near the size it shows at: the large one, shrunk to 14,
	-- blurs, and an even stroke of two pixels needs its own proportions.
	local art = ART .. (size <= 20 and "island_ring_small.tga" or "island_ring.tga")
	call(ring.track, "SetTexture", art)
	call(ring.track, "SetVertexColor", 1, 1, 1, 0.14)
	call(ring.track, "SetSize", size, size)
	ring.fill = CreateFrame("Cooldown", nil, parent)
	call(ring.fill, "SetSize", size, size)
	call(ring.fill, "EnableMouse", false)
	-- Addons that print a countdown on every cooldown leave this one alone.
	ring.fill.noCooldownCount = true
	call(ring.fill, "SetSwipeTexture", art)
	call(ring.fill, "SetReverse", true)
	call(ring.fill, "SetDrawEdge", false)
	call(ring.fill, "SetDrawBling", false)
	call(ring.fill, "SetHideCountdownNumbers", true)
	call(ring.track, "Hide")
	call(ring.fill, "Hide")
	return ring
end

shell.place_ring = function(ring, relative, x, y)
	for _, part in ipairs({ ring.track, ring.fill }) do
		call(part, "ClearAllPoints")
		call(part, "SetPoint", "TOPLEFT", relative, "TOPLEFT", x, -y)
	end
end

-- Sets the ring on the line of another region, `gap` before that region's `point`
-- (its left edge unless said otherwise).
shell.chain_ring = function(ring, following, gap, point)
	for _, part in ipairs({ ring.track, ring.fill }) do
		call(part, "ClearAllPoints")
		call(part, "SetPoint", "RIGHT", following, point or "LEFT", -gap, 0)
	end
end

shell.set_ring = function(ring, fraction, color)
	fraction = math.max(0, math.min(0.999, fraction))
	call(ring.track, "Show")
	call(ring.fill, "Show")
	call(ring.fill, "SetSwipeColor", color[1], color[2], color[3], 1)
	call(ring.fill, "Pause")
	call(ring.fill, "SetCooldown", (GetTime and GetTime() or 0) - 100 * fraction, 100)
end

-- The ring with nothing in it: the dim track only.
shell.track_ring = function(ring)
	call(ring.track, "Show")
	call(ring.fill, "Hide")
end

shell.hide_ring = function(ring)
	call(ring.track, "Hide")
	call(ring.fill, "Hide")
end


local function screen_size(method)
	return (call(UIParent, method) or (method == "GetWidth" and OPEN_W + 32 or 1080)) / (module.get(id, "size") / 100)
end

-- The battleground score and similar widgets sit at the top center. When one is
-- showing, the pill drops below it instead of covering it.
local function widget_clearance()
	if not module.get(id, "avoid_top_widgets") then return 0 end
	local widget = UIWidgetTopCenterContainerFrame
	if not widget or call(widget, "IsShown") ~= true then return 0 end
	local bottom, edge = call(widget, "GetBottom"), call(UIParent, "GetTop")
	if not finite(bottom) or not finite(edge) or edge - bottom < 1 then return 0 end
	return (edge - bottom) / (module.get(id, "size") / 100) + 8
end

local function place_frame(width, height)
	local available_x = math.max(0, (screen_size("GetWidth") - width) / 2 - 8)
	local available_y = math.max(8, screen_size("GetHeight") - height - 8)
	local x = math.max(-available_x, math.min(available_x, module.get(id, "position_x")))
	local y = math.min(available_y, math.max(module.get(id, "position_top"), widget_clearance()))
	call(frame, "SetScale", module.get(id, "size") / 100)
	call(frame, "ClearAllPoints")
	call(frame, "SetPoint", "TOP", UIParent, "TOP", x, -y)
end

function island.reset_position()
	module.set(id, "position_x", 0)
	module.set(id, "position_top", 12)
end

-- A preset sets what the player chooses to see. Placement, size, opacity and
-- the key stay as they are. Each option carries its value under each preset,
-- so the options a feed addon adds follow the preset too.
local PRESET_ORDER = { "Quiet", "Standard", "Informative" }
local registered

function island.apply_preset(name)
	local known = false
	for _, preset in ipairs(PRESET_ORDER) do known = known or preset == name end
	if not known or not registered then return false end
	for key, option in pairs(registered.options) do
		local value = option.presets and option.presets[name]
		if value ~= nil then module.set(id, key, value) end
	end
	return true
end

function island.preview_notifications()
	if not module.enabled(id) then return false end
	island.notify({ source = "everlook.preview", key = "warning", text = "Bag space is running low", severity = "warning", kind = "bags", persist = true })
	island.notify({ source = "everlook.preview", key = "coins", text = "Money received", money = 12345, severity = "success", kind = "money" })
	island.notify({ source = "everlook.preview", key = "long", text = "A longer notification stays readable in the inbox when there is more to say.", detail = "Open the Island to read the full message." })
	return true
end

local function clock_now()
	return GetTime and GetTime() or 0
end

local function active_status()
	return statuses[#statuses]
end

local function remove_status(entry)
	entry.status_timer = nil
	for index = #statuses, 1, -1 do
		if statuses[index] == entry then table.remove(statuses, index) end
	end
end

local function unread_count()
	return island_inbox.unread(notices)
end

local function bound_history()
	island_inbox.evict(notices, module.get(id, "inbox_size"))
end

-- The role is a name from ROLES. The older `true` means body, and none means title.
local function make_label(parent, justify, role)
	local font, tone = unpack(ROLES[role == true and "body" or role or "title"])
	local label = call(parent, "CreateFontString", nil, "OVERLAY", font)
	call(label, "SetJustifyH", justify or "LEFT")
	call(label, "SetTextColor", unpack(tone))
	call(label, "SetWordWrap", true)
	call(label, "SetNonSpaceWrap", true)
	call(label, "SetSpacing", 4)
	call(label, "SetHeight", 0)
	return label
end

local function make_visual(parent, belongs_to_preview)
	local visual = CreateFrame("Frame", nil, parent)
	call(visual, "EnableMouse", false)
	call(visual, "SetAllPoints", parent)
	if belongs_to_preview then preview_targets[#preview_targets + 1] = { frame = visual, parent = parent } end
	return visual
end

-- A row in the notifications list is set smaller than a toast, which is read at a glance,
-- and lights up under the pointer.
local function make_content(parent, belongs_to_preview, row)
	local visual = make_visual(parent, belongs_to_preview)
	local node = { frame = parent, visual = visual, label = make_label(visual, "LEFT", row and "text"),
		detail = make_label(visual, "LEFT", row and "caption" or true), meta = make_label(visual, "LEFT", row and "caption" or true), row = row }
	if row then
		local wash = call(visual, "CreateTexture", nil, "BACKGROUND")
		call(wash, "SetPoint", "TOPLEFT", visual, "TOPLEFT", shell.card.wash_x, -shell.card.wash_y)
		call(wash, "SetPoint", "BOTTOMRIGHT", visual, "BOTTOMRIGHT", -shell.card.wash_x, shell.card.wash_y)
		call(wash, "SetColorTexture", 1, 1, 1, 0.06)
		call(wash, "Hide")
		node.on_hover = function(inside) call(wash, inside and "Show" or "Hide") end
	end
	-- A slim bar down the left edge carries the severity, so a warning reads at a
	-- glance without leaning on the text colour.
	node.accent = call(visual, "CreateTexture", nil, "ARTWORK")
	call(node.accent, "Hide")
	node.icon = call(visual, "CreateTexture", nil, "OVERLAY")
	call(node.icon, "SetSize", shell.card.icon, shell.card.icon)
	call(node.icon, "SetPoint", "TOPLEFT", visual, "TOPLEFT", shell.card.inset, -shell.card.icon_top)
	call(node.label, "SetPoint", "TOPLEFT", visual, "TOPLEFT", shell.card.text, -shell.card.label_top)
	node.progress = CreateFrame("StatusBar", nil, visual)
	call(node.progress, "EnableMouse", false)
	call(node.progress, "SetStatusBarTexture", ART .. "island_white.tga")
	call(node.progress, "SetStatusBarColor", unpack(COLORS.accent))
	call(node.progress, "SetMinMaxValues", 0, 1)
	return node
end

local function notice_mark(icon, entry)
	if icon == "generic" and entry and entry.item_id then return { item_id = entry.item_id } end
	if icon == "generic" and entry and entry.spell_id then return { spell_id = entry.spell_id } end
	return icon or "generic"
end

local function paint_icon(texture, icon, entry)
	if compact_api and compact_api.apply then compact_api.apply(texture, notice_mark(icon, entry)) end
end

function island.age_text(seconds)
	if seconds < 60 then return "Just now" end
	local minutes = math.floor(seconds / 60)
	if minutes < 60 then return minutes .. "m ago" end
	local hours = math.floor(minutes / 60)
	minutes = minutes % 60
	return (minutes == 0 and hours .. "h" or hours .. "h " .. minutes .. "m") .. " ago"
end

local function content_size(node, entry, width, compact, activity)
	local card = shell.card
	paint_icon(node.icon, entry.icon, entry)
	local text_width = width - card.text - card.inset
	call(node.label, "SetWidth", text_width)
	call(node.label, "SetMaxLines", 0)
	local primary = entry.runs and compact_api.compile(entry.runs, vitals.rich) or entry.text
	if (entry.count or 1) > 1 then primary = (primary or "") .. " ×" .. entry.count end
	call(node.label, "SetText", primary or entry.text)
	-- A row you have read steps back from one you have not.
	if node.row then call(node.label, "SetTextColor", unpack(entry.unread and COLORS.primary or COLORS.secondary)) end
	local primary_height = call(node.label, "GetStringHeight") or 14
	local foreign_source = type(entry.source) == "string" and entry.source:find("^smart_island") == nil and entry.source:find("^everlook") == nil
	-- A toast from Everlook itself does not name its source. The inbox row does.
	local source_label = (foreign_source or not compact) and (foreign_source and entry.source or "Everlook") or nil
	local severity = ({ success = "Success", warning = "Warning", error = "Error" })[entry.severity]
	local pieces = {}
	if severity then pieces[#pieces + 1] = severity end
	if source_label then pieces[#pieces + 1] = source_label end
	local metadata = table.concat(pieces, ", ")
	if not compact and not activity then
		local age = math.max(0, math.floor(clock_now() - (entry.updated_at or clock_now())))
		metadata = (entry.unread and "Unread, " or "") .. metadata .. ", " .. island.age_text(age)
	end
	local line_height = call(node.label, "GetLineHeight") or 14
	local clipped = false
	if compact and primary_height > line_height * 3 + 8 then
		call(node.label, "SetMaxLines", 3)
		primary_height = call(node.label, "GetStringHeight") or line_height * 3 + 8
		clipped = true
	end
	local detail = entry.detail or ""
	if entry.deferred then detail = detail ~= "" and (detail .. "\nAvailable after combat.") or "Available after combat." end
	if entry.money ~= nil then
		detail = detail .. (detail ~= "" and "\n" or "") .. (entry.money > 0 and "+" or "") .. vitals.rich(entry.money)
	end
	local y = card.label_top + shell.space.within + primary_height
	call(node.detail, "ClearAllPoints")
	call(node.detail, "SetPoint", "TOPLEFT", node.visual, "TOPLEFT", card.text, -y)
	call(node.detail, "SetWidth", text_width)
	call(node.detail, "SetMaxLines", 0)
	call(node.detail, "SetText", detail)
	call(node.detail, detail ~= "" and "Show" or "Hide")
	if detail ~= "" then
		local h = call(node.detail, "GetStringHeight") or 12
		if compact and h > 32 then
			call(node.detail, "SetMaxLines", 2)
			h, clipped = call(node.detail, "GetStringHeight") or 32, true
		end
		y = y + h + card.after_detail
	end
	if clipped then metadata = metadata ~= "" and ("More in inbox, " .. metadata) or "More in inbox" end
	-- A routine toast from Everlook needs no byline. The inbox row still has one.
	local routine = compact and not activity and not clipped and not foreign_source
		and entry.severity ~= "warning" and entry.severity ~= "error"
	call(node.meta, routine and "Hide" or "Show")
	if routine then
		y = y + card.after_routine
	else
		call(node.meta, "ClearAllPoints")
		call(node.meta, "SetPoint", "TOPLEFT", node.visual, "TOPLEFT", card.text, -y)
		call(node.meta, "SetWidth", text_width)
		call(node.meta, "SetText", metadata)
		call(node.meta, "SetTextColor", unpack(COLORS[entry.severity] or (node.row and COLORS.muted or COLORS.secondary)))
		local metadata_height = call(node.meta, "GetStringHeight") or 12
		y = y + metadata_height + card.after_meta
	end
	call(node.progress, entry.progress ~= nil and "Show" or "Hide")
	if entry.progress ~= nil then
		call(node.progress, "ClearAllPoints")
		call(node.progress, "SetPoint", "TOPLEFT", node.visual, "TOPLEFT", card.text, -y)
		call(node.progress, "SetSize", text_width, card.bar)
		call(node.progress, "SetValue", entry.progress)
		y = y + card.after_bar
	end
	local action_row = actions.paint(node, entry, compact) or 0
	if action_row > 0 then y = y + action_row end
	node.width, node.height = width, math.max(card.min_height, y)
	call(node.frame, "SetSize", node.width, node.height)
	local tone = COLORS[entry.severity]
	if tone and not activity and entry.severity ~= "info" then
		call(node.accent, "SetColorTexture", tone[1], tone[2], tone[3], 1)
		call(node.accent, "ClearAllPoints")
		call(node.accent, "SetPoint", "TOPLEFT", node.visual, "TOPLEFT", card.accent_x, -card.accent_top)
		call(node.accent, "SetSize", card.bar, math.max(4, node.height - 2 * card.accent_top))
		call(node.accent, "Show")
	else
		call(node.accent, "Hide")
	end
	if action_row > 0 then actions.paint(node, entry, compact) end
	if not activity and (not compact or node.frame.mouse) then
		-- A card with buttons or a click target keeps its left clicks. Letting them pass through
		-- the card can let them pass its buttons too, so only a plain notice is click-through.
		if compact then
			if entry.interaction == nil or entry.interaction == "inbox" then
				call(node.frame, "SetPassThroughButtons", "LeftButton")
			else
				call(node.frame, "SetPassThroughButtons")
			end
		end
		call(node.frame, "RegisterForClicks", "LeftButtonUp", "RightButtonUp")
		call(node.frame, "SetScript", "OnMouseUp", function(_, button)
			if button == "RightButton" and node.entry and not node.entry.removed and not node.entry.frozen then
				island.dismiss(node.entry.id)
			end
		end)
	end
	return node.height
end

local function copy_notice(entry)
	return { id = entry.id, source = entry.source, key = entry.key, kind = entry.kind, text = entry.text, duration = entry.duration,
		severity = entry.severity, detail = entry.detail, icon = entry.icon, money = entry.money,
		progress = entry.progress, presentation = entry.presentation, interaction = entry.interaction,
		capsule = entry.capsule and compact_api.copy(entry.capsule) or nil,
		runs = entry.runs,
		actions = actions.summary(entry), item_id = entry.item_id, spell_id = entry.spell_id,
		deferred = entry.deferred or nil, frozen = entry.frozen or nil,
		persist = entry.persist == true or nil, count = entry.count,
		unread = entry.unread, created_at = entry.created_at, updated_at = entry.updated_at }
end

local function copy_notices(entries)
	local list = {}
	for index = 1, #entries do list[index] = copy_notice(entries[index]) end
	return list
end

local function toast_position(node)
	local motion = node.motion
	if not motion then return node.y, node.alpha end
	local movement = call(node.translation, "GetSmoothProgress") or 0
	local fading = call(node.fade, "GetSmoothProgress") or 0
	return motion.from_y + (motion.to_y - motion.from_y) * movement,
		motion.from_alpha + (motion.to_alpha - motion.from_alpha) * fading
end

local function copy_toasts()
	local list = {}
	for index = 1, #active_toasts do
		local entry = active_toasts[index]
		local item = copy_notice(entry)
		item.y, item.alpha = toast_position(entry.node)
		item.phase, item.shown = entry.node.handoff and "handoff" or entry.phase, entry.node.shown
		item.width, item.height = entry.node.width, entry.node.height
		item.remaining = entry.remaining
		list[index] = item
	end
	return list
end

local function preview_position()
	local motion = preview.motion
	if not motion then return preview.y, preview.alpha end
	local movement = call(preview_translations[1], "GetSmoothProgress") or 0
	local fading = call(preview_fade, "GetSmoothProgress") or 0
	return motion.from_y + (motion.to_y - motion.from_y) * movement,
		motion.from_alpha + (motion.to_alpha - motion.from_alpha) * fading
end

local function place_preview(y, alpha)
	preview.y, preview.alpha = y, alpha
	call(expanded, "SetAlpha", alpha)
	call(shell.face, "SetAlpha", 1 - alpha)
	call(resting, "SetAlpha", 1)
	for _, target in ipairs(preview_targets) do
		call(target.frame, "ClearAllPoints")
		call(target.frame, "SetPoint", "TOPLEFT", target.parent, "TOPLEFT", 0, y)
		call(target.frame, "SetPoint", "BOTTOMRIGHT", target.parent, "BOTTOMRIGHT", 0, y)
	end
end

local function settle_preview(is_open)
	call(preview_group, "Stop")
	preview.motion, preview.phase, preview.open = nil, "settled", is_open
	preview.land = true
	place_preview(0, is_open and 1 or 0)
end

local function animate_preview(is_open)
	if preview.motion and preview.motion.sized and shell.sample then shell.sample() end
	local from_y, from_alpha = preview_position()
	call(preview_group, "Stop")
	if is_open and from_alpha == 0 then from_y = -6 end
	local to_y = is_open and 0 or -4
	local reduced = module.get(id, "reduced_motion")
	if reduced then from_y, to_y = 0, 0 end
	local to_alpha = is_open and 1 or 0
	local duration = is_open and MOTION.open or MOTION.close
	preview.phase, preview.open, preview.reduced = is_open and "opening" or "closing", is_open, reduced
	if not preview_group then settle_preview(is_open); return end
	local motion = { from_y = from_y, to_y = to_y, from_alpha = from_alpha, to_alpha = to_alpha, duration = duration, reduced = reduced == true }
	preview.motion = motion
	place_preview(from_y, from_alpha)
	for _, animation in ipairs(preview_translations) do
		call(animation, "SetOffset", 0, to_y - from_y)
		call(animation, "SetDuration", duration)
	end
	call(preview_fade, "SetFromAlpha", from_alpha)
	call(preview_fade, "SetToAlpha", to_alpha)
	call(preview_fade, "SetDuration", duration)
	call(preview_group, "SetScript", "OnFinished", function()
		if preview.motion ~= motion or not module.enabled(id) then return end
		settle_preview(is_open)
		paint()
	end)
	call(preview_group, "Play")
end

function island.format_clock(hour, minute)
	if not usable(hour) or not usable(minute) or type(hour) ~= "number" or type(minute) ~= "number" then return "" end
	return string.format("%d:%02d", hour, minute)
end

function island.format_level(level)
	if not usable(level) or type(level) ~= "number" then return "" end
	return tostring(level)
end

local function opened()
	return pinned or hovering or holding
end

-- A section changed. The panes redraw only while the island is open; closed, nothing shows them.
-- Inside a batch the redraw waits until the batch ends, so several changes draw once.
local batch_depth, batch_changed = 0, false

local function sections_changed()
	if batch_depth > 0 then
		if opened() then batch_changed = true end
	elseif opened() then
		paint("section")
	end
end

-- Something on the closed capsule changed, which shows whether or not the island is open.
local function capsule_changed()
	if batch_depth > 0 then
		batch_changed = true
	else
		paint("capsule")
	end
end

local function in_batch(work)
	batch_depth = batch_depth + 1
	local ok, result = pcall(work)
	batch_depth = batch_depth - 1
	if not ok then error(result, 0) end
	if batch_depth == 0 and batch_changed then
		batch_changed = false
		paint("section")
	end
	return result
end

-- The quest card and its plan, pushed as sections in one batch.
shell.push_quests = function()
	return in_batch(function() return quest_context.push() end)
end
quest_context.after_refresh = function() shell.quest_pushed = shell.push_quests() end

-- The header and the status cells, pushed as sections in one batch.
local function push_summary()
	return in_batch(function()
		local summary_pushed = island_summary.push(readout, module.get(id, "low_slots"))
		local resting_pushed = island_summary.push_resting(readout, {
			level = island.format_level(readout.level), xp = module.get(id, "closed_xp"), clock = module.get(id, "closed_clock"),
			gear = module.get(id, "source_durability"), bags = module.get(id, "source_bags"), free = module.get(id, "closed_bags"),
			low_slots = module.get(id, "low_slots"),
		})
		return summary_pushed or resting_pushed
	end)
end

local function mode()
	if opened() then return "open" end
	return "closed"
end

-- What a capsule that is held below the statuses shows of itself, for tests and /dump.
shell.held_view = function(list)
	local top = list[#list]
	return top and { source = top.source, key = top.key, text = top.text, count = #list } or nil
end

function island.view()
	local preview_y, preview_alpha = preview_position()
	return {
		mode = mode(),
		sections = sections.count(),
		background = shell.held_view(shell.backgrounds),
		resting = shell.held_view(shell.resting),
		quests = quest_context.view(true),
		pinned = pinned == true,
		hovering = hovering == true,
		holding = holding == true,
		toasts = copy_toasts(),
		notices = copy_notices(notices),
		queue = copy_notices(toast_queue),
		level = readout.level,
		xp = readout.xp,
		xp_max = readout.xp_max,
		money = readout.money_text,
		durability = readout.durability_text,
		bags = readout.bags_text,
		clock = readout.clock_text,
		coords = readout.coords_text,
		shown = frame ~= nil and frame.shown ~= false and module.enabled(id),
		width = frame and frame.width,
		height = frame and frame.height,
		summary_height = summary_height,
		unread_count = unread_count(),
		unread_below = shell.unread_below,
		more_above = shell.scrollbar ~= nil and shell.scrollbar.above == true,
		more_below = shell.scrollbar ~= nil and shell.scrollbar.below == true,
		scroll_offset = scroll_offset,
		quest_offset = shell.quest_offset,
		quest_height = shell.quest_height,
		scroll_height = scroll_height,
		content_height = content_height,
		can_undo = undo_state ~= nil,
		status = active_status() and copy_notice(active_status()) or nil,
		status_height = status_height,
		shell = { width = shell.width, height = shell.height, from = shell.from_w, to = shell.to_w, playing = shell.playing == true },
		preview = { phase = preview.phase, y = preview_y, alpha = preview_alpha, duration = preview.motion and preview.motion.duration },
	}
end

local function read_clock()
	if not GetGameTime then return end
	local hour, minute = GetGameTime()
	readout.clock_text = island.format_clock(hour, minute)
end

local function read_coords()
	readout.coords_text = nil
	local coordinates = Everlook.coordinates
	if not module.enabled("coordinates") or not coordinates or not coordinates.player_text then
		return
	end
	local text = coordinates.player_text()
	if text ~= "" then readout.coords_text = text end
end

function island.pull()
	local snap = vitals.snapshot()
	readout = {}
	readout.level, readout.xp, readout.xp_max, readout.xp_text = snap.level, snap.xp, snap.xp_max, snap.xp_text
	readout.money = snap.money
	readout.money_text = snap.money_text
	readout.durability = snap.durability
	if snap.durability ~= nil then readout.durability_max = 100 end
	readout.durability_text = snap.durability_text
	readout.bags = snap.bags
	readout.bags_total = snap.bags_total
	readout.bags_text = snap.bags_text
	read_clock()
	read_coords()
	push_summary()
end

-- Activity warnings ask whether a condition notice is still on screen.
function island.notice_live(handle)
	if not handle then return nil end
	for _, list in ipairs({ notices, active_toasts }) do
		for index = 1, #list do
			local entry = list[index]
			if entry.id == handle and entry.phase ~= "exiting" then
				return entry.node and "toast" or "inbox"
			end
		end
	end
end

local function take_bar(snap)
	if not snap then return end
	readout.xp, readout.xp_max, readout.level, readout.xp_text = snap.xp, snap.xp_max, snap.level, snap.xp_text
	push_summary()
end

local function refresh_readouts()
	vitals.follow("refresh")
end

-- The open summary is the header and the status cells under it, both sections that
-- island_summary.lua pushes. The open island is two columns that the summary and the panes share:
-- the left one runs to `left_w`, the right one begins there. With no left column (`left_w` is 0)
-- the cells stack, two across.
local function layout_summary(width, left_w)
	local space = shell.space
	local edge = space.edge
	local header, metrics = sections.list("header"), sections.list("metrics")
	local y = shell.blocks_header:paint(header, edge, width)
	if #header > 0 then y = y + space.section end
	shell.blocks_metrics.options.across = left_w == 0 and 2 or 4
	local metrics_end = shell.blocks_metrics:paint(metrics, y, width)
	summary_height = (#metrics > 0 and metrics_end or (#header > 0 and y - space.section or y)) + edge
	call(summary, "SetSize", width, summary_height)
	call(shell.divider, "ClearAllPoints")
	call(shell.divider, "SetPoint", "BOTTOMLEFT", summary, "BOTTOMLEFT", edge, 0)
	call(shell.divider, "SetPoint", "BOTTOMRIGHT", summary, "BOTTOMRIGHT", -edge, 0)
	call(shell.divider, "SetHeight", 1)
end

local QUEST_COLOR = { 1, 0.82, 0.25, 1 }
shell.quest_color = QUEST_COLOR

local function show_label(label, visible, text)
	if not label then return end
	if visible and text and text ~= "" then
		call(label, "SetText", text)
		call(label, "Show")
		call(label, "SetShown", true)
	else
		call(label, "Hide")
		call(label, "SetShown", false)
	end
end

local function secure_origin(node, y)
	local point = frame and frame.point or {}
	local top = -(point[5] or 0)
	return { x = point[4] or 0, y = -(top + (frame and frame.height or 0) - y), scale = module.get(id, "size") / 100,
		width = node.width, height = node.height }
end

local function position_toast(node, y, alpha)
	node.y, node.alpha = y, alpha
	call(node.frame, "ClearAllPoints")
	call(node.frame, "SetPoint", "TOP", frame, node.anchor or "BOTTOM", 0, y)
	call(node.frame, "SetAlpha", alpha)
end

local animate_toast

local function handoff_toasts()
	for _, entry in ipairs(active_toasts) do
		if entry.phase ~= "exiting" then
			local node = entry.node
			local y, alpha = toast_position(node)
			call(node.group, "Stop")
			node.motion, node.anchor = nil, "TOP"
			position_toast(node, y - frame.height, alpha)
			local token = {}
			node.handoff, node.shown = token, true
			animate_toast(node, node.y, 0, MOTION.handoff, function()
				if node.handoff ~= token or entry.node ~= node then return end
				node.handoff, node.shown = nil, false
				call(node.frame, "Hide")
			end)
		end
	end
end

-- Native translations reset when stopped. Sample their smoothed position
-- before retargeting, then commit the final anchor when the motion finishes.
animate_toast = function(node, y, alpha, duration, finished)
	local from_y, from_alpha = toast_position(node)
	call(node.group, "Stop")
	node.motion = nil
	node.reduced = module.get(id, "reduced_motion")
	if node.reduced then from_y = y end
	position_toast(node, from_y, from_alpha)
	if not node.group then
		position_toast(node, y, alpha)
		if finished then finished() end
		return
	end
	local motion = { from_y = from_y, to_y = y, from_alpha = from_alpha, to_alpha = alpha }
	node.motion = motion
	call(node.translation, "SetOffset", 0, y - from_y)
	call(node.translation, "SetDuration", duration)
	call(node.fade, "SetFromAlpha", from_alpha)
	call(node.fade, "SetToAlpha", alpha)
	local completing = node.entry and node.entry.completing and alpha == 1
	call(node.fade, "SetDuration", completing and MOTION.complete or duration)
	if completing then node.entry.completing = nil end
	call(node.group, "SetScript", "OnFinished", function()
		if node.motion ~= motion then return end
		node.motion = nil
		position_toast(node, y, alpha)
		if finished then finished() end
	end)
	call(node.group, "Play")
end

local function acquire_toast()
	for index = 1, #toast_pool do
		if not toast_pool[index].entry then return toast_pool[index] end
	end
	local card = CreateFrame("Button", nil, frame)
	call(card, "EnableMouse", false)
	call(card, "RegisterForClicks", "LeftButtonUp", "RightButtonUp")
	call(card, "SetFrameLevel", 51)
	local node = make_content(card)
	node.surface = island_surface.make(card)
	node.group = call(card, "CreateAnimationGroup")
	if node.group then
		node.translation = call(node.group, "CreateAnimation", "Translation")
		node.fade = call(node.group, "CreateAnimation", "Alpha")
		call(node.translation, "SetSmoothing", "OUT")
		call(node.fade, "SetSmoothing", "OUT")
		call(node.group, "SetToFinalAlpha", true)
	end
	toast_pool[#toast_pool + 1] = node
	return node
end

local function size_toast(entry)
	local node = entry.node
	local screen_width = screen_size("GetWidth")
	local _, font_size = call(node.label, "GetFont")
	node.width = math.max(64, math.min(font_size and font_size > 14 and 360 or 320, screen_width - 32))
	content_size(node, entry, node.width, true)
	island_surface.size(node.surface, node.width, node.height, shell.radius.panel)
end

local remove_toast, toast_timer

local function layout_toasts()
	if opened() then
		for index = #active_toasts, 1, -1 do
			if active_toasts[index].phase == "exiting" then remove_toast(active_toasts[index], true) end
		end
	end
	local y = -8
	for index = 1, #active_toasts do
		local entry = active_toasts[index]
		local node = entry.node
		if node.deferred_painted ~= (entry.deferred == true) then
			size_toast(entry)
			node.deferred_painted = entry.deferred == true
		end
		node.shown = not opened() or node.handoff ~= nil
		call(node.frame, node.shown and "Show" or "Hide")
		if opened() and not node.handoff then
			call(node.group, "Stop")
			node.motion, node.target_y, node.anchor, entry.phase = nil, y, nil, "visible"
			position_toast(node, y, 0)
		elseif opened() then
			-- The handoff owns its fade; metric repaints must not restart it.
		elseif entry.phase == "exiting" and node.reduced ~= module.get(id, "reduced_motion") then
			animate_toast(node, node.motion.to_y, 0, EXIT_TIME, function() remove_toast(entry) end)
		elseif entry.phase ~= "exiting" and (node.anchor or node.target_y ~= y or node.reduced ~= module.get(id, "reduced_motion")) then
			if node.anchor then
				local from_y, alpha = toast_position(node)
				call(node.group, "Stop")
				node.motion, node.handoff, node.anchor = nil, nil, nil
				position_toast(node, from_y + frame.height, alpha)
			end
			local toast_y = y
			node.target_y, node.reduced = toast_y, module.get(id, "reduced_motion")
			animate_toast(node, toast_y, 1, ENTER_TIME, function()
				if entry.phase == "entering" then entry.phase = "visible" end
				actions.sync(entry, opened(), entry.phase, false, secure_origin(node, toast_y))
			end)
		end
		actions.sync(entry, opened(), entry.phase, node.motion, secure_origin(node, y))
		y = y - node.height - TOAST_GAP
	end
end

local function release_notice(entry)
	if not entry or entry.removed or entry.persist then return end
	mark_removed(entry)
	entry.timer, entry.expires_at, entry.remaining, entry.expire_row = nil, nil, nil, nil
	for index = #notices, 1, -1 do
		if notices[index] == entry then table.remove(notices, index) end
	end
	for index = #toast_queue, 1, -1 do
		if toast_queue[index] == entry then table.remove(toast_queue, index) end
	end
end

remove_toast = function(entry, skip_paint)
	for index = #active_toasts, 1, -1 do
		if active_toasts[index] == entry then table.remove(active_toasts, index) end
	end
	local expire = entry.expire_row
	local deadline = entry.expires_at
	entry.expire_row = nil
	entry.timer, entry.phase, entry.hover_count = nil, nil, 0
	if not entry.frozen then actions.release(entry) end
	local node = entry.node
	if node then
		call(node.group, "Stop")
		node.motion, node.entry, node.shown, node.handoff, node.anchor = nil, nil, false, nil, nil
		call(node.frame, "Hide")
	end
	entry.node = nil
	if expire and not entry.persist then
		release_notice(entry)
	elseif not entry.persist and not entry.removed and not opened() and deadline then
		local seconds = deadline - clock_now()
		if seconds < 0.1 then seconds = 0.1 end
		toast_timer(entry, seconds)
	end
	if not skip_paint then paint() end
end

local function exit_toast(entry)
	if entry.frozen or entry.phase == "exiting" then return false end
	entry.timer, entry.phase = nil, "exiting"
	if opened() then
		remove_toast(entry)
	else
		local y = toast_position(entry.node)
		animate_toast(entry.node, y + 8, 0, EXIT_TIME, function() remove_toast(entry) end)
	end
	return true
end

toast_timer = function(entry, seconds)
	if not entry or entry.removed then
		if entry then entry.timer, entry.expires_at, entry.remaining = nil, nil, nil end
		return
	end
	actions.arm(entry, seconds, opened(), clock_now(), function(token, delay)
		if C_Timer and C_Timer.After then
			C_Timer.After(delay, function()
				if entry.timer ~= token or entry.removed then return end
				if entry.node and entry.phase ~= "exiting" then
					if not entry.persist then entry.expire_row = true end
					exit_toast(entry)
				elseif not entry.persist then
					release_notice(entry)
					paint()
				end
			end)
		end
	end)
end

function island.hover_notice(entry, inside)
	actions.hover(entry, inside, clock_now(), opened(), toast_timer)
end

local priority = island_toasts.priority

local function show_toast(entry)
	if entry.node then
		size_toast(entry)
		entry.phase = "entering"
		entry.node.target_y = nil
	elseif #active_toasts < module.get(id, "toast_count") then
		entry.node = acquire_toast()
		entry.node.entry, entry.node.target_y, entry.phase = entry, nil, "entering"
		size_toast(entry)
		position_toast(entry.node, 0, 0)
		active_toasts[#active_toasts + 1] = entry
	else
		for index = 1, #toast_queue do
			if toast_queue[index] == entry then
				if not entry.persist and (entry.timer or entry.expires_at or entry.remaining) then
					toast_timer(entry, entry.duration)
				end
				return
			end
		end
		if #toast_queue == QUEUE_MAX then
			local evict = island_toasts.evict_index(toast_queue, entry)
			if not evict then return end
			local removed = table.remove(toast_queue, evict)
			if removed and not removed.persist and not removed.removed then
				local seconds = removed.remaining
				if not seconds and removed.expires_at then seconds = math.max(0.1, removed.expires_at - clock_now()) end
				toast_timer(removed, seconds or removed.duration)
			end
		end
		toast_queue[#toast_queue + 1] = entry
		if entry.severity == "error" then
			for _, visible in ipairs(active_toasts) do
				if not visible.persist and priority(visible) == 1 and visible.phase ~= "exiting" and not visible.frozen then
					exit_toast(visible)
					break
				end
			end
		end
		if not entry.persist then
			local blocked = #active_toasts >= module.get(id, "toast_count")
			for _, visible in ipairs(active_toasts) do
				if not visible.persist and visible.phase ~= "exiting" then blocked = false end
			end
			if blocked then toast_timer(entry, entry.duration) end
		end
		return
	end
	toast_timer(entry, entry.duration)
	layout_toasts()
end

local function pump_toasts()
	if opened() then return end
	while #active_toasts < module.get(id, "toast_count") and #toast_queue > 0 do
		show_toast(table.remove(toast_queue, island_toasts.next_index(toast_queue)))
	end
end

local function clear_toasts()
	local kept, queue = {}, {}
	for index = 1, #active_toasts do
		local entry = active_toasts[index]
		if entry.frozen then
			kept[#kept + 1] = entry
		else
			local seconds = entry.remaining
			if not seconds and entry.expires_at then seconds = math.max(0.1, entry.expires_at - clock_now()) end
			entry.timer, entry.phase, entry.expires_at, entry.remaining = nil, nil, nil, nil
			actions.release(entry)
			if entry.node then
				call(entry.node.group, "Stop")
				entry.node.motion, entry.node.entry, entry.node.shown, entry.node.handoff, entry.node.anchor = nil, nil, false, nil, nil
				call(entry.node.frame, "Hide")
				entry.node = nil
			end
			if not entry.persist and not entry.removed then toast_timer(entry, seconds or entry.duration) end
		end
	end
	for index = 1, #toast_queue do
		local waiting = toast_queue[index]
		if waiting.frozen then
			queue[#queue + 1] = waiting
		elseif not waiting.persist and not waiting.removed and not waiting.timer and not waiting.expires_at then
			toast_timer(waiting, waiting.remaining or waiting.duration)
		end
	end
	active_toasts, toast_queue = kept, queue
end

-- The unread rows that start below the visible part of the list, and where the
-- first of them sits. A row counts as seen once any of it shows, as in the read timer.
shell.count_unread_below = function(list)
	local count, first = 0, nil
	for index, entry in ipairs(list) do
		local node = history_nodes[index]
		if node and entry.unread and node.y >= scroll_offset + scroll_height then
			count, first = count + 1, first or node.y
		end
	end
	shell.unread_below, shell.unread_first = count, first
	return count
end

-- The open island is two columns, quests on the left and notifications on the
-- right. The summary above them uses the same split, so what sits above a
-- pane lines up with it.
shell.panes = grid.panes

-- The width the open island takes, and whether two panes fit in it. Two panes sit on the
-- grid at their own width; when the screen is too narrow for them, the island is one pane.
shell.panel = function(two)
	local width, fitted = grid.fit(two, screen_size("GetWidth") - 32)
	return math.max(CLOSED_W, width), fitted
end

local function layout_expanded(list, status, two)
	local space = shell.space
	local width
	width, two = shell.panel(two)
	local left_w, right_w = shell.panes(width, two)
	layout_summary(width, left_w)
	if status then
		call(status_node.frame, "ClearAllPoints")
		call(status_node.frame, "SetPoint", "TOPLEFT", expanded, "TOPLEFT", 0, -summary_height)
		status_height = content_size(status_node, status, width, true, true) + space.within
		status_node.tooltip = root_hover.tooltip
	end
	local header_height = summary_height + status_height
	local viewport_top = header_height + space.head
	-- Sections in the notifications pane come first, with the history under them.
	local b_list = sections.list("pane_b")
	local b_end = shell.blocks_b:paint(b_list, space.near, right_w)
	content_height = #b_list > 0 and (b_end + space.section) or 0
	call(empty_text, "ClearAllPoints")
	call(empty_text, "SetPoint", "TOPLEFT", inbox_content, "TOPLEFT", space.edge, -content_height - space.near)
	call(empty_text, "SetWidth", right_w - 2 * space.edge)
	call(empty_text, "SetText", "No notifications yet")
	call(shell.empty_hint, "ClearAllPoints")
	call(shell.empty_hint, "SetPoint", "TOPLEFT", inbox_content, "TOPLEFT", space.edge, -content_height - space.near - (call(empty_text, "GetStringHeight") or 14) - space.within)
	call(shell.empty_hint, "SetWidth", right_w - 2 * space.edge)
	call(shell.empty_hint, "SetText", EMPTY_HINT)
	for index, entry in ipairs(list) do
		local node = history_nodes[index]
		if node then
			node.tooltip, node.entry, node.y = entry.text .. (entry.detail and "\n" .. entry.detail or "") ..
				(entry.money ~= nil and "\n" .. vitals.delta(entry.money) or "") ..
					(entry.frozen and "" or "\nRight-click to dismiss"), entry, content_height
			call(node.frame, "ClearAllPoints")
			call(node.frame, "SetPoint", "TOPLEFT", inbox_content, "TOPLEFT", 0, -content_height)
			content_height = content_height + content_size(node, entry, right_w)
		end
	end
	if #list == 0 then
		content_height = content_height + space.near + (call(empty_text, "GetStringHeight") or 14) + space.within
			+ (call(shell.empty_hint, "GetStringHeight") or 12) + space.section
	end
	-- Both lists share one height, so the divider between them runs clean.
	-- The quests pane: the quest source's card and plan, and the sections of other addons below them.
	-- Its heading is "Quests", unless the first section is another addon's, whose title it takes.
	local a_list = two and sections.list("pane_a") or {}
	local first_a = a_list[1]
	local quest_title = first_a and first_a.source ~= "everlook_quests" and first_a.title or nil
	call(shell.quest_heading, "Show")
	shell.heading(shell.quest_heading, quest_title or "Quests")
	local a_end = shell.blocks_a:paint(a_list, space.near, left_w, quest_title ~= nil)
	local quest_height = #a_list > 0 and (a_end + space.edge) or 0
	local room = math.max(space.pane_min, screen_size("GetHeight") - viewport_top - space.edge - space.block)
	-- Beside the quests, the notifications ask for no more than `pane_floor` of the height, and scroll
	-- past it, so a long history does not stretch a short quest column into empty space.
	local wanted = two and math.max(quest_height, math.min(content_height, space.pane_floor)) or content_height
	scroll_height = math.min(math.max(wanted, space.pane_min), space.pane_max, room)
	if follow_end then
		scroll_offset = content_height - scroll_height
	elseif scroll_anchor then
		for _, node in ipairs(history_nodes) do
			if node.entry and node.entry.id == scroll_anchor.id then scroll_offset = node.y + scroll_anchor.offset end
		end
	end
	scroll_anchor, follow_end = nil, nil
	scroll_offset = math.max(0, math.min(scroll_offset, content_height - scroll_height))
	-- Counted only now, against the offset the list will really show.
	local show_new = shell.count_unread_below(list) > 0
	-- A different quest starts at its top, and the card never follows the end of the notices.
	local quests_view = quest_context.view()
	local quest_id = quests_view and quests_view.current and quests_view.current.id
	if quest_id ~= shell.quest_shown then shell.quest_offset, shell.quest_shown = 0, quest_id end
	shell.quest_height = quest_height
	shell.quest_offset = math.max(0, math.min(shell.quest_offset, quest_height - scroll_height))
	call(inbox_content, "SetSize", right_w, content_height)
	call(inbox, "ClearAllPoints")
	call(inbox, "SetPoint", "TOPLEFT", expanded, "TOPLEFT", left_w, -viewport_top)
	call(inbox, "SetSize", right_w, scroll_height)
	call(inbox, "SetVerticalScroll", scroll_offset)
	call(quest_content, "SetSize", left_w, math.max(1, quest_height))
	call(quest_scroll, "ClearAllPoints")
	call(quest_scroll, "SetPoint", "TOPLEFT", expanded, "TOPLEFT", 0, -viewport_top)
	call(quest_scroll, "SetSize", left_w, scroll_height)
	call(quest_scroll, "SetVerticalScroll", shell.quest_offset)
	-- Each pane has a heading row. The notifications' also holds its controls.
	call(shell.quest_heading, "ClearAllPoints")
	call(shell.quest_heading, "SetPoint", "LEFT", expanded, "TOPLEFT", space.edge, -(header_height + space.head / 2))
	call(shell.notice_heading, "ClearAllPoints")
	call(shell.notice_heading, "SetPoint", "LEFT", expanded, "TOPLEFT", left_w + space.edge, -(header_height + space.head / 2))
	-- With no quest to show, the island is the notifications alone.
	for _, part in ipairs({ quest_scroll, shell.quest_heading, shell.pane_divider }) do
		call(part, two and "Show" or "Hide")
	end
	local height = viewport_top + scroll_height + space.edge
	call(shell.pane_divider, "ClearAllPoints")
	call(shell.pane_divider, "SetPoint", "TOPLEFT", expanded, "TOPLEFT", left_w, -header_height)
	call(shell.pane_divider, "SetSize", 1, height - header_height)
	call(footer, "ClearAllPoints")
	call(footer, "SetPoint", "TOPLEFT", expanded, "TOPLEFT", left_w, -header_height)
	call(footer, "SetSize", right_w, space.head)
	call(clear_button, #notices > 0 and "Show" or "Hide")
	call(undo_button, undo_state and "Show" or "Hide")
	call(undo_button, "ClearAllPoints")
	if #notices > 0 then
		call(undo_button, "SetPoint", "RIGHT", clear_button, "LEFT", -space.near, 0)
	else
		call(undo_button, "SetPoint", "TOPRIGHT", footer, "TOPRIGHT", -space.edge, -(space.head - space.link) / 2)
	end
	local unread_below = shell.unread_below
	call(new_button, show_new and "Show" or "Hide")
	shell.set_control_text(new_button, unread_below == 1 and "1 new notice" or unread_below .. " new notices")
	call(new_button, "ClearAllPoints")
	call(new_button, "SetPoint", "BOTTOMRIGHT", inbox, "BOTTOMRIGHT", -(space.edge + space.near), space.near)
	shell.scroll_api.layout(shell.scrollbar, left_w, viewport_top, scroll_height, content_height, scroll_offset, right_w)
	shell.scroll_api.layout(shell.quest_scrollbar, 0, viewport_top, scroll_height, quest_height, shell.quest_offset, left_w)
	call(expanded, "SetSize", width, height)
	island_surface.size(expanded_surface, width, height, shell.radius.panel)
	return width, height
end

local function apply_visual(width, height)
	shell.width, shell.height = width, height
	call(resting, "SetSize", width, height)
	call(resting, "SetAlpha", 1)
	call(resting, "Show")
	island_surface.size(surface, width, height, shell.radius.capsule)
	island_surface.size_glow(shell.glow, width, height, shell.radius.capsule)
	call(expanded, "SetSize", width, height)
end

shell.apply = apply_visual

local function measure_capsule(text, role)
	if shell.measure then
		shell.role(shell.measure, role or "title")
		call(shell.measure, "SetText", text)
	end
	local measured = call(shell.measure, "GetStringWidth")
	if type(measured) == "number" and measured == measured and measured >= 0 and measured < math.huge then return measured end
	return #text * 8
end

-- A resting slot is a frame holding a row of its own, so the capsule that is leaving and the one arriving
-- can each be drawn whole and faded against each other.
local function place_slot(slot, layout, alpha)
	if not slot then return end
	slot.row:set(layout.row, layout.reserve)
	call(slot.frame, "SetAlpha", alpha)
	call(slot.frame, "Show")
end

local function hide_slot(slot)
	if not slot then return end
	call(slot.frame, "Hide")
end

local function finish_shell()
	apply_visual(shell.to_w, shell.to_h)
	if shell.fading then
		hide_slot(resting_slots[shell.outgoing])
		local incoming = resting_slots[shell.incoming_slot]
		if shell.to_empty then
			hide_slot(incoming)
		elseif incoming then
			call(incoming.frame, "SetAlpha", 1)
		end
		shell.signature = shell.incoming
		shell.front = shell.incoming_slot
	end
	shell.playing, shell.fading, shell.sizing = false, false, false
	call(shell.group, "Stop")
	call(frame, "SetScript", "OnUpdate", preview.motion and shell.tick or nil)
end

local function sample_shell()
	local progress = call(shell.anim, "GetSmoothProgress") or 0
	if shell.sizing then
		apply_visual(shell.from_w + (shell.to_w - shell.from_w) * progress, shell.from_h + (shell.to_h - shell.from_h) * progress)
	end
	if shell.fading then
		local outgoing = resting_slots[shell.outgoing]
		local incoming = resting_slots[shell.incoming_slot]
		if outgoing then
			call(outgoing.frame, "SetAlpha", 1 - progress)
		end
		if incoming then
			call(incoming.frame, "SetAlpha", progress)
		end
	end
	if progress >= 1 then finish_shell() end
end

local function play_shell()
	if not shell.group or not shell.anim then finish_shell(); return end
	call(shell.group, "Stop")
	call(shell.anim, "SetDuration", MOTION.open)
	call(shell.group, "Play")
	shell.playing = true
	call(frame, "SetScript", "OnUpdate", shell.tick)
	sample_shell()
end

-- The open and close preview owns the chrome while it plays. A capsule ease waits.
shell.tick = function()
	if preview.motion and shell.sample then shell.sample() end
	if shell.playing then sample_shell() end
	if not preview.motion and not shell.playing then call(frame, "SetScript", "OnUpdate", nil) end
end

shell.sample = function()
	local motion = preview.motion
	if not motion or not motion.sized then return end
	local progress = call(preview_fade, "GetSmoothProgress") or 0
	local opening = preview.phase == "opening"
	local travel = motion.reduced and (opening and 1 or 0) or progress
	local grow = motion.reduced and 1 or progress
	local width = motion.from_w + (motion.to_w - motion.from_w) * grow
	local height = motion.from_h + (motion.to_h - motion.from_h) * grow
	apply_visual(width, height)
	local alpha = motion.from_alpha + (motion.to_alpha - motion.from_alpha) * progress
	call(expanded, "SetAlpha", alpha)
	call(shell.face, "SetAlpha", 1 - alpha)
	call(shell.face, "SetPoint", "TOP", resting, "TOP", 0, 0)
	call(shell.face, "SetSize", motion.closed_w or CLOSED_W, motion.closed_h or CLOSED_H)
	if motion.travel_x then
		local from_x = width / 2 - (motion.closed_w or CLOSED_W) / 2 + motion.travel_x
		local from_y = -((motion.closed_h or CLOSED_H) / 2)
		local title = shell.blocks_header and shell.blocks_header:first_title()
		local to_x = shell.space.edge + ((call(title, "GetStringWidth") or 0) / 2)
		local to_y = -shell.space.edge - ((call(title, "GetLineHeight") or 14) / 2)
		call(closed_text, "ClearAllPoints")
		call(closed_text, "SetPoint", "CENTER", resting, "TOPLEFT", from_x + (to_x - from_x) * travel, from_y + (to_y - from_y) * travel)
	end
end

-- Width moves only when the measured pill changes by at least 4. A one-step
-- m:ss tick stays put. Icon and trailing changes still crossfade.
local function drive_shell(target_w, target_h, signature, layout, snap)
	if preview.motion then return end
	-- The first capsule there is appears at once.
	if shell.signature == nil and signature ~= nil and not shell.playing then snap = true end
	local reduced = module.get(id, "reduced_motion")
	local width_delta = math.abs(target_w - shell.width)
	local height_delta = math.abs(target_h - shell.height)
	local same = shell.playing and shell.incoming == signature and shell.to_w == target_w and shell.to_h == target_h
	if same and not snap then
		local live = resting_slots[shell.fading and shell.incoming_slot or shell.front]
		if live and layout then live.row:set(layout.row, layout.reserve) end
		return
	end
	if not snap and not shell.playing and signature == shell.signature and width_delta < 4 and height_delta < 4 then
		local live = resting_slots[shell.front or 1]
		if live and layout then live.row:set(layout.row, layout.reserve) end
		apply_visual(target_w, target_h)
		return
	end
	if snap then
		shell.to_w, shell.to_h, shell.from_w, shell.from_h = target_w, target_h, target_w, target_h
		shell.incoming, shell.fading, shell.sizing, shell.to_empty = signature, false, false, signature == nil
		shell.front = shell.front or 1
		apply_visual(target_w, target_h)
		hide_slot(resting_slots[shell.front == 1 and 2 or 1])
		if layout and signature then
			place_slot(resting_slots[shell.front], layout, 1)
		else
			hide_slot(resting_slots[shell.front])
		end
		shell.signature = signature
		shell.playing = false
		call(shell.group, "Stop")
		call(frame, "SetScript", "OnUpdate", nil)
		return
	end
	local fading = signature ~= shell.signature
	local sizing = not reduced and (width_delta >= 4 or height_delta >= 4)
	shell.from_w, shell.from_h = shell.width, shell.height
	shell.to_w, shell.to_h = target_w, target_h
	shell.incoming = signature
	shell.fading, shell.sizing = fading, sizing
	shell.to_empty = signature == nil
	shell.outgoing = shell.front or 1
	shell.incoming_slot = shell.outgoing == 1 and 2 or 1
	shell.front = shell.front or 1
	if reduced then apply_visual(target_w, target_h) end
	if fading and layout and signature then
		place_slot(resting_slots[shell.incoming_slot], layout, 0)
	elseif fading and signature == nil then
		hide_slot(resting_slots[shell.incoming_slot])
	end
	if not fading and layout then
		place_slot(resting_slots[shell.front], layout, 1)
	end
	play_shell()
end

paint = function(reason)
	if not frame or not module.enabled(id) then return end
	shell.stats.paint = shell.stats.paint + 1
	local now = mode()
	local changed = preview.open ~= opened()
	if reason == "keyboard" then
		settle_preview(opened())
		for _, entry in ipairs(active_toasts) do entry.node.handoff = nil end
	elseif changed and reason == "pointer" then
		if opened() then handoff_toasts() end
		animate_preview(opened())
	elseif changed then
		settle_preview(opened())
	elseif preview.motion and preview.reduced ~= module.get(id, "reduced_motion") then
		animate_preview(opened())
	end
	local visual_open = now == "open" or preview.phase == "closing"
	local list = visual_open and notices or {}
	local width, height = CLOSED_W, CLOSED_H
	local status = active_status()
	-- The capsule is held by the first of: a status, a background status, the resting display. A status
	-- with no capsule of its own keeps its icon beside the level.
	local background = not status and shell.backgrounds[#shell.backgrounds] or nil
	local rested = not status and not background and shell.resting[#shell.resting] or nil
	local holder = status or background or rested
	local compact = holder and holder.capsule
	local level_text = island.format_level(readout.level)
	if status and not compact then
		compact = { icon = notice_mark(status.icon, status), text = level_text ~= "" and level_text or nil }
	end
	-- A status can carry its progress outside its capsule. The capsule shows it as a percent.
	if status and status.capsule and compact.progress == nil and type(status.progress) == "number" then
		compact = compact_api.copy(compact)
		compact.progress = status.progress
	end
	local page_width, two = shell.panel(visual_open and #sections.list("pane_a") > 0)
	local available = math.max(64, screen_size("GetWidth") - 32)
	local morphing = preview.phase == "opening" or preview.phase == "closing"
	-- The unread count sits on the capsule's right inset, and the capsule keeps clear of the room it takes.
	-- A status that has a capsule of its own shows no count.
	local unread = unread_count()
	local counts_unread = not (status and status.capsule)
	local reserve = 0
	if unread > 0 then
		call(unread_text, "SetText", tostring(unread))
		reserve = math.ceil(call(unread_text, "GetStringWidth") or 8) + shell.space.near
	end
	local layout = compact and compact_api.layout(compact, measure_capsule, available, counts_unread and reserve or 0) or nil
	local closed_w, closed_h = CLOSED_W, CLOSED_H
	if layout then closed_w, closed_h = layout.width, layout.height end
	status_height = 0
	-- The open island already shows what the tooltip would say. The resting display has none.
	local described = status or background
	root_hover.tooltip = not visual_open and described and (described.text .. (described.detail and "\n" .. described.detail or "")) or nil
	call(shell.face, "SetPoint", "TOP", resting, "TOP", 0, 0)
	call(shell.face, "SetSize", closed_w, closed_h)
	if visual_open then width, height = layout_expanded(list, status, two) end
	if now ~= "open" then
		width, height = closed_w, closed_h
	end
	frame.width, frame.height = width, height
	call(frame, "SetSize", width, height)
	place_frame(width, height)
	local hit_inset = now == "closed" and -2 or 0
	call(frame, "SetHitRectInsets", hit_inset, hit_inset, hit_inset, hit_inset)
	call(frame, "Show")
	frame.shown = true
	call(expanded, visual_open and "Show" or "Hide")
	call(resting, "SetAlpha", 1)
	call(resting, "Show")
	call(summary, visual_open and "Show" or "Hide")
	call(status_node.frame, status and visual_open and "Show" or "Hide")
	call(inbox, visual_open and "Show" or "Hide")
	call(quest_scroll, visual_open and two and "Show" or "Hide")
	call(footer, visual_open and "Show" or "Hide")
	if not visual_open then
		shell.scroll_api.hide(shell.scrollbar)
		shell.scroll_api.hide(shell.quest_scrollbar)
	end
	for _, control in ipairs(preview_controls) do call(control, "EnableMouse", now == "open") end
	show_label(empty_text, visual_open and #list == 0, "No notifications yet")
	show_label(shell.empty_hint, visual_open and #list == 0, EMPTY_HINT)
	call(unread_text, "ClearAllPoints")
	call(unread_text, "SetPoint", "RIGHT", shell.face, "RIGHT", layout and -shell.space.edge or -5, 0)
	show_label(unread_text, (now == "closed" or morphing) and counts_unread and unread_count() > 0, tostring(unread_count()))
	local unread_warning = false
	for _, entry in ipairs(notices) do
		if entry.unread and priority(entry) > 1 then unread_warning = true end
	end
	call(unread_text, "SetTextColor", unpack(unread_warning and COLORS.warning or COLORS.accent))
	-- Opening the island, the level slides from the resting display to the header's title, when the
	-- resting display's own title is the level. The copy that slides stands in for that title meanwhile.
	local travels = rested ~= nil and layout ~= nil and level_text ~= "" and layout.row.title == level_text and morphing
	show_label(closed_text, travels, level_text)
	for _, slot in ipairs(resting_slots) do slot.row:lend_title(travels) end
	for index = 1, LIST_MAX do
		local entry = list[index]
		local node = history_nodes[index]
		if node then
			call(node.frame, visual_open and entry ~= nil and "Show" or "Hide")
		end
	end
	if module.get(id, "toasts") then
		pump_toasts()
		layout_toasts()
	else
		clear_toasts()
	end
	if inspect_rows then inspect_rows() end
	local signature = layout and compact_api.signature(compact) or nil
	-- The slide starts at the title's centre in the pill: the middle of the row when the title is alone,
	-- or the row's edge inset and half the title when other parts share the row.
	local travel_x
	if travels then
		local row = layout.row
		local alone = row.icon == nil and row.arrow == nil and not row.ring and #row.labels == 0 and row.badge == nil
		travel_x = alone and (closed_w - (layout.reserve or 0)) / 2 or shell.space.edge + (call(closed_text, "GetStringWidth") or 0) / 2
	end
	if preview.land and not preview.motion then
		preview.land = false
		if now == "open" then
			shell.apply(width, height)
		else
			drive_shell(closed_w, closed_h, signature, layout, true)
			call(shell.face, "SetAlpha", 1)
		end
	elseif preview.motion then
		local motion = preview.motion
		motion.to_w, motion.to_h = width, height
		motion.closed_w, motion.closed_h = closed_w, closed_h
		motion.travel_x = travel_x
		if not motion.sized then
			motion.from_w, motion.from_h = shell.width, shell.height
			motion.sized = true
		end
		shell.sample()
		call(frame, "SetScript", "OnUpdate", shell.tick)
	elseif now == "open" then
		shell.apply(width, height)
	else
		drive_shell(closed_w, closed_h, signature, layout, visual_open or changed or reason == "keyboard")
	end
	shell.sync_idle(now == "closed" and not morphing and not status and not background and #active_toasts == 0 and unread_count() == 0)
end

local function leave_open()
	local resting_rows = {}
	for index = 1, #notices do
		local entry = notices[index]
		if not entry.node and not entry.persist and not entry.removed and entry.presentation ~= "status"
			and (entry.expires_at or entry.remaining) then
			resting_rows[#resting_rows + 1] = entry
		end
	end
	if not was_open and opened() then
		actions.hold(active_toasts, clock_now())
		actions.hold(resting_rows, clock_now())
	elseif was_open and not opened() then
		actions.unhold(active_toasts, toast_timer)
		actions.unhold(resting_rows, toast_timer)
	end
	was_open = opened()
end

function island.open_notice(entry)
	if not module.enabled(id) or not entry or entry.removed then return false end
	pinned = true
	scroll_anchor = { id = entry.id, offset = 0 }
	follow_end = false
	leave_open()
	refresh_readouts()
	paint("pointer")
	return true
end

inspect_rows = function()
	for index, entry in ipairs(notices) do
		local node = history_nodes[index]
		local visible = opened() and node and node.entry == entry and node.y < scroll_offset + scroll_height
			and node.y + node.height > scroll_offset
		if not visible then
			entry.read_timer = nil
		elseif entry.unread and not entry.read_timer and C_Timer and C_Timer.After then
			local token = {}
			entry.read_timer = token
			C_Timer.After(0.75, function()
				if entry.read_timer ~= token or not opened() or not module.enabled(id) then return end
				for _, current in ipairs(notices) do
					if current == entry then entry.unread, entry.read_timer = false, nil; paint(); return end
				end
			end)
		end
	end
end

function island.scroll_to(offset)
	if not usable(offset) or type(offset) ~= "number" or not opened() then return end
	scroll_offset = math.max(0, math.min(offset, content_height - scroll_height))
	paint()
end

function island.scroll_quests(offset)
	if not usable(offset) or type(offset) ~= "number" or not opened() then return end
	shell.quest_offset = math.max(0, math.min(offset, shell.quest_height - scroll_height))
	paint()
end

function island.clear_history()
	if not module.enabled(id) or #notices == 0 then return false end
	local kept, cleared = {}, {}
	for _, entry in ipairs(notices) do
		if entry.frozen then
			kept[#kept + 1] = entry
		else
			entry.read_timer, entry.removed = nil, true
			cleared[#cleared + 1] = entry
		end
	end
	if #cleared == 0 then return false end
	local token = { entries = cleared }
	undo_state, notices, scroll_offset = token, kept, 0
	clear_toasts()
	paint()
	if C_Timer and C_Timer.After then
		C_Timer.After(5, function()
			if undo_state ~= token then return end
			undo_state = nil
			paint()
		end)
	end
	return true
end

function island.undo_clear()
	if not undo_state or not module.enabled(id) then return false end
	local restored = island_inbox.restore(notices, undo_state.entries)
	undo_state, notices = nil, restored
	for _, entry in ipairs(notices) do
		if entry.removed then
			entry.removed = nil
			entry.action_generation = (entry.action_generation or 0) + 1
		end
	end
	bound_history()
	paint()
	return true
end

local function plain_string(value, maximum)
	return usable(value) and type(value) == "string" and #value <= maximum and value:find("%S") ~= nil
end

local function refresh_status(entry)
	local exists = false
	for _, current in ipairs(statuses) do if current == entry then exists = true end end
	if not exists then
		statuses[#statuses + 1] = entry
		if #statuses > STATUS_MAX then remove_status(statuses[1]) end
	end
	local token = {}
	entry.status_timer = token
	if C_Timer and C_Timer.After then
		C_Timer.After(30, function()
			if entry.status_timer ~= token then return end
			remove_status(entry)
			paint()
		end)
	end
end

function island.notify(payload)
	if not module.enabled(id) then return nil, "disabled" end
	if not usable(payload) or type(payload) ~= "table" or getmetatable(payload) ~= nil then return nil, "invalid_notification" end
	local read, reason = island_notice.read(payload, module.get(id, "read_time"))
	if not read then return nil, reason end
	local text, source, kind, key, duration = read.text, read.source, read.kind, read.key, read.duration
	local persist, stack, severity, detail, icon = read.persist, read.stack, read.severity, read.detail, read.icon
	local money, progress, presentation = read.money, read.progress, read.presentation
	local compact, runs, spec = read.compact, read.runs, read.spec
	-- A background or resting status is only a capsule: it takes no part in history, toasts or timers.
	local held_list = (read.rank == "background" and shell.backgrounds) or (read.rank == "resting" and shell.resting) or nil
	if held_list then
		local held
		for _, candidate in ipairs(held_list) do
			if candidate.source == source and candidate.key == key then held = candidate end
		end
		if not held then
			next_notice_id = next_notice_id + 1
			held = { id = next_notice_id, rank = read.rank, presentation = "status" }
			held_list[#held_list + 1] = held
		end
		held.source, held.key, held.kind, held.text, held.detail, held.icon = source, key, kind, text, detail, icon
		held.severity, held.duration, held.capsule, held.runs = severity, duration, compact, runs
		capsule_changed()
		return held.id
	end
	if opened() then
		follow_end = scroll_offset >= content_height - scroll_height - 1
		for _, node in ipairs(history_nodes) do
			if node.entry and node.y + node.height > scroll_offset then
				scroll_anchor = { id = node.entry.id, offset = scroll_offset - node.y }
				break
			end
		end
	end
	local entry, joined
	if key then
		for _, list in ipairs({ notices, statuses, active_toasts, toast_queue }) do
			for index = 1, #list do
				if list[index].source == source and list[index].key == key then entry = list[index]; break end
			end
			if entry then break end
		end
	end
	if not entry and stack and presentation ~= "status" then
		for _, list in ipairs({ notices, active_toasts, toast_queue }) do
			for index = #list, 1, -1 do
				local candidate = list[index]
				if candidate.source == source and candidate.stack == stack and not candidate.removed
					and candidate.presentation ~= "status" and candidate.persist == (persist == true)
					and candidate.phase ~= "exiting" and not candidate.expire_row then
					entry, joined = candidate, true
					break
				end
			end
			if entry then break end
		end
	end
	if entry and entry.frozen then return nil, "combat_locked" end
	local next_money = money
	if joined and money ~= nil and entry.money ~= nil then
		next_money = entry.money + money
		if not finite(next_money) or math.abs(next_money) > 9007199254740991 or next_money ~= math.floor(next_money) then
			return nil, "invalid_money"
		end
	elseif joined and money == nil then
		next_money = entry.money
	end
	if not entry then
		next_notice_id = next_notice_id + 1
		entry = { id = next_notice_id, created_at = clock_now(), unread = true, count = 1 }
		-- A new warning or error flashes the island, so it is seen even while you are looking elsewhere.
		if severity == "warning" or severity == "error" then island.react(severity) end
	elseif joined then
		entry.count = (entry.count or 1) + 1
	end
	-- A producer can publish the same key while its card is still leaving.
	if entry.removed then entry.removed, entry.expire_row = nil, nil end
	local continued_status = presentation == "status" and entry.presentation == "status"
	entry.completing = presentation == "toast" and entry.presentation == "status"
	if joined or entry.text ~= text or entry.severity ~= severity or (not continued_status and
		(entry.detail ~= detail or entry.money ~= next_money or entry.presentation ~= presentation)) then entry.unread, entry.read_timer = true, nil end
	entry.updated_at = clock_now()
	entry.source, entry.key, entry.kind, entry.text, entry.duration = source, key, kind, text, duration
	entry.severity, entry.detail, entry.icon, entry.money = severity, detail, icon, next_money
	entry.persist, entry.stack = persist == true, stack
	entry.progress, entry.presentation = progress, presentation
	entry.capsule, entry.runs = compact, runs
	if actions.different(entry, spec) then entry.action_generation = (entry.action_generation or 0) + 1 end
	entry.interaction, entry.actions = spec.interaction, spec.actions
	entry.item_id, entry.spell_id = spec.item_id, spec.spell_id
	if actions.protected(entry) and actions.locked() and not (entry.secure_card and entry.secure_card.armed) then
		entry.deferred = true
	end
	if presentation == "status" then refresh_status(entry) else remove_status(entry) end
	for index = #notices, 1, -1 do
		if notices[index] == entry then table.remove(notices, index) end
	end
	notices[#notices + 1] = entry
	bound_history()
	local combat = InCombatLockdown and InCombatLockdown()
	local kept_quiet = (not usable(combat) or combat == true) and not module.get(id, "combat_toasts") and priority(entry) == 1
		and not actions.protected(entry)
	if module.get(id, "do_not_disturb") and priority(entry) < 3 then kept_quiet = true end
	if presentation == "toast" and not kept_quiet and module.get(id, "toasts") and (entry.node or not opened()) then
		show_toast(entry)
	elseif presentation ~= "toast" or kept_quiet then
		for index = #toast_queue, 1, -1 do
			if toast_queue[index] == entry then table.remove(toast_queue, index) end
		end
		if entry.node then exit_toast(entry) end
	end
	local waiting = false
	for index = 1, #toast_queue do
		if toast_queue[index] == entry then waiting = true end
	end
	if not entry.persist and presentation ~= "status" and not entry.node and not entry.removed and not waiting then
		toast_timer(entry, entry.duration)
	end
	paint()
	vitals.follow("notice", source, detail, money)
	return entry.id
end

mark_removed = function(entry)
	if entry then entry.removed, entry.hover_count = true, 0 end
end

function island.dismiss(handle)
	if not usable(handle) or type(handle) ~= "number" then return false end
	if sections.get(handle) then
		sections.remove(handle)
		sections_changed()
		return true
	end
	for _, list in ipairs({ statuses, notices, toast_queue, active_toasts }) do
		for index = 1, #list do
			if list[index].id == handle and list[index].frozen then return nil, "combat_locked" end
		end
	end
	local removed = false
	for _, list in ipairs({ shell.backgrounds, shell.resting }) do
		for index = #list, 1, -1 do
			if list[index].id == handle then table.remove(list, index); removed = true end
		end
	end
	for index = #statuses, 1, -1 do
		if statuses[index].id == handle then remove_status(statuses[index]); removed = true end
	end
	for index = #notices, 1, -1 do
		if notices[index].id == handle then
			mark_removed(notices[index])
			table.remove(notices, index)
			removed = true
		end
	end
	for index = #toast_queue, 1, -1 do
		if toast_queue[index].id == handle then mark_removed(toast_queue[index]); table.remove(toast_queue, index); removed = true end
	end
	for index = #active_toasts, 1, -1 do
		if active_toasts[index].id == handle and exit_toast(active_toasts[index]) then mark_removed(active_toasts[index]); removed = true end
	end
	if removed then paint() end
	return removed
end

-- Live control of a notice that is already showing. A producer holds the handle
-- notify returned, and changes the notice through these calls instead of
-- building new notices or reaching into the Island's frames.
local function find_notice(handle)
	for _, list in ipairs({ notices, statuses, toast_queue, active_toasts, shell.backgrounds, shell.resting }) do
		for index = 1, #list do
			if list[index].id == handle then return list[index] end
		end
	end
end

-- The notice written back as the payload notify would take, so an update is a
-- change to that payload and goes through the same checks.
local function payload_of(entry)
	local rows = {}
	for index, action in ipairs(entry.actions or {}) do
		rows[index] = { id = action.id, label = action.label, type = action.type, on_click = action.callback,
			item_id = action.item_id, spell_id = action.spell_id, allow_in_combat = action.allow_in_combat or nil,
			enabled = action.type == "callback" and action.enabled or nil }
	end
	return {
		source = entry.source, key = entry.key, kind = entry.kind, text = entry.text, duration = entry.duration,
		severity = entry.severity, detail = entry.detail, icon = entry.icon, money = entry.money, progress = entry.progress,
		presentation = entry.presentation, persist = entry.persist, stack = entry.stack, interaction = entry.interaction,
		actions = #rows > 0 and rows or nil, item_id = entry.item_id, spell_id = entry.spell_id,
		capsule = entry.capsule, runs = entry.runs, rank = entry.rank,
	}
end

-- Adds a section to a pane, or replaces the one this source made under the same key.
-- Returns its handle, or nil and a reason.
function island.section(spec)
	if not module.enabled(id) then return nil, "disabled" end
	local record, reason = island_section.read(spec)
	if not record then return nil, reason end
	local handle, limit = sections.put(record, clock_now())
	if not handle then return nil, limit end
	sections_changed()
	return handle
end

-- The reaction playing on the island's body, drawn from the arithmetic in island_reaction.lua.
local reaction_state = island_reaction.new()

local function show_reaction()
	local sample = island_reaction.sample(reaction_state, clock_now())
	if not sample then
		island_surface.set_glow(shell.glow, nil, 0, 0)
		call(shell.reaction_frame, "SetScript", "OnUpdate", nil)
		return
	end
	island_surface.set_glow(shell.glow, island_capsule.tone_color(sample.tone), sample.tint, sample.edge)
end

local function stop_reaction()
	reaction_state = island_reaction.new()
	island_surface.set_glow(shell.glow, nil, 0, 0)
	call(shell.reaction_frame, "SetScript", "OnUpdate", nil)
end

local REACTION_KEYS = { kind = true, strength = true, source = true }

-- Flashes the island's body. `reaction` is a kind, or { kind, strength, source }. Returns true,
-- or nil and a reason: disabled, do_not_disturb, invalid_reaction, or limited.
function island.react(reaction)
	if not module.enabled(id) or not module.get(id, "reactions") then return nil, "disabled" end
	if module.get(id, "do_not_disturb") then return nil, "do_not_disturb" end
	local kind, strength = reaction, nil
	if type(reaction) == "table" then
		if not usable(reaction) or getmetatable(reaction) ~= nil then return nil, "invalid_reaction" end
		for key in pairs(reaction) do
			if not REACTION_KEYS[key] then return nil, "invalid_reaction" end
		end
		kind, strength = reaction.kind, reaction.strength
		if reaction.source ~= nil and (type(reaction.source) ~= "string" or #reaction.source > 64) then return nil, "invalid_reaction" end
	elseif not usable(reaction) then
		return nil, "invalid_reaction"
	end
	local started, reason = island_reaction.start(reaction_state, kind, strength, clock_now(), module.get(id, "reduced_motion") == true)
	if not started then return nil, reason end
	call(shell.reaction_frame, "SetScript", "OnUpdate", show_reaction)
	show_reaction()
	return true
end

local SECTION_CHANGES = { title = true, order = true, blocks = true, expires = true }

local function update_section(record, changes)
	for name in pairs(changes) do
		if not SECTION_CHANGES[name] then return nil, "invalid_update" end
	end
	local merged = { source = record.source, key = record.key, region = record.region, title = record.title,
		order = record.order, expires = record.expires, blocks = changes.blocks or {} }
	for name in pairs(SECTION_CHANGES) do
		if changes[name] ~= nil and name ~= "blocks" then merged[name] = changes[name] end
	end
	local next_record, reason = island_section.read(merged)
	if not next_record then return nil, reason end
	-- Blocks that were not changed are kept as they were read.
	if changes.blocks == nil then next_record.blocks, next_record.bytes = record.blocks, record.bytes end
	local handle, limit = sections.put(next_record, clock_now())
	if not handle then return nil, limit end
	sections_changed()
	return handle
end

function island.update(handle, changes)
	if not module.enabled(id) then return nil, "disabled" end
	if not usable(handle) or type(handle) ~= "number" then return nil, "invalid_handle" end
	if not usable(changes) or type(changes) ~= "table" or getmetatable(changes) ~= nil then return nil, "invalid_update" end
	if changes.source ~= nil or changes.key ~= nil or changes.id ~= nil then return nil, "invalid_update" end
	local record = sections.get(handle)
	if record then return update_section(record, changes) end
	local entry = find_notice(handle)
	if not entry or entry.removed then return nil, "unknown_handle" end
	if entry.frozen then return nil, "combat_locked" end
	-- notify finds a notice by source and key, so a notice made without a key gets a private one.
	if not entry.key then entry.key = "~" .. entry.id end
	local merged = payload_of(entry)
	for name, value in pairs(changes) do merged[name] = value end
	-- An empty action list clears the buttons, and buttons are the default interaction only while there are some.
	if type(merged.actions) == "table" and next(merged.actions) == nil then
		merged.actions = nil
		if changes.interaction == nil and merged.interaction == "buttons" then merged.interaction = nil end
	end
	return island.notify(merged)
end

function island.set_actions(handle, list)
	return island.update(handle, { actions = list })
end

function island.set_action_enabled(handle, action_id, enabled)
	if not module.enabled(id) then return nil, "disabled" end
	if not usable(handle) or type(handle) ~= "number" then return nil, "invalid_handle" end
	if not usable(action_id) or type(action_id) ~= "string" then return nil, "invalid_action_id" end
	local entry = find_notice(handle)
	if not entry then return nil, "unknown_handle" end
	if entry.frozen then return nil, "combat_locked" end
	return actions.set_enabled(entry, action_id, enabled)
end

local event_frame
local subscriptions = {}
local next_subscription_id = 0

local function report_event_error(event, reason)
	local detail = plain_string(reason, 1024) and reason or "notification producer failed"
	geterrorhandler()("Everlook Smart Island (" .. event .. "): " .. detail)
end

local function notification_event(_, event, ...)
	if not module.enabled(id) then return end
	-- A producer can remove subscriptions during its callback. New subscriptions
	-- start on the next event; removed ones are skipped even in this snapshot.
	local pending = {}
	for index = 1, #subscriptions do
		if subscriptions[index].event == event then pending[#pending + 1] = subscriptions[index] end
	end
	for index = 1, #pending do
		local subscription = pending[index]
		if subscription.active and module.enabled(id) then
			local ok, payload = pcall(subscription.callback, event, ...)
			if not ok then
				report_event_error(event, payload)
			elseif issecretvalue and issecretvalue(payload) then
				report_event_error(event, "invalid_notification")
			elseif payload ~= nil then
				-- A callback may also ask for a reaction, with or without a notice to go with it.
				if type(payload) == "table" and getmetatable(payload) == nil and payload.reaction ~= nil then
					local ok_reaction, why = island.react(payload.reaction)
					if not ok_reaction and why == "invalid_reaction" then report_event_error(event, why) end
					local rest = {}
					for key, value in pairs(payload) do
						if key ~= "reaction" then rest[key] = value end
					end
					payload = next(rest) ~= nil and rest or nil
				end
				if payload ~= nil then
					local handle, reason = island.notify(payload)
					if not handle and reason ~= "disabled" then report_event_error(event, reason) end
				end
			end
		end
	end
end

function island.register_event(event, callback)
	if not plain_string(event, 64) then return nil, "invalid_event" end
	if not usable(callback) or type(callback) ~= "function" then return nil, "invalid_callback" end
	if not event_frame then
		if not CreateFrame then return nil, "unavailable" end
		event_frame = CreateFrame("Frame")
		event_frame:SetScript("OnEvent", notification_event)
	end
	local ok, listening = pcall(event_frame.RegisterEvent, event_frame, event)
	if not ok or not listening then return nil, "invalid_event" end
	next_subscription_id = next_subscription_id + 1
	subscriptions[#subscriptions + 1] = { id = next_subscription_id, event = event, callback = callback, active = true }
	return next_subscription_id
end

function island.unregister_event(handle)
	if not usable(handle) or type(handle) ~= "number" then return false end
	local removed
	for index = 1, #subscriptions do
		if subscriptions[index].id == handle then
			removed = table.remove(subscriptions, index)
			removed.active = false
			break
		end
	end
	if not removed then return false end
	for index = 1, #subscriptions do
		if subscriptions[index].event == removed.event then return true end
	end
	event_frame:UnregisterEvent(removed.event)
	return true
end

Everlook.island = {
	notify = island.notify,
	dismiss = island.dismiss,
	update = island.update,
	set_actions = island.set_actions,
	set_action_enabled = island.set_action_enabled,
	register_event = island.register_event,
	unregister_event = island.unregister_event,
	section = island.section,
	react = island.react,
	-- Raised only when something is added, so an addon can test for what it needs.
	api = 3,
}

local function hide()
	quest_context.reset()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	painted = {}
	sections.clear()
	island_summary.reset()
	quest_context.forget_push()
	stop_reaction()
	local kept = {}
	for _, entry in ipairs(notices) do
		if entry.frozen then kept[#kept + 1] = entry else mark_removed(entry) end
	end
	for _, entry in ipairs(active_toasts) do
		if not entry.frozen then mark_removed(entry) end
	end
	for _, entry in ipairs(toast_queue) do
		if not entry.frozen then mark_removed(entry) end
	end
	clear_toasts()
	settle_preview(false)
	for _, entry in ipairs(statuses) do entry.status_timer = nil end
	statuses = {}
	shell.backgrounds, shell.resting = {}, {}
	undo_state, close_token, scroll_anchor, follow_end = nil, nil, nil, nil
	scroll_offset, scroll_height, content_height = 0, 0, 0
	shell.quest_offset, shell.quest_height, shell.quest_shown = 0, 0, nil
	pinned, hovering, holding, hold_was_pinned, hold_at, was_open = nil, nil, nil, nil, nil, nil
	notices, readout = kept, {}
	vitals.follow("hide")
	shell.signature, shell.incoming, shell.playing, shell.fading, shell.sizing = nil, nil, false, false, false
	shell.width, shell.height = CLOSED_W, CLOSED_H
	shell.from_w, shell.to_w, shell.from_h, shell.to_h = CLOSED_W, CLOSED_W, CLOSED_H, CLOSED_H
	call(shell.group, "Stop")
	call(frame, "SetScript", "OnUpdate", nil)
	if frame then
		call(frame, "Hide")
		frame.shown = false
	end
end

local function on_enter()
	if not module.enabled(id) or not module.get(id, "hover_preview") then return end
	close_token = nil
	hovering = true
	leave_open()
	refresh_readouts()
	paint("pointer")
end

-- Moving from the Island onto one of its own controls is a leave for the frame
-- and an enter for the control. A control that does not tell the Island it was
-- entered (the scroll thumb, the experience heading, the buttons on a notice)
-- would otherwise close it under the pointer. So the close waits, and checks
-- whether the pointer is still over the Island, and checks again until it is not.
local CLOSE_DELAY = 0.1

local function on_leave()
	local token = {}
	close_token = token
	local function close()
		if close_token ~= token then return end
		if call(frame, "IsMouseOver") == true and C_Timer and C_Timer.After then
			C_Timer.After(CLOSE_DELAY, close)
			return
		end
		close_token, hovering = nil, nil
		leave_open()
		paint("pointer")
	end
	if C_Timer and C_Timer.After then C_Timer.After(CLOSE_DELAY, close) else close() end
end

-- Shift and drag moves the Island by writing the same two placement options as
-- the sliders. The frame is never made movable, so place_frame stays in charge.
-- One table holds the pieces so ensure_frame stays under Lua's upvalue limit.
local mover = {}

local function drag_follow()
	local drag = mover.drag
	if not drag or not module.enabled(id) then return end
	local cursor_x, cursor_y = GetCursorPosition()
	if not finite(cursor_x) or not finite(cursor_y) then return end
	local ratio = (call(UIParent, "GetEffectiveScale") or 1) * (module.get(id, "size") / 100)
	module.set(id, "position_x", math.floor(drag.x + (cursor_x - drag.cursor_x) / ratio + 0.5))
	module.set(id, "position_top", math.floor(drag.top - (cursor_y - drag.cursor_y) / ratio + 0.5))
end

function mover.install(target)
	mover.watch = CreateFrame("Frame", nil, UIParent)
	call(target, "RegisterForDrag", "LeftButton")
	call(target, "SetScript", "OnDragStart", function()
		if not module.enabled(id) or not IsShiftKeyDown or not IsShiftKeyDown() or not GetCursorPosition then return end
		local cursor_x, cursor_y = GetCursorPosition()
		if not finite(cursor_x) or not finite(cursor_y) then return end
		mover.drag = { cursor_x = cursor_x, cursor_y = cursor_y, x = module.get(id, "position_x"), top = module.get(id, "position_top") }
		call(mover.watch, "SetScript", "OnUpdate", drag_follow)
	end)
	call(target, "SetScript", "OnDragStop", function()
		if not mover.drag then return end
		drag_follow()
		mover.drag, mover.dragged_at = nil, clock_now()
		call(mover.watch, "SetScript", "OnUpdate", nil)
	end)
end

-- With Hide when idle on, the closed pill fades out once nothing needs it and
-- returns for a notice, a status, a quest or the pointer. The frame keeps its
-- hit area while faded, so hovering the spot brings it back.
local idle = { delay = 5 }

function idle.show(visible)
	local target = visible and 1 or 0
	if idle.target == target then return end
	idle.target = target
	if UIFrameFadeOut and UIFrameFadeIn and not module.get(id, "reduced_motion") then
		local fade = visible and UIFrameFadeIn or UIFrameFadeOut
		fade(frame, 0.3, call(frame, "GetAlpha") or (1 - target), target)
	else
		call(frame, "SetAlpha", target)
	end
end

function idle.sync(quiet)
	if not module.get(id, "hide_when_idle") or not quiet or hovering then
		idle.since = nil
		idle.show(true)
		return
	end
	local now = clock_now()
	idle.since = idle.since or now
	if now - idle.since >= idle.delay then
		idle.show(false)
	elseif C_Timer and C_Timer.After and not idle.waiting then
		idle.waiting = true
		C_Timer.After(idle.delay - (now - idle.since) + 0.05, function()
			idle.waiting = nil
			if module.enabled(id) and paint then paint() end
		end)
	end
end

shell.sync_idle = idle.sync

local function on_click()
	if not module.enabled(id) then return end
	-- Letting go after a drag also clicks the Island. That click is not a pin.
	if mover.dragged_at and clock_now() - mover.dragged_at < 0.2 then mover.dragged_at = nil; return end
	pinned = not pinned
	leave_open()
	refresh_readouts()
	paint("pointer")
end

local function hover_target(target, node)
	call(target, "SetScript", "OnEnter", function()
		on_enter()
		if node.on_hover then node.on_hover(true) end
		if node.tooltip and GameTooltip then
			call(GameTooltip, "SetOwner", target, "ANCHOR_RIGHT")
			call(GameTooltip, "SetText", node.tooltip, 1, 1, 1, 1, true)
			call(GameTooltip, "Show")
		end
	end)
	call(target, "SetScript", "OnLeave", function()
		call(GameTooltip, "Hide")
		if node.on_hover then node.on_hover(false) end
		on_leave()
	end)
end

local function make_control(parent, name, title, width, callback)
	local button = CreateFrame("Button", name, parent)
	call(button, "SetSize", width, shell.space.control)
	call(button, "RegisterForClicks", "LeftButtonUp")
	local visual = make_visual(button, true)
	local background = island_surface.make(visual)
	island_surface.size(background, width, shell.space.control, shell.radius.control)
	local label = make_label(visual, "CENTER", true)
	call(label, "SetPoint", "CENTER")
	call(label, "SetText", title)
	call(button, "SetScript", "OnClick", callback)
	button.label, button.background, button.pad, button.hover = label, background, 24, { tooltip = title }
	hover_target(button, button.hover)
	preview_controls[#preview_controls + 1] = button
	return button
end

-- A quiet button for a heading row or a line of content: a thin outline round muted words, the
-- same look as the buttons on a notice. Under the pointer the fill lightens and the words turn white.
shell.tint_link = function(button, state)
	island_surface.tint_button(button.quiet, state)
	call(button.label, "SetTextColor", unpack(state == "rest" and COLORS.secondary or COLORS.primary))
end

shell.make_link = function(parent, name, title, callback)
	local button = CreateFrame("Button", name, parent)
	call(button, "SetSize", 56, shell.space.link)
	call(button, "RegisterForClicks", "LeftButtonUp")
	local visual = make_visual(button, true)
	button.quiet = island_surface.make_button(visual)
	local label = make_label(visual, "CENTER", true)
	call(label, "SetPoint", "CENTER")
	call(label, "SetText", title)
	call(button, "SetScript", "OnClick", function(...)
		shell.tint_link(button, "hover")
		callback(...)
	end)
	call(button, "SetScript", "OnMouseDown", function() shell.tint_link(button, "press") end)
	button.label, button.pad = label, 24
	button.hover = { tooltip = nil, on_hover = function(inside) shell.tint_link(button, inside and "hover" or "rest") end }
	hover_target(button, button.hover)
	preview_controls[#preview_controls + 1] = button
	shell.tint_link(button, "rest")
	shell.set_control_text(button, title)
	return button
end

-- A control whose words change sizes itself to them.
shell.set_control_text = function(button, text)
	call(button.label, "SetText", text)
	local width = math.max(56, math.ceil(call(button.label, "GetStringWidth") or 0) + button.pad)
	call(button, "SetWidth", width)
	if button.background then island_surface.size(button.background, width, shell.space.control, shell.radius.control) end
	if button.quiet then island_surface.size_button(button.quiet, width, shell.space.link) end
end

local function ensure_frame()
	if frame or not CreateFrame or not UIParent then return frame end
	frame = CreateFrame("Button", "EverlookSmartIsland", UIParent)
	if not frame then return nil end
	frame.width, frame.height = CLOSED_W, CLOSED_H
	call(frame, "SetFrameStrata", "HIGH")
	call(frame, "SetFrameLevel", 50)
	call(frame, "SetClampedToScreen", true)
	call(frame, "EnableMouse", true)
	call(frame, "RegisterForClicks", "LeftButtonUp")
	call(frame, "SetSize", CLOSED_W, CLOSED_H)
	call(frame, "SetPoint", "TOP", UIParent, "TOP", 0, -8)
	resting = CreateFrame("Frame", "EverlookIslandResting", frame)
	call(resting, "EnableMouse", false)
	call(resting, "SetFrameLevel", 49)
	call(resting, "SetPoint", "TOP", frame, "TOP", 0, 0)
	call(resting, "SetSize", CLOSED_W, CLOSED_H)
	call(resting, "SetAlpha", 1)
	surface = island_surface.make(resting)
	shell.glow = island_surface.make_glow(resting)
	shell.reaction_frame = CreateFrame("Frame", nil, frame)
	shell.face = CreateFrame("Frame", "EverlookIslandFace", frame)
	call(shell.face, "EnableMouse", false)
	call(shell.face, "SetFrameLevel", 52)
	call(shell.face, "SetPoint", "TOP", resting, "TOP", 0, 0)
	call(shell.face, "SetSize", CLOSED_W, CLOSED_H)
	expanded = CreateFrame("Frame", "EverlookIslandExpanded", frame)
	call(expanded, "EnableMouse", false)
	call(expanded, "SetFrameLevel", 50)
	call(expanded, "SetClipsChildren", true)
	call(expanded, "SetPoint", "TOP", frame, "TOP", 0, 0)
	local background = make_visual(expanded, true)
	expanded_surface = island_surface.make(background)
	call(background, "Hide")
	summary = CreateFrame("Frame", nil, expanded)
	call(summary, "SetPoint", "TOPLEFT", expanded, "TOPLEFT", 0, 0)
	call(summary, "EnableMouse", false)
	closed_text = make_label(shell.face, "CENTER")
	call(closed_text, "SetPoint", "CENTER", shell.face, "CENTER", -4, 0)
	unread_text = make_label(shell.face, "RIGHT", true)
	call(unread_text, "SetPoint", "RIGHT", shell.face, "RIGHT", -5, 0)
	call(unread_text, "SetTextColor", unpack(COLORS.accent))
	shell.measure = make_label(resting, "LEFT")
	call(shell.measure, "Hide")
	for index = 1, 2 do
		local slot_frame = CreateFrame("Frame", nil, shell.face)
		call(slot_frame, "SetAllPoints", shell.face)
		call(slot_frame, "EnableMouse", false)
		call(slot_frame, "Hide")
		resting_slots[index] = { frame = slot_frame, row = island_row.new(slot_frame, { label = make_label, ring_size = shell.space.capsule_ring, center_alone = true,
			rings = { make = shell.make_ring, place = shell.place_ring, chain = shell.chain_ring, set = shell.set_ring, hide = shell.hide_ring } }) }
	end
	-- A capsule's arrow that asks for its angle is turned ten times a second, while a capsule shows.
	shell.capsule_aim = CreateFrame("Frame", nil, shell.face)
	local capsule_wait = 0
	call(shell.capsule_aim, "SetScript", "OnUpdate", function(_, elapsed)
		if type(elapsed) ~= "number" then return end
		capsule_wait = capsule_wait + elapsed
		if capsule_wait < 0.1 then return end
		capsule_wait = 0
		for _, slot in ipairs(resting_slots) do
			if slot.frame.shown ~= false then slot.row:tick() end
		end
	end)
	shell.group = call(resting, "CreateAnimationGroup")
	if shell.group then
		shell.anim = call(shell.group, "CreateAnimation", "Alpha")
		call(shell.anim, "SetSmoothing", "OUT")
		call(shell.anim, "SetDuration", MOTION.open)
		call(shell.anim, "SetFromAlpha", 0)
		call(shell.anim, "SetToAlpha", 1)
	end
	local activity = CreateFrame("Button", nil, expanded)
	status_node = make_content(activity, true)
	hover_target(activity, status_node)
	call(activity, "SetScript", "OnClick", on_click)
	preview_controls[#preview_controls + 1] = activity
	local header_visual = make_visual(summary, true)
	shell.header_visual = header_visual
	shell.divider = call(header_visual, "CreateTexture", nil, "ARTWORK")
	call(shell.divider, "SetColorTexture", 1, 1, 1, 0.1)
	-- The two lists and what frames them: a heading row and a rule over each, and
	-- a divider between. They sit in one layer so the open motion moves them together.
	local panes_visual = make_visual(expanded, true)
	shell.pane_divider = call(panes_visual, "CreateTexture", nil, "ARTWORK")
	call(shell.pane_divider, "SetColorTexture", 1, 1, 1, 0.1)
	shell.quest_heading = make_label(panes_visual, "LEFT", "heading")
	shell.heading(shell.quest_heading, "Quests")
	shell.notice_heading = make_label(panes_visual, "LEFT", "heading")
	shell.heading(shell.notice_heading, "Notifications")
	quest_scroll = CreateFrame("ScrollFrame", nil, expanded)
	call(quest_scroll, "EnableMouseWheel", true)
	preview_controls[#preview_controls + 1] = quest_scroll
	quest_content = CreateFrame("Frame", nil, quest_scroll)
	call(quest_content, "SetSize", OPEN_W / 2, 1)
	call(quest_content, "SetPoint", "TOPLEFT", quest_scroll, "TOPLEFT", 0, 0)
	call(quest_scroll, "SetScrollChild", quest_content)
	call(quest_scroll, "SetScript", "OnMouseWheel", function(_, delta)
		if usable(delta) and type(delta) == "number" then island.scroll_quests(shell.quest_offset - delta * shell.space.step) end
	end)
	hover_target(quest_scroll, {})
	inbox = CreateFrame("ScrollFrame", nil, expanded)
	call(inbox, "EnableMouseWheel", true)
	preview_controls[#preview_controls + 1] = inbox
	inbox_content = CreateFrame("Frame", nil, inbox)
	call(inbox_content, "SetSize", OPEN_W / 2, 1)
	call(inbox_content, "SetPoint", "TOPLEFT", inbox, "TOPLEFT", 0, 0)
	call(inbox, "SetScrollChild", inbox_content)
	call(inbox, "SetScript", "OnMouseWheel", function(_, delta)
		if usable(delta) and type(delta) == "number" then island.scroll_to(scroll_offset - delta * shell.space.step) end
	end)
	hover_target(inbox, {})
	local empty_visual = make_visual(inbox_content, true)
	empty_text = make_label(empty_visual, "LEFT", "text")
	call(empty_text, "SetPoint", "TOPLEFT", empty_visual, "TOPLEFT", shell.space.edge, -shell.space.edge)
	shell.empty_hint = make_label(empty_visual, "LEFT", "caption")
	for index = 1, LIST_MAX do
		local target = CreateFrame("Button", nil, inbox_content)
		local node = make_content(target, true, true)
		history_nodes[index] = node
		hover_target(target, node)
		preview_controls[#preview_controls + 1] = target
	end
	footer = CreateFrame("Frame", nil, expanded)
	clear_button = shell.make_link(footer, "EverlookIslandClearHistory", "Clear history", island.clear_history)
	call(clear_button, "SetPoint", "TOPRIGHT", footer, "TOPRIGHT", -shell.space.edge, -((shell.space.head - shell.space.link) / 2))
	undo_button = shell.make_link(footer, "EverlookIslandUndo", "Undo", island.undo_clear)
	-- The pill floats over the foot of the list, so it sits above the edge fades.
	new_button = make_control(expanded, "EverlookIslandNewNotices", "New notices", 96, function() island.scroll_to(shell.unread_first or content_height) end)
	call(new_button, "SetFrameLevel", 64)
	new_button.hover.tooltip = "Go to the first unread notice"
	local function drag_ratio() return (call(UIParent, "GetEffectiveScale") or 1) * (module.get(id, "size") / 100) end
	shell.scrollbar = shell.scroll_api.make(expanded, { scroll_to = island.scroll_to, ratio = drag_ratio })
	preview_controls[#preview_controls + 1] = shell.scrollbar.thumb
	shell.quest_scrollbar = shell.scroll_api.make(expanded, { name = "EverlookIslandQuestScrollThumb", scroll_to = island.scroll_quests, ratio = drag_ratio })
	preview_controls[#preview_controls + 1] = shell.quest_scrollbar.thumb
	quest_context.ensure_ui({ pin = island.pin_quest, space = shell.space,
		-- The level, and the experience percent when the capsule shows it, for the quest on the capsule.
		badge = function()
			local level = island.format_level(readout.level)
			if level == "" then return nil end
			return level, module.get(id, "closed_xp") and readout.xp_text or nil
		end })
	local block_host = { label = make_label, visual = make_visual, link = shell.make_link, set_link_text = shell.set_control_text,
		hover = function(target, node)
			hover_target(target, node)
			preview_controls[#preview_controls + 1] = target
		end,
		heading = shell.heading, space = shell.space, ring_size = shell.space.capsule_ring, primary = COLORS.primary,
		money = vitals.rich, click = on_click, role = shell.role,
		rings = { make = shell.make_ring, place = shell.place_ring, chain = shell.chain_ring, set = shell.set_ring, hide = shell.hide_ring, track = shell.track_ring } }
	shell.blocks_header = island_blocks.new(shell.header_visual, block_host, { title_role = "display", row_height = 20 })
	shell.blocks_metrics = island_blocks.new(shell.header_visual, block_host, { across = 4 })
	shell.blocks_a = island_blocks.new(quest_content, block_host)
	shell.blocks_b = island_blocks.new(inbox_content, block_host)
	-- A row's arrow that asks for its angle is turned ten times a second, while the panes show.
	shell.aim_frame = CreateFrame("Frame", nil, expanded)
	local aim_wait = 0
	call(shell.aim_frame, "SetScript", "OnUpdate", function(_, elapsed)
		if type(elapsed) ~= "number" then return end
		aim_wait = aim_wait + elapsed
		if aim_wait < 0.1 then return end
		aim_wait = 0
		shell.blocks_a:tick()
		shell.blocks_b:tick()
	end)
	preview_group = call(expanded, "CreateAnimationGroup")
	if preview_group then
		preview_fade = call(preview_group, "CreateAnimation", "Alpha")
		call(preview_fade, "SetSmoothing", "OUT")
		for _, target in ipairs(preview_targets) do
			local translation = call(preview_group, "CreateAnimation", "Translation")
			call(translation, "SetTarget", target.frame)
			call(translation, "SetSmoothing", "OUT")
			preview_translations[#preview_translations + 1] = translation
		end
		call(preview_group, "SetToFinalAlpha", true)
	end
	settle_preview(false)
	hover_target(frame, root_hover)
	call(frame, "SetScript", "OnClick", on_click)
	mover.install(frame)
	call(frame, "Hide")
	frame.shown = false
	return frame
end

-- Plain history rows from before a reload come back once per session, read or
-- unread as they were. They have no actions: the producers own those.
local function restore_history()
	if shell.history_restored or not Everlook.island_history then return end
	shell.history_restored = true
	local now = clock_now()
	for _, row in ipairs(Everlook.island_history.load()) do
		next_notice_id = next_notice_id + 1
		local icon = island_notice.icon_for(row.icon, row.kind)
		notices[#notices + 1] = {
			id = next_notice_id, source = row.source, key = row.key, kind = row.kind, text = row.text, detail = row.detail,
			severity = row.severity, icon = icon, money = row.money, count = row.count, unread = row.unread,
			duration = 4, persist = false, presentation = "inbox", actions = {},
			created_at = now - row.age, updated_at = now - row.age,
		}
	end
	bound_history()
end

local function follow_top_widgets()
	local widget = UIWidgetTopCenterContainerFrame
	if shell.top_widgets_followed or not widget or type(widget.HookScript) ~= "function" then return end
	shell.top_widgets_followed = true
	for _, script in ipairs({ "OnShow", "OnHide", "OnSizeChanged" }) do
		widget:HookScript(script, function()
			if module.enabled(id) and module.get(id, "avoid_top_widgets") and paint then paint() end
		end)
	end
end

local function notice_minutes(now)
	local minutes = 0
	for index = 1, #notices do
		local updated = notices[index].updated_at
		if type(updated) == "number" then
			local age = now - updated
			if age >= 60 then minutes = minutes + math.floor(age / 60) end
		end
	end
	return minutes
end

local function note_screen()
	local open = opened()
	painted.clock, painted.coords = readout.clock_text, readout.coords_text
	painted.minutes = open and notice_minutes(clock_now()) or 0
	if module.get(id, "quest_context") and quest_context.pulse then
		painted.quest = quest_context.pulse(open)
	else
		painted.quest = nil
	end
end

local function apply(enabled)
	island_surface.set_opacity(module.get(id, "opacity") / 100)
	bound_history()
	if not enabled then
		hide()
		return
	end
	ensure_frame()
	follow_top_widgets()
	restore_history()
	refresh_readouts()
	refresh_quests(true)
	vitals.follow("sync")
	paint()
	note_screen()
	if ticker or not C_Timer or not C_Timer.NewTicker then return end
	ticker = C_Timer.NewTicker(1, function()
		if not module.enabled(id) then
			hide()
			return
		end
		-- Mail, hearth, and the half-hour recap still sample every second.
		-- The frame itself stays put until a visible label changes: the open
		-- clock and coordinates, a notice's minute, or the quest chip.
		local open = opened()
		if sections.prune(clock_now()) and open then
			paint("section")
			return
		end
		local pushed = false
		if open then
			read_clock()
			read_coords()
			pushed = push_summary()
		end
		-- A push of the quest sections and capsule redraws the island after the scan, whether it is open or closed.
		local quests_pushed = refresh_quests(false)
		pushed = quests_pushed or pushed
		local minutes = open and notice_minutes(clock_now()) or painted.minutes
		local quest_mark = nil
		if module.get(id, "quest_context") and quest_context.pulse then
			quest_mark = quest_context.pulse(open)
		end
		if readout.clock_text == painted.clock and readout.coords_text == painted.coords
			and minutes == painted.minutes and quest_mark == painted.quest then
			return
		end
		-- A push already redrew the open island for what it carried: the clock and the coordinates, or the quests.
		local changed_elsewhere = minutes ~= painted.minutes or (quest_mark ~= painted.quest and not quests_pushed)
		painted.clock, painted.coords = readout.clock_text, readout.coords_text
		painted.minutes, painted.quest = minutes, quest_mark
		if not pushed or changed_elsewhere then paint() end
	end)
end

local function on_event(event, ...)
	if event == "PLAYER_LOGOUT" then
		if module.enabled(id) and Everlook.island_history then Everlook.island_history.save(notices, clock_now()) end
		return
	end
	if event == "CHAT_MSG_COMBAT_XP_GAIN" or event == "UPDATE_EXHAUSTION" or event == "PLAYER_XP_UPDATE" then
		take_bar(vitals.follow(event))
		paint()
		return
	end
	if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then paint(); return end
	if event == "QUEST_TURNED_IN" then
		refresh_quests(true)
		paint()
		return
	end
	if event == "QUEST_LOG_UPDATE" or event == "QUEST_WATCH_UPDATE" or event == "QUEST_WATCH_LIST_CHANGED" or event == "SUPER_TRACKING_CHANGED" then
		if refresh_quests_from_event() then paint() end
		return
	end
	if event == "PLAYER_LEVEL_UP" or event == "PLAYER_MONEY" or event == "UPDATE_INVENTORY_DURABILITY" or event == "BAG_UPDATE_DELAYED" then
		vitals.follow(event, ...)
		paint()
	else
		vitals.follow("catchup")
		paint()
	end
end

local function key_down()
	if holding or not module.enabled(id) then return end
	holding = true
	hold_was_pinned = pinned == true
	hold_at = GetTime and GetTime() or 0
	leave_open()
	refresh_readouts()
	paint("keyboard")
end

local function key_up()
	if not holding then return end
	local started, pinned_before = hold_at, hold_was_pinned
	holding, hold_at, hold_was_pinned = nil, nil, nil
	if module.enabled(id) then
		local now = GetTime and GetTime() or 0
		if type(started) ~= "number" or (now - started) < HOLD then
			pinned = not pinned_before
		else
			pinned = pinned_before
		end
	end
	leave_open()
	paint("keyboard")
end

-- The keyboard route to the right-click dismiss. The newest toast goes first.
-- A notice held for combat stays until the fight ends.
function island.dismiss_top()
	if not module.enabled(id) then return false end
	for index = #active_toasts, 1, -1 do
		local entry = active_toasts[index]
		if not entry.frozen and entry.phase ~= "exiting" then return island.dismiss(entry.id) == true end
	end
	return false
end

function everlook_smart_island_dismiss()
	island.dismiss_top()
end

-- Called by Bindings.xml. Same press-and-release shape as the radial menu key.
function everlook_smart_island_key(keystate)
	if keystate == "down" then key_down() else key_up() end
end

actions.use({
	hover = island.hover_notice,
	open = island.open_notice,
	now = clock_now,
	dismiss = function(handle) island.dismiss(handle) end,
	enabled = function() return module.enabled(id) end,
	each = function(fn)
		local seen = {}
		local function visit(entry)
			if entry and not seen[entry] then
				seen[entry] = true
				fn(entry)
			end
		end
		for index = 1, #notices do visit(notices[index]) end
		for index = 1, #active_toasts do visit(active_toasts[index]) end
		for index = 1, #toast_queue do visit(toast_queue[index]) end
	end,
	-- A toast that was leaving when the pointer reached it stays instead.
	revive = function(entry)
		if not entry.node or entry.phase ~= "exiting" then return end
		entry.phase, entry.expire_row, entry.node.target_y = "entering", nil, nil
		layout_toasts()
	end,
	resume = function(entry)
		if entry.node and entry.phase ~= "exiting" and not opened() then
			toast_timer(entry, entry.remaining or entry.duration)
		end
	end,
	repaint = function()
		if paint then paint() end
	end,
})

registered = module.register({
	addon = addon_name, page = "smart_island", order = 10,
	id = id,
	name = "Smart island",
	description = "While this is on, a pill at the top of the screen shows a level chip when closed, unless a quest or a status capsule replaces that chip, and level, experience, gold, durability, bag slots, and the clock when open, with toasts underneath. Hover previews it, a click or a tap of the key pins it open, a second click or tap closes it, holding the key peeks, the key is set below or under Key Bindings, turning this off hides the pill and clears its notices except a card frozen in combat, and the quest tracker and action bars stay where they are.",
	keybinding = ACTION,
	extra_keybindings = { "EVERLOOK_SMART_ISLAND_DISMISS" },
	options = {
		size = { name = "Island size", default = 100, min = 80, max = 150, step = 5, unit = "%", description = "Scales the Island's text, surfaces, controls, and toasts together, from 80 to 150, in steps of 5. 100 is the normal size, the position sliders stay on their own options, and this number does nothing until Smart island is on." },
		opacity = { name = "Island opacity", default = 96, min = 60, max = 100, step = 2, unit = "%", description = "How solid the Island's dark surface is. Lower it to see more of the game behind the pill, toasts and open island. Text stays fully opaque." },
		position_x = { name = "Horizontal position", default = 0, min = -600, max = 600, step = 1, unit = " px", description = "Moves the closed pill and the open Island left or right of the screen center, from -600 to 600, in steps of 1. Zero stays centered, a negative number moves left, a positive number moves right, Distance from top stays on its own slider, either shape is pulled back toward the center when it would leave the screen, and this number does nothing until Smart island is on. You can also hold Shift and drag the Island." },
		position_top = { name = "Distance from top", default = 12, min = 8, max = 300, step = 1, unit = " px", description = "Sets how far the closed pill and the open Island sit below the top of the screen, from 8 to 300, in steps of 1. A larger number sits further down, Horizontal position stays on its own slider, either shape is moved back up when it would leave the screen, and this number does nothing until Smart island is on." },
		read_time = { name = "Notification read time", default = 4, min = 3, max = 10, step = 1, unit = " s", description = "Sets how many seconds a toast stays when that notice does not set its own time, from 3 to 10, in steps of 1. A toast already showing keeps its time, time spent waiting behind ordinary toasts does not count, and a notice waiting behind cards that need a decision counts down and can leave the inbox before it appears, the countdown pauses while the Island is open or the pointer is on that toast, the toast and its inbox row leave together when the time ends, a notice that never gets a toast uses the same time in the inbox, a notice that needs a decision stays until you dismiss it, a flight or other line that stays on the Island keeps its own time, and this number does nothing until Smart island is on. Right-click a notice to dismiss it sooner." },
		avoid_top_widgets = { name = "Stay clear of top-center widgets", default = true, description = "Move the pill below the battleground score and similar widgets while they show, so it never covers them. Your Distance from top still applies when no widget is showing." },
		closed_xp = { name = "Experience percent on the pill", default = true, description = "Show your experience percent beside the level while the Island is closed.", presets = { Quiet = false, Standard = true, Informative = true } },
		closed_clock = { name = "Clock on the pill", default = false, description = "Show the game time beside the level while the Island is closed.", presets = { Quiet = false, Standard = false, Informative = true } },
		closed_bags = { name = "Free slots on the pill", default = false, description = "Show free bag slots beside the level while the Island is closed. A warning shows there when slots run low, whether this is on or not.", presets = { Quiet = false, Standard = false, Informative = true } },
		hide_when_idle = { name = "Hide when idle", default = false, description = "Fade the closed pill out after five quiet seconds. It returns for a notice, a status, an active quest or the pointer. Hover where it was to bring it back." },
		hover_preview = { name = "Preview on hover", default = true, description = "Opens the Island while the pointer is over it, and closes that preview shortly after the pointer leaves. Click and the bound key still open and close it when this is off, and a pinned or held Island stays open after the pointer leaves." },
		combat_toasts = { name = "Show routine toasts in combat", default = false, description = "Lets a notice that is not a warning or an error toast during combat, while Show notification toasts is on. With this off, that notice stays in the inbox and does not toast, including after combat ends, while a warning, an error, or a notice with an item or spell button can still toast.", presets = { Quiet = false, Standard = false, Informative = false } },
		quest_context = { name = "Show active quest", default = false, description = "Shows the quest selected in the quest tracker in the Island capsule, and lists its objectives while the Island is open. An arrow points toward the quest when its waypoint or map pin is on your continent. The tracker stays as you left it. A pinned quest comes first. A suggestion, a progressing quest or a nearby quest can replace the selection when its option is on.", presets = { Quiet = false, Standard = true, Informative = true } },
		quest_plan = { name = "Suggest a quest order", default = true, description = "Ranks every quest in your log by straight-line distance and how many levels it sits from you, lists that order on the open Island, and shows the best one in the capsule. A pin still comes first, the quest tracker stays as you left it, a turn-in is ranked by distance only, a quest with no distance comes after one that has it, the suggestion holds through a smaller improvement and moves when another quest is at least a fifth better, when the suggested quest's turn-in state changes, or when the new leader has a distance or a known level the suggestion lacks, each quest is measured from where you are with no path between stops, and this stays quiet unless Show active quest is on." },
		quest_nearby = { name = "Show nearby watched quests", default = false, description = "Shows the closest watched quest on the Island when Suggest a quest order is off. A pinned or progressing quest comes first, and the tracker selection stays when no watched quest has a distance. Needs Show active quest." },
		quest_recent = { name = "Show progressing watched quests", default = false, description = "Shows the watched quest that just advanced on the Island for fifteen seconds after an objective count increases or an objective finishes, and a later one replaces it. Logging in does not count, an unwatched quest stays quiet, a pin or a suggestion still comes first, those fifteen seconds then give way to a nearby watched quest while that option is on and otherwise to the quest selected in the tracker, this stays quiet unless Show active quest is on, and turning this off leaves the capsule to those instead." },
		quest_title = { name = "Show quest title in the capsule", default = true, description = "Widens the closed Island strip and adds the quest name plus a segment for each of the first ten objectives that has a required count, even when that count is still zero, or that is finished. Turning this off leaves the icon and distance on a shorter strip, the open Island still lists the quest, the name stays in the tooltip, a status notice replaces the strip, and no quest leaves the strip hidden." },
		quest_distance_weight = { name = "Quest distance weight", default = 1, min = 0.25, max = 4, step = 0.25, percent = true, description = "A higher percentage makes a longer straight-line distance push a quest further down the suggested order, from 25% to 400%, in steps of 25%. This changes nothing unless Suggest a quest order or Next quest is on, the level weight stays on its own slider, distance still counts at the lowest setting, and a quest with no distance still comes after one that has it." },
		quest_level_weight = { name = "Quest level weight", default = 2, min = 0, max = 4, step = 0.5, percent = true, description = "A higher percentage pushes a quest further down the suggested order for each level it sits away from you, from 0% to 400%, in steps of 50%. This changes nothing unless Suggest a quest order or Next quest is on, each level more than two above you still adds eight to that quest's score even when this is zero, turn-ins and a quest whose level or yours is unknown use distance only, and Quest distance weight stays on its own slider." },
		source_repair = { name = "Show confirmed repair results", default = true, description = "Posts a notice once Auto repair has finished, naming the cost and whether the guild bank or your own gold paid. The request itself, a vendor you close before it finishes, a cost the client hides, and a result after three seconds stay quiet, gold short of the cost warns on the Island, and Auto repair has to be on.", presets = { Quiet = true, Standard = true, Informative = true } },
		source_sell = { name = "Show confirmed junk sales", default = true, description = "Posts one notice for the junk copper that has left your bags once selling stops. A visit that sells nothing stays quiet, an item still in the bag stays out of the total, a total the client hides stays quiet, turning this off leaves the sale and its chat line alone, and Sell junk has to be on.", presets = { Quiet = true, Standard = true, Informative = true } },
		source_flight = { name = "Show flight activity", default = false, description = "Shows this flight on the Island while you are in the air, with the elapsed time, adding the learned time left once a finished flight on that route has been recorded and saying when that estimate is exceeded. On the ground it stays quiet, the closed Island shows the flight mark and the time left or else the elapsed time, with a destination of 16 bytes or fewer beside it, a longer name or one with a vertical bar or a line break stays off that line, landing posts an arrival notice, turning this off clears the flight without that notice, and Flight time must also be on.", presets = { Quiet = false, Standard = true, Informative = true } },
		do_not_disturb = { name = "Do not disturb", default = false, description = "Only errors show as toasts. Every other notice goes to the inbox, where the unread count still shows. Stays on until you turn it off.", presets = { Quiet = false, Standard = false, Informative = false } },
		toast_count = { name = "Toasts on screen", default = 3, min = 1, max = 4, step = 1, description = "How many toasts can show at once below the island. Others wait in a short queue, with warnings first.", presets = { Quiet = 2, Standard = 3, Informative = 4 } },
		inbox_size = { name = "Inbox size", default = 10, min = 10, max = 30, step = 5, description = "How many notices the open island keeps. When it is full, the oldest routine notice goes first, and warnings and notices that need a decision are kept longest." },
		toasts = { name = "Show notification toasts", default = true, description = "Shows notifications below the Island, as many at once as Toasts on screen allows. Turning this off clears that stack and the waiting line and keeps the history, a card frozen in combat cannot leave until combat ends, and opening the Island shows the history instead.", presets = { Quiet = true, Standard = true, Informative = true } },
		reactions = { name = "Show reactions", default = true, description = "Flashes the island's body in a soft color when a warning or an error arrives, and when an addon sends a reaction such as a level-up. A flash is a tint and a line along the straight edges, never a sound or a movement, and never plays while Do not disturb is on.", presets = { Quiet = false, Standard = true, Informative = true } },
		reduced_motion = { name = "Reduce toast motion", default = false, description = "Fades toasts, and the hover open and close, without sliding them, and snaps the resting pill and the open chrome to their new size. Turning this off brings the slides back, a fade already running follows the new setting, and the level-up flash stays as it is." },
	},
	sections = {
		{
			name = "Presets",
			keys = {},
			after = function(layout)
				local descriptions = {
					Quiet = "Warnings and results only. Quest display and the optional feeds go off.",
					Standard = "Quest display, quest turn-ins, rare loot, the Hearthstone, mail and flights, with the warnings.",
					Informative = "Everything on, including reputation, professions, the recap and experience detail.",
				}
				for _, name in ipairs(PRESET_ORDER) do
					layout:AddInitializer(CreateSettingsButtonInitializer(name .. " preset", "Apply", function() return island.apply_preset(name) end,
						descriptions[name] .. " Placement, size and opacity stay as they are.", true))
				end
			end,
		},
		{
			name = "Placement",
			keys = { "size", "opacity", "position_x", "position_top", "avoid_top_widgets" },
			after = function(layout)
				layout:AddInitializer(CreateSettingsButtonInitializer("Reset Island position", "Reset", island.reset_position,
					"Restore top-center placement. Keep your chosen size and other preferences.", true))
			end,
		},
		{ name = "Opening", keys = { "hover_preview", "hide_when_idle", "read_time" } },
		{ name = "Closed pill", keys = { "closed_xp", "closed_clock", "closed_bags" } },
		{
			name = "Quest display",
			keys = { "quest_title", "quest_context", "quest_nearby", "quest_recent", "quest_plan", "quest_distance_weight", "quest_level_weight" },
		},
		{
			name = "Notices",
			keys = { "do_not_disturb", "toasts", "toast_count", "inbox_size", "reactions", "reduced_motion", "combat_toasts" },
			after = function(layout)
				layout:AddInitializer(CreateSettingsButtonInitializer("Preview notifications", "Preview", island.preview_notifications,
					"Show local examples with a warning, coins and a longer message. Enable Smart island first.", true))
			end,
		},
		{
			name = "Activity",
			keys = { "source_repair", "source_sell", "source_flight" },
		},
	},
	apply = apply,
	events = {
		"UI_SCALE_CHANGED",
		"DISPLAY_SIZE_CHANGED",
		"PLAYER_LOGOUT",
		"PLAYER_ENTERING_WORLD",
		"PLAYER_XP_UPDATE",
		"PLAYER_LEVEL_UP",
		"PLAYER_REGEN_ENABLED",
		"CHAT_MSG_COMBAT_XP_GAIN",
		"UPDATE_EXHAUSTION",
		"PLAYER_MONEY",
		"UPDATE_INVENTORY_DURABILITY",
		"BAG_UPDATE_DELAYED",
		"QUEST_TURNED_IN",
		"QUEST_LOG_UPDATE",
		"QUEST_WATCH_UPDATE",
		"QUEST_WATCH_LIST_CHANGED",
		"SUPER_TRACKING_CHANGED",
	},
	on_event = on_event,
})
