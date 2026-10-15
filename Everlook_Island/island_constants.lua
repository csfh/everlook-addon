-- The fixed numbers, colours and texts of smart_island.lua, kept out of it so that file
-- stays well under Lua 5.1's 200 locals per chunk. Loaded after island_toasts.lua and
-- before smart_island.lua (TOC order is the wiring).
local Everlook = Everlook
local grid = Everlook.island_grid

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
-- The quest events arrive in bursts. The first one scans at once, and the rest
-- inside the window collapse into one scan when it ends.
local QUEST_SCAN_WINDOW = 0.5
-- A preset sets what the player chooses to see. Placement, size, opacity and
-- the key stay as they are. Each option carries its value under each preset,
-- so the options a feed addon adds follow the preset too.
local PRESET_ORDER = { "Quiet", "Standard", "Informative" }
local QUEST_COLOR = { 1, 0.82, 0.25, 1 }
local REACTION_KEYS = { kind = true, strength = true, source = true }
local SECTION_CHANGES = { title = true, order = true, blocks = true, expires = true }
-- Moving from the Island onto one of its own controls is a leave for the frame
-- and an enter for the control. A control that does not tell the Island it was
-- entered (the scroll thumb, the experience heading, the buttons on a notice)
-- would otherwise close it under the pointer. So the close waits, and checks
-- whether the pointer is still over the Island, and checks again until it is not.
local CLOSE_DELAY = 0.1

Everlook.island_const = {
	ACTION = ACTION,
	HOLD = HOLD,
	LIST_MAX = LIST_MAX,
	STATUS_MAX = STATUS_MAX,
	CLOSED_W = CLOSED_W,
	CLOSED_H = CLOSED_H,
	QUEUE_MAX = QUEUE_MAX,
	TOAST_GAP = TOAST_GAP,
	MOTION = MOTION,
	ENTER_TIME = ENTER_TIME,
	EXIT_TIME = EXIT_TIME,
	OPEN_W = OPEN_W,
	NARROW_W = NARROW_W,
	COLORS = COLORS,
	ROLES = ROLES,
	ART = ART,
	EMPTY_HINT = EMPTY_HINT,
	QUEST_SCAN_WINDOW = QUEST_SCAN_WINDOW,
	PRESET_ORDER = PRESET_ORDER,
	QUEST_COLOR = QUEST_COLOR,
	REACTION_KEYS = REACTION_KEYS,
	SECTION_CHANGES = SECTION_CHANGES,
	CLOSE_DELAY = CLOSE_DELAY,
}
