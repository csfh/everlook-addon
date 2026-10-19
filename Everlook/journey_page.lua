local _, Everlook = ...

-- The Journey page of the settings window: what the character playing now has recorded, and where
-- signing stands. Nothing here is built until the page is first shown, and it only reads while it is shown.
-- It is a read-only summary: the journey itself is seen on everlook.ing, and the game has no copy and paste.

local REFRESH = 1
local LABEL_X, VALUE_X, VALUE_WIDTH = 8, 230, 120
local ROW = 22

local COUNTS = {
	{ key = "completed", label = "Quests completed" },
	{ key = "started", label = "Quests in progress" },
	{ key = "abandoned", label = "Quests given up" },
	{ key = "met", label = "Creatures met" },
	{ key = "zones", label = "Zones found" },
	{ key = "areas", label = "Places discovered" },
}

local function plural(count, one, many)
	return count .. " " .. (count == 1 and one or many)
end

-- What the page says, from a summary: a status line, the counts, and where signing stands. Pure, so it can be tested.
function Everlook.journey.lines(summary)
	local lines = { status = "", counts = {}, signing = {} }
	if not summary.available then
		lines.status = "This game client cannot keep a journey."
		return lines
	end
	local profile = summary.profile
	if not summary.enabled then
		lines.status = "Off. Turn on Keep a journey on the main Everlook page, and each character you play starts one."
		return lines
	end
	if profile then
		lines.status = "On for " .. profile.name .. " of " .. profile.realm .. "."
	else
		lines.status = "On. This character has not recorded anything yet."
	end
	local counts = summary.counts or {}
	for index, entry in ipairs(COUNTS) do
		lines.counts[index] = { label = entry.label, value = tostring(counts[entry.key] or 0) }
	end
	lines.recorded = plural(summary.rows or 0, "thing recorded", "things recorded") .. (summary.positions and ", with where you stood." or ", without where you stood.")
	lines.signing[1] = plural(summary.signed or 0, "chunk is signed and ready for the app", "chunks are signed and ready for the app")
	local waiting = (summary.waiting or 0) + ((summary.open or 0) > 0 and 1 or 0)
	if waiting > 0 then
		lines.signing[2] = plural(waiting, "chunk is waiting to be signed", "chunks are waiting to be signed") .. ", at logout and in the background."
	end
	if summary.token then
		lines.signing[#lines.signing + 1] = "Signed with your Everlook token."
	else
		lines.signing[#lines.signing + 1] = "Place the token in the Everlook app, and the journey is signed."
	end
	return lines
end

local frame
local built
local texts = {}
local count_rows = {}

local function text(panel, template, justify, width)
	local line = panel:CreateFontString(nil, "OVERLAY", template)
	if width and line.SetWidth then
		line:SetWidth(width)
	end
	if line.SetJustifyH then
		line:SetJustifyH(justify or "LEFT")
	end
	if line.SetWordWrap then
		line:SetWordWrap(true)
	end
	return line
end

local function build(panel)
	local title = text(panel, "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", LABEL_X, -8)
	title:SetText("Journey")
	texts.status = text(panel, "GameFontHighlight", "LEFT", 520)
	texts.status:SetPoint("TOPLEFT", LABEL_X, -36)
	local top = -84
	for index = 1, #COUNTS do
		local label = text(panel, "GameFontHighlight", "LEFT", VALUE_X - LABEL_X)
		label:SetPoint("TOPLEFT", LABEL_X, top - (index - 1) * ROW)
		local value = text(panel, "GameFontNormal", "RIGHT", VALUE_WIDTH)
		value:SetPoint("TOPLEFT", VALUE_X, top - (index - 1) * ROW)
		count_rows[index] = { label = label, value = value }
	end
	texts.recorded = text(panel, "GameFontDisable", "LEFT", 520)
	texts.recorded:SetPoint("TOPLEFT", LABEL_X, top - #COUNTS * ROW - 8)
	texts.signing = text(panel, "GameFontHighlight", "LEFT", 520)
	texts.signing:SetPoint("TOPLEFT", LABEL_X, top - #COUNTS * ROW - 40)
	local note = text(panel, "GameFontDisable", "LEFT", 520)
	note:SetPoint("BOTTOMLEFT", LABEL_X, 8)
	note:SetText("Everlook's app sends the journey. See it on everlook.ing under Journey, where you choose how each character is shown and who sees it.")
	built = true
end

local function refresh()
	local lines = Everlook.journey.lines(Everlook.journey.summary())
	texts.status:SetText(lines.status)
	for index, row in ipairs(count_rows) do
		local entry = lines.counts[index]
		row.label:SetText(entry and entry.label or "")
		row.value:SetText(entry and entry.value or "")
	end
	texts.recorded:SetText(lines.recorded or "")
	texts.signing:SetText(table.concat(lines.signing, "\n"))
end

-- The frame the settings window shows as the Journey page. The window parents and sizes it.
function Everlook.journey.page()
	if frame then
		return frame
	end
	local panel = CreateFrame("Frame", "EverlookJourneyPage")
	panel:Hide()
	local waited = 0
	panel:SetScript("OnShow", function(self)
		if not built then
			build(self)
		end
		waited = 0
		refresh()
		self:SetScript("OnUpdate", function(_, elapsed)
			waited = waited + elapsed
			if waited >= REFRESH then
				waited = 0
				refresh()
			end
		end)
	end)
	-- Nothing reads the journey while the page is closed.
	panel:SetScript("OnHide", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	frame = panel
	return panel
end
