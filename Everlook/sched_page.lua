local _, Everlook = ...

-- The Performance page: what the scheduler is doing right now. Nothing here is
-- built until the page is first shown, and it only reads while it is shown.

local REFRESH = 0.25
local STRIP_WIDTH, STRIP_HEIGHT = 360, 56
local BAR_GAP = 1
local ROW_HEIGHT = 20

local NAMES = {
	items = "Item reads",
	collected_scan = "Collected search",
	segments = "World data",
	defer = "Event scans",
}

local STATES = {
	working = { "Working", 0.45, 0.85, 0.5 },
	idle = { "Idle", 0.55, 0.55, 0.55 },
	paused = { "Waiting for combat", 1, 0.82, 0.3 },
	sleeping = { "Sleeping", 0.55, 0.7, 0.9 },
	resting = { "Resting after errors", 1, 0.4, 0.35 },
}

local COLUMNS = {
	{ key = "name", label = "Task", x = 8, width = 150, justify = "LEFT" },
	{ key = "state", label = "Now", x = 164, width = 140, justify = "LEFT" },
	{ key = "runs", label = "Runs", x = 310, width = 60, justify = "RIGHT" },
	{ key = "average", label = "Avg ms", x = 376, width = 60, justify = "RIGHT" },
	{ key = "worst", label = "Worst ms", x = 442, width = 66, justify = "RIGHT" },
	{ key = "errors", label = "Errors", x = 514, width = 56, justify = "RIGHT" },
}

local frame
local built
local bars = {}
local rows = {}
local texts = {}

local function text(panel, template, justify, width)
	local line = panel:CreateFontString(nil, "OVERLAY", template)
	if width and line.SetWidth then
		line:SetWidth(width)
	end
	if line.SetJustifyH then
		line:SetJustifyH(justify or "LEFT")
	end
	if line.SetWordWrap then
		line:SetWordWrap(false)
	end
	return line
end

local function number(value)
	if value == math.floor(value) then
		return tostring(value)
	end
	return (string.format("%.2f", value):gsub("0+$", ""))
end

local function row_at(panel, index)
	if rows[index] then
		return rows[index]
	end
	local row = {}
	for _, column in ipairs(COLUMNS) do
		local line = text(panel, "GameFontHighlight", column.justify, column.width)
		line:SetPoint("TOPLEFT", column.x, -(176 + index * ROW_HEIGHT))
		row[column.key] = line
	end
	rows[index] = row
	return row
end

