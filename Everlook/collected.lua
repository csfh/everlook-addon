local _, Everlook = ...

Everlook.collected = {}

local ROW_HEIGHT = 22
local search_text = ""

local ROLE_LABELS = { [1] = "giver", [2] = "turn-in", [4] = "objective", [5] = "rare" }

function Everlook.collected.filter(records, query)
	if type(records) ~= "table" then
		return {}
	end
	if type(query) ~= "string" or query == "" then
		return records
	end
	local needle = query:lower()
	local matches = {}
	for index = 1, #records do
		local record = records[index]
		local lowered = record.key
		if type(lowered) ~= "string" and type(record.text) == "string" then
			lowered = record.text:lower()
		end
		if type(lowered) == "string" and lowered:find(needle, 1, true) then
			matches[#matches + 1] = record
		end
	end
	return matches
end

local function row_for(bucket, key)
	if not Everlook.world or not Everlook.world.row then
		return nil
	end
	local id = key
	if type(key) == "string" and not key:find(":", 1, true) then
		id = tonumber(key) or key
	end
	return Everlook.world.row(bucket, id)
end

function Everlook.collected.location_text(bucket, key)
	local row = row_for(bucket, key)
	if type(row) ~= "table" or type(row.locations) ~= "table" then
		return nil
	end
	local lines = {}
	for index = 1, #row.locations do
		local location = row.locations[index]
		if type(location) == "table" and type(location.mapId) == "number" then
			local map = Everlook.world.row("maps", location.mapId)
			local name = type(map) == "table" and type(map.name) == "string" and map.name or ("Map " .. location.mapId)
			local x = type(location.x) == "number" and string.format("%.1f", location.x / 10) or "?"
			local y = type(location.y) == "number" and string.format("%.1f", location.y / 10) or "?"
			local text = name .. " " .. x .. ", " .. y
			local role = ROLE_LABELS[location.role]
			if role then
				text = text .. " " .. role
			end
			lines[#lines + 1] = text
		end
	end
	if #lines == 0 then
		return nil
	end
	return table.concat(lines, "; ")
end

function Everlook.collected.address(bucket, key)
	local kinds = { items = "item", spells = "spell", npcs = "npc", objects = "object", quests = "quest" }
	local kind = kinds[bucket]
	if not kind then
		return nil
	end
	if type(key) == "string" and key:find(":", 1, true) then
		return nil
	end
	local id = tonumber(key)
	if not id then
		return nil
	end
	return Everlook.links.url(kind, id)
end

function Everlook.collected.insert(bucket, key)
	local url = Everlook.collected.address(bucket, key)
	if not url or type(ChatFrame_OpenChat) ~= "function" then
		return false
	end
	ChatFrame_OpenChat((url:gsub("^https://", "")))
	return true
end

local frame
local nav_label
local nav_prev
local nav_next
local bucket_box
local bucket_bar
local record_box
local record_bar
local empty
local selected_bucket
local selected_record_id
local places

local function retain_scroll()
	return ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition or nil
end

local function apply_provider(scroll_box, entries, keep_scroll)
	local retain = keep_scroll and retain_scroll() or nil
	scroll_box:SetDataProvider(CreateDataProvider(entries), retain)
end

local function paint_bucket(button, element_data)
	local selected = element_data.bucket == selected_bucket
	button.highlight:SetShown(selected)
	button.label:SetFontObject(selected and "GameFontHighlight" or "GameFontNormal")
end

-- The page of the selected bucket being looked at, and a search across pages.
-- Only one page is read at a time, and a search reads the rest a few at a time.
local page_at = {}
local scan

local function page_total(bucket)
	return Everlook.world.page_count(bucket)
end

local function current_page(bucket)
	local page = page_at[bucket] or 1
	local total = page_total(bucket)
	if page > total then
		page = total
	end
	if page < 1 then
		page = 1
	end
	return page
end

local function describe_page(bucket, page)
	local first, last, count = Everlook.world.page_range(bucket, page)
	local total = page_total(bucket)
	if total <= 1 then
		return count .. " rows"
	end
	local span = last and (first .. "-" .. last) or (first .. " and up")
	return "Page " .. page .. " of " .. total .. ", ids " .. span .. ", " .. count .. " rows"
end

local function show_navigation(bucket, page)
	if not nav_label then
		return
	end
	local total = page_total(bucket)
	if scan then
		nav_label:SetText(scan.done and (#scan.results .. " found in " .. scan.total .. " pages") or ("Searching " .. scan.index .. " of " .. scan.total .. " pages, " .. #scan.results .. " found"))
	else
		nav_label:SetText(describe_page(bucket, page))
	end
	local browsing = not scan
	if nav_prev and nav_prev.SetEnabled then
		nav_prev:SetEnabled(browsing and page > 1)
	end
	if nav_next and nav_next.SetEnabled then
		nav_next:SetEnabled(browsing and page < total)
	end
end

-- A number typed in the box jumps to the page that holds that id. Anything else
-- narrows the rows of the page being looked at.
local function typed_id()
	return search_text:match("^%s*(%d+)%s*$")
end

local function filter_text()
	return typed_id() and "" or search_text
end

local function refresh()
	if not bucket_box then
		return
	end
	-- Only the chosen bucket is listed and sorted. The others show a count.
	local entries = Everlook.world.collected_buckets()
	local still
	for index = 1, #entries do
		if entries[index].bucket == selected_bucket then
			still = entries[index]
		end
	end
	if not still then
		still = entries[1]
		selected_bucket = still and still.bucket or nil
	end
	local shown = #entries > 0
	bucket_box:SetShown(shown)
	bucket_bar:SetShown(shown)
	record_box:SetShown(shown)
	record_bar:SetShown(shown)
	empty:SetShown(not shown)
	if not shown then
		return
	end
	local page = current_page(selected_bucket)
	page_at[selected_bucket] = page
	show_navigation(selected_bucket, page)
	local records = scan and scan.results or Everlook.collected.filter(Everlook.world.page_records(selected_bucket, page), filter_text())
	local record = records[1]
	if selected_record_id then
		local found = false
		for index = 1, #records do
			if records[index].id == selected_record_id then
				record = records[index]
				found = true
				break
			end
		end
		if not found then
			selected_record_id = record and record.id or nil
		end
	elseif record then
		selected_record_id = record.id
	end
	apply_provider(bucket_box, entries, true)
	apply_provider(record_box, records, true)
	if places then
		local text = record and Everlook.collected.location_text(selected_bucket, record.id) or nil
		places:SetText(text or "")
	end
end

local function stop_scan()
	scan = nil
	if frame then
		frame:SetScript("OnUpdate", nil)
	end
end

local function choose(bucket)
	stop_scan()
	selected_bucket = bucket
	selected_record_id = nil
	refresh()
end

local function go(step)
	if not selected_bucket then
		return
	end
	stop_scan()
	page_at[selected_bucket] = current_page(selected_bucket) + step
	selected_record_id = nil
	refresh()
end

local MATCH_LIMIT = 500
local SCAN_MS = 2

-- Looks for a name in every page of the bucket, a few at a time, and shows what
-- it has found as it goes. A thousand pages are not read in one frame.
local function scan_step()
	if not scan or scan.done then
		return
	end
	local began = type(debugprofilestop) == "function" and debugprofilestop() or nil
	local grown = false
	while scan.index < scan.total do
		scan.index = scan.index + 1
		local found = Everlook.collected.filter(Everlook.world.page_records(scan.bucket, scan.index), scan.needle)
		for index = 1, #found do
			if #scan.results < MATCH_LIMIT then
				scan.results[#scan.results + 1] = found[index]
				grown = true
			end
		end
		if not began or debugprofilestop() - began >= SCAN_MS then
			break
		end
	end
	if scan.index >= scan.total or #scan.results >= MATCH_LIMIT then
		scan.done = true
		frame:SetScript("OnUpdate", nil)
		grown = true
	end
	if grown then
		refresh()
	else
		show_navigation(scan.bucket, current_page(scan.bucket))
	end
end

local function start_scan()
	if not selected_bucket or typed_id() or search_text == "" then
		return
	end
	scan = { bucket = selected_bucket, needle = search_text, index = 0, total = page_total(selected_bucket), results = {}, done = false }
	selected_record_id = nil
	frame:SetScript("OnUpdate", scan_step)
	scan_step()
	refresh()
end

local function prepare_row(button)
	local highlight = button:CreateTexture(nil, "BACKGROUND")
	highlight:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
	highlight:SetBlendMode("ADD")
	highlight:SetAllPoints()
	highlight:Hide()
	button.highlight = highlight

	button:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
	local hover = button:GetHighlightTexture()
	if hover then
		hover:SetAlpha(0.35)
	end

	local detail = button:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	detail:SetPoint("RIGHT", -8, 0)
	detail:SetJustifyH("RIGHT")
	detail:SetWordWrap(false)
	button.detail = detail

	local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("LEFT", 8, 0)
	label:SetPoint("RIGHT", detail, "LEFT", -8, 0)
	label:SetJustifyH("LEFT")
	label:SetWordWrap(false)
	label:SetMaxLines(1)
	button.label = label
end

local function init_bucket(button, element_data)
	if not button.label then
		prepare_row(button)
		button:RegisterForClicks("LeftButtonUp")
		button:SetScript("OnClick", function(self)
			local data = self:GetElementData()
			if data and data.bucket then
				choose(data.bucket)
			end
		end)
	end
	button.label:SetText(element_data.label)
	button.detail:SetText(tostring(element_data.count))
	paint_bucket(button, element_data)
end

local function init_record(button, element_data)
	if not button.label then
		prepare_row(button)
	end
	button.label:SetFontObject("GameFontHighlight")
	button.label:SetText(element_data.text)
	local where = element_data.id == selected_record_id and Everlook.collected.location_text(selected_bucket, element_data.id) or nil
	button.detail:SetText(where or element_data.id)
	if not button.everlook_click then
		button.everlook_click = true
		if button.RegisterForClicks then
			button:RegisterForClicks("LeftButtonUp")
		end
		button:SetScript("OnClick", function(self)
			local data = self:GetElementData()
			if not data then
				return
			end
			if IsShiftKeyDown and IsShiftKeyDown() then
				Everlook.collected.insert(selected_bucket, data.id)
				return
			end
			selected_record_id = data.id
			refresh()
		end)
	end
end

local function create_list(parent, initializer)
	local scroll_box = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
	local scroll_bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
	scroll_bar:SetPoint("TOPLEFT", scroll_box, "TOPRIGHT", 4, 0)
	scroll_bar:SetPoint("BOTTOMLEFT", scroll_box, "BOTTOMRIGHT", 4, 0)
	local view = CreateScrollBoxListLinearView(1, 1, 2, 2, 0)
	view:SetElementExtent(ROW_HEIGHT)
	view:SetElementInitializer("Button", initializer)
	ScrollUtil.InitScrollBoxListWithScrollBar(scroll_box, scroll_bar, view)
	return scroll_box, scroll_bar
end

-- The lists are built the first time the page is shown, so a player who
-- never opens it pays nothing beyond one empty frame.
local function build(panel)
	local heading = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
	heading:SetPoint("TOPLEFT", 8, -8)
	heading:SetText("Collected data")

	local blank = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	blank:SetPoint("CENTER", 0, -8)
	blank:SetText("Nothing collected yet.")
	blank:Hide()
	empty = blank

	local where = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	where:SetPoint("BOTTOMLEFT", 8, 8)
	where:SetPoint("BOTTOMRIGHT", -16, 8)
	if where.SetJustifyH then
		where:SetJustifyH("LEFT")
	end
	if where.SetWordWrap then
		where:SetWordWrap(false)
	end
	where:SetText("")
	places = where
	panel.places = where

	local buckets, bucket_scroll = create_list(panel, init_bucket)
	buckets:SetPoint("TOPLEFT", 8, -64)
	buckets:SetPoint("BOTTOMLEFT", 8, 32)
	buckets:SetWidth(200)

	local records, record_scroll = create_list(panel, init_record)
	records:SetPoint("TOPLEFT", bucket_scroll, "TOPRIGHT", 14, 0)
	records:SetPoint("BOTTOMLEFT", bucket_scroll, "BOTTOMRIGHT", 14, 0)
	records:SetPoint("RIGHT", panel, "RIGHT", -24, 0)

	local search = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
	search:SetPoint("TOPLEFT", 228, -8)
	search:SetPoint("TOPRIGHT", -28, -8)
	search:SetSize(400, 22)
	if search.SetAutoFocus then
		search:SetAutoFocus(false)
	end
	search:SetScript("OnTextChanged", function(self)
		search_text = self.GetText and self:GetText() or ""
		stop_scan()
		local id = typed_id()
		if id and selected_bucket then
			page_at[selected_bucket] = Everlook.world.page_for_id(selected_bucket, tonumber(id))
			selected_record_id = nil
		end
		refresh()
	end)
	-- Enter looks for the name in every page, not just this one.
	search:SetScript("OnEnterPressed", function()
		start_scan()
	end)

	local previous = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	previous:SetSize(24, 22)
	previous:SetPoint("TOPLEFT", 228, -36)
	previous:SetText("<")
	previous:SetScript("OnClick", function()
		go(-1)
	end)
	local following = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	following:SetSize(24, 22)
	following:SetPoint("TOPLEFT", 256, -36)
	following:SetText(">")
	following:SetScript("OnClick", function()
		go(1)
	end)
	local where_label = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	where_label:SetPoint("LEFT", following, "RIGHT", 8, 0)
	where_label:SetText("")
	nav_prev, nav_next, nav_label = previous, following, where_label

	bucket_box = buckets
	bucket_bar = bucket_scroll
	record_box = records
	record_bar = record_scroll
end

-- The frame the settings window shows as the Collected data page. The
-- settings window parents and sizes it, so it has no window chrome of its own.
function Everlook.collected.page()
	if frame then
		return frame
	end
	local panel = CreateFrame("Frame", "EverlookCollectedPage")
	panel:Hide()
	panel:SetScript("OnShow", function(self)
		if not bucket_box then
			build(self)
		end
		refresh()
	end)
	-- A search stops with the page, so nothing keeps reading pages unseen.
	panel:SetScript("OnHide", stop_scan)
	frame = panel
	return panel
end
