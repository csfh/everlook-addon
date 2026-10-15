local _, Everlook = ...

Everlook.report = {}

-- `/everlook report <words>` saves what the player wrote, with facts about the
-- install, in the saved file. The desktop app sends it to the site on its next
-- sync. Nothing leaves the game by itself and nothing depends on the clipboard.
-- The caps and the shape are written in docs/contracts.md.
local MAX_REPORTS = 5
local MAX_AGE = 14 * 24 * 3600
local MAX_TEXT = 1000
local MAX_FACTS = 3000
local MAX_ERRORS = 5
local MAX_ERROR_LINE = 200

-- Cuts to `limit` characters, never inside a multi-byte one.
function Everlook.report.cut(text, limit)
	if type(text) ~= "string" then return "" end
	local count, position = 0, 1
	while position <= #text do
		local lead = text:byte(position)
		local size = lead >= 240 and 4 or lead >= 224 and 3 or lead >= 192 and 2 or 1
		if count == limit then return text:sub(1, position - 1) end
		count = count + 1
		position = position + size
	end
	return text
end

local function clean(words)
	words = tostring(words or ""):gsub("[%c]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	return words
end

function Everlook.report.facts()
	local lines = {}
	local where = Everlook.where and Everlook.where.text and Everlook.where.text() or ""
	if where ~= "" then lines[#lines + 1] = where end
	local errors = Everlook.errors and Everlook.errors.list() or {}
	local first = math.max(1, #errors - MAX_ERRORS + 1)
	for index = first, #errors do
		local item = errors[index]
		lines[#lines + 1] = "Error from " .. tostring(item.owner) .. ": " .. Everlook.report.cut(clean(item.message), MAX_ERROR_LINE)
	end
	return Everlook.report.cut(table.concat(lines, "\n"), MAX_FACTS)
end

local function now()
	return type(time) == "function" and time() or 0
end

-- Saves one report and returns it, or nil when there were no words.
function Everlook.report.add(words)
	words = Everlook.report.cut(clean(words), MAX_TEXT)
	if words == "" then return nil end
	EverlookDB = EverlookDB or {}
	local list = type(EverlookDB.reports) == "table" and EverlookDB.reports or {}
	local at = now()
	local kept = {}
	for _, report in ipairs(list) do
		if type(report) == "table" and type(report.at) == "number" and at - report.at <= MAX_AGE then kept[#kept + 1] = report end
	end
	local report = {
		id = Everlook.hash.sha256(at .. ":" .. #kept .. ":" .. words):sub(1, 8),
		at = at,
		text = words,
		facts = Everlook.report.facts(),
	}
	kept[#kept + 1] = report
	while #kept > MAX_REPORTS do table.remove(kept, 1) end
	EverlookDB.reports = kept
	return report
end

function Everlook.report.command(words)
	local report = Everlook.report.add(words)
	if not report then
		Everlook.say("Write what went wrong after the command, such as /everlook report the vendor sells nothing.")
		return
	end
	Everlook.say("Saved. The Everlook app sends it with your next upload, with the build, your place and the modules you have on. No character name is in it.")
end