local function draw_strip(snapshot)
	local frames, budget = snapshot.frames, snapshot.budget
	-- Twice the budget fits the strip, so a frame that stays inside it is half
	-- the height and one that overruns reaches the top.
	local scale = STRIP_HEIGHT / (budget * 2)
	local count = #frames
	for index = 1, #bars do
		local bar = bars[index]
		local used = frames[count - #bars + index]
		if used then
			local height = math.min(STRIP_HEIGHT, math.max(1, used * scale))
			bar:SetHeight(height)
			if used > budget then
				bar:SetColorTexture(1, 0.4, 0.35, 0.9)
			else
				bar:SetColorTexture(0.45, 0.85, 0.5, 0.9)
			end
			bar:Show()
		else
			bar:Hide()
		end
	end
end

local function refresh()
	if not built or not Everlook.sched or not Everlook.sched.snapshot then
		return
	end
	local snapshot = Everlook.sched.snapshot()
	local fps = snapshot.fps and string.format("%d frames a second", snapshot.fps + 0.5) or "frame rate unknown"
	texts.summary:SetText(string.format("Each frame gives all background work %s ms, split between the tasks below. %s%s.",
		number(snapshot.budget), fps, snapshot.combat and ", in combat" or ""))
	texts.queued:SetText(snapshot.queued > 0 and (snapshot.queued .. " event scans waiting") or "No event scans waiting")
	draw_strip(snapshot)
	local total = 0
	for _, task in ipairs(snapshot.tasks) do
		total = total + task.ms
	end
	for index, task in ipairs(snapshot.tasks) do
		local row = row_at(frame, index)
		local state = STATES[task.state] or STATES.idle
		row.name:SetText(NAMES[task.name] or task.name)
		row.state:SetText(state[1])
		row.state:SetTextColor(state[2], state[3], state[4])
		row.runs:SetText(tostring(task.runs))
		row.average:SetText(task.runs > 0 and number(math.floor(task.ms / task.runs * 100 + 0.5) / 100) or "0")
		row.worst:SetText(number(math.floor(task.worst * 100 + 0.5) / 100))
		row.errors:SetText(tostring(task.errors))
		if task.errors > 0 then
			row.errors:SetTextColor(1, 0.4, 0.35)
		else
			row.errors:SetTextColor(0.55, 0.55, 0.55)
		end
		for _, line in pairs(row) do
			line:Show()
		end
	end
	for index = #snapshot.tasks + 1, #rows do
		for _, line in pairs(rows[index]) do
			line:Hide()
		end
	end
	texts.total:SetText(total > 0 and string.format("%s ms of work this session", number(math.floor(total + 0.5))) or "")
end

local function build(panel)
	local heading = text(panel, "GameFontNormalHuge")
	heading:SetPoint("TOPLEFT", 8, -8)
	heading:SetText("Performance")

	texts.summary = text(panel, "GameFontDisable")
	texts.summary:SetPoint("TOPLEFT", 8, -40)
	texts.summary:SetPoint("TOPRIGHT", -16, -40)

	local strip_label = text(panel, "GameFontNormal")
	strip_label:SetPoint("TOPLEFT", 8, -68)
	strip_label:SetText("Time spent in recent frames that had background work")

	local strip = CreateFrame("Frame", nil, panel)
	strip:SetPoint("TOPLEFT", 8, -88)
	strip:SetSize(STRIP_WIDTH, STRIP_HEIGHT)
	local floor = strip:CreateTexture(nil, "BACKGROUND")
	floor:SetAllPoints()
	floor:SetColorTexture(1, 1, 1, 0.05)
	-- Half the strip is the budget.
	local line = strip:CreateTexture(nil, "ARTWORK")
	line:SetPoint("LEFT", strip, "BOTTOMLEFT", 0, STRIP_HEIGHT / 2)
	line:SetPoint("RIGHT", strip, "BOTTOMRIGHT", 0, STRIP_HEIGHT / 2)
	line:SetHeight(1)
	line:SetColorTexture(1, 0.82, 0.3, 0.6)
	local budget_label = text(panel, "GameFontDisable", "LEFT")
	budget_label:SetPoint("LEFT", strip, "RIGHT", 8, 0)
	budget_label:SetText("Budget")
	local width = (STRIP_WIDTH - BAR_GAP * 59) / 60
	for index = 1, 60 do
		local bar = strip:CreateTexture(nil, "OVERLAY")
		bar:SetPoint("BOTTOMLEFT", (index - 1) * (width + BAR_GAP), 0)
		bar:SetWidth(width)
		bar:SetHeight(1)
		bar:Hide()
		bars[index] = bar
	end

	texts.queued = text(panel, "GameFontDisable")
	texts.queued:SetPoint("TOPLEFT", 8, -152)

	for _, column in ipairs(COLUMNS) do
		local label = text(panel, "GameFontNormal", column.justify, column.width)
		label:SetPoint("TOPLEFT", column.x, -176)
		label:SetText(column.label)
	end

	texts.total = text(panel, "GameFontDisable")
	texts.total:SetPoint("BOTTOMLEFT", 8, 32)

	local note = text(panel, "GameFontDisable")
	note:SetPoint("BOTTOMLEFT", 8, 8)
	note:SetPoint("BOTTOMRIGHT", -16, 8)
	note:SetText("Work that can wait is queued and done a little each frame. Most of it stops in combat.")
	built = true
end

-- The frame the settings window shows as the Performance page. The window
-- parents and sizes it.
function Everlook.sched.page()
	if frame then
		return frame
	end
	local panel = CreateFrame("Frame", "EverlookPerformancePage")
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
	-- Nothing reads the scheduler while the page is closed.
	panel:SetScript("OnHide", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	frame = panel
	return panel
end
