local _, Everlook = ...

-- Keeps what is saved up to date as the world changes, in small steps.
--
-- A page that changed needs two things done: its rows saved as the page's
-- own string, and its upload segment packed, hashed and listed in the manifest
-- that one signature covers. Both wait until the page has been quiet for a
-- while, then run a millisecond or so a frame, never in combat. Logout saves
-- every page that changed, since nothing else would keep it, and builds
-- upload segments only as far as the time allows.

Everlook.segments = {}
local S = Everlook.segments
local P = Everlook.pages

local floor = math.floor
local internal = Everlook.world.internal

-- The site reads a number in a `sources` list as one of its five fixed names,
-- so a source that is only a word must stay a word. That column is left out of
-- the string table.
local sources_column = {}
for bucket, columns in pairs(internal.columns) do
	for index = 1, #columns do
		if columns[index] == "sources" then
			sources_column[bucket] = index
		end
	end
end

-- The second part of a segment's name says how rows are grouped: by the page
-- that holds them.
local GROUPING = 1

local WORK_MS = 1.5
local SLOW_WORK_MS = 0.75
local PACK_MS = 0.5
local HASH_BLOCKS = 6
local QUIET = 15
local MAX_WAIT = 120
local COMMIT_EVERY = 300
local LOGOUT_MS = 400
local CHECK_EVERY = 10

local queue = {}
local published = {}
local staged = {}
local job
local committing
local pads, pads_secret
local last_commit = 0
local last_check = 0
local next_poll = 0
local index_turn = false
local total_bytes = 0
local stats = {}
local frame

local function now()
	return type(GetTime) == "function" and GetTime() or 0
end

local function clock()
	return type(debugprofilestop) == "function" and debugprofilestop() or 0
end

function S.enabled()
	return P.enabled()
end

local function wake()
	if frame and not frame:IsShown() then
		frame:Show()
	end
end

local function segment_name(page)
	return page.bucket .. "." .. GROUPING .. "." .. page.start
end

-- A page changed. It waits its turn, and waits longer each time it changes again.
P.on_dirty = function(page)
	local t = now()
	page.touched = t
	if not page.queued then
		page.queued = true
		page.first_dirty = t
		queue[#queue + 1] = page
		wake()
	end
end

-- A page that was cut in two no longer matches the segment listed for it, and
-- the rows it gave up would be listed twice. It is left out until it is packed again.
P.on_split = function(page)
	local name = segment_name(page)
	staged[name] = nil
	if published[name] then
		total_bytes = total_bytes - (published[name].bytes or 0)
		published[name] = nil
	end
end

local function dequeue(page)
	for index = 1, #queue do
		if queue[index] == page then
			queue[index] = queue[#queue]
			queue[#queue] = nil
			break
		end
	end
	page.queued = false
	page.first_dirty = nil
end

local function settle_queue(page)
	if page.queued and not page.raw_dirty and not page.seg_dirty then
		dequeue(page)
	end
end

function S.reset()
	queue, published, staged = {}, {}, {}
	job, committing = nil, nil
	total_bytes = 0
	last_commit = now()
	stats = {}
end

-- What the saved manifest says about each segment, and only for a segment the
-- file really holds. A whole world beside a manifest means an older addon ran
-- in between, and the manifest cannot be trusted.
local function read_saved()
	published = {}
	local db = EverlookDB
	if type(db) ~= "table" or type(db.manifest) ~= "string" or type(db.segments) ~= "table" then
		return
	end
	if db.world ~= nil then
		db.manifest, db.segments = nil, nil
		return
	end
	for name, count, sha in db.manifest:gmatch("([%w]+%.%d+%.%d+)=(%d+):(%x+)") do
		if type(db.segments[name]) == "string" then
			published[name] = { rows = tonumber(count), sha = sha, bytes = #db.segments[name] }
			total_bytes = total_bytes + #db.segments[name]
		end
	end
end

-- Called once the pages are in place, while the loading screen is up.
function S.rebuild()
	-- Pages that moving the old collection in has already marked stay in line.
	local waiting = {}
	for index = 1, #queue do
		if P.by_name(queue[index].name) == queue[index] then
			waiting[#waiting + 1] = queue[index]
		end
	end
	S.reset()
	queue = waiting
	read_saved()
	local stale = type(EverlookDB) == "table" and type(EverlookDB.staleSegments) == "table" and EverlookDB.staleSegments or {}
	local named = {}
	for index = 1, #stale do
		named[stale[index]] = true
	end
	if type(EverlookDB) == "table" then
		EverlookDB.staleSegments = nil
	end
	for _, page in pairs(P.all()) do
		local name = segment_name(page)
		local info = published[name]
		if not P.derived(page.bucket) and (not info or info.rows ~= page.count or named[name]) then
			page.seg_dirty = true
			P.on_dirty(page)
		end
	end
	-- Whatever is waiting at load has waited long enough.
	local t = now()
	for index = 1, #queue do
		queue[index].touched = t - QUIET
		queue[index].first_dirty = t - QUIET
	end
end

-- Stages of one job. Each call does a small piece and returns.
local RAW = {}
local SEG = {}

function RAW.load(current)
	P.page_rows(current.page)
	current.stage = "cbor"
end

function RAW.cbor(current)
	local cbor = P.encode_cbor(current.page)
	if type(cbor) ~= "string" then
		current.failed = true
		return
	end
	current.cbor = cbor
	current.stage = "store"
end

function RAW.store(current)
	local page = current.page
	P.store_payload(page, P.encode_payload(current.cbor))
	current.cbor = nil
	current.stage = "done"
end

function SEG.load(current)
	local rows = P.page_rows(current.page)
	local list = {}
	for _, row in pairs(rows) do
		list[#list + 1] = row
	end
	current.list = list
	current.index = 1
	current.stage = "pack"
end

function SEG.pack(current)
	local began = clock()
	local bucket = current.page.bucket
	while current.index <= #current.list do
		current.packed[#current.packed + 1] = internal.pack_row(bucket, current.list[current.index])
		current.index = current.index + 1
		if clock() - began >= PACK_MS then
			return
		end
	end
	current.list = nil
	current.index = 1
	current.stage = "count"
end

function SEG.count(current)
	local packed = current.packed
	local began = clock()
	current.counts = current.counts or {}
	local skip = sources_column[current.page.bucket]
	while current.index <= #packed do
		local row = packed[current.index]
		local held = skip and row[skip]
		if held then
			row[skip] = false
		end
		internal.count_strings(row, current.counts, false)
		if held then
			row[skip] = held
		end
		current.index = current.index + 1
		if clock() - began >= PACK_MS then
			return
		end
	end
	local table_strings, indexes = {}, {}
	for text, count in pairs(current.counts) do
		if count >= 2 then
			table_strings[#table_strings + 1] = text
			indexes[text] = #table_strings
		end
	end
	current.counts = nil
	current.index = 1
	if #table_strings > 0 then
		current.strings, current.indexes = table_strings, indexes
		current.stage = "replace"
	else
		current.document = { v = 2, b = current.page.bucket, r = packed }
		current.stage = "cbor"
	end
end

function SEG.replace(current)
	local packed = current.packed
	local began = clock()
	local skip = sources_column[current.page.bucket]
	while current.index <= #packed do
		local row = packed[current.index]
		local held = skip and row[skip]
		if held then
			row[skip] = false
		end
		internal.replace_strings(row, current.indexes, false)
		if held then
			row[skip] = held
		end
		current.index = current.index + 1
		if clock() - began >= PACK_MS then
			return
		end
	end
	current.document = { v = 2, b = current.page.bucket, r = packed, s = current.strings }
	current.strings, current.indexes = nil, nil
	current.stage = "cbor"
end

function SEG.cbor(current)
	local cbor = C_EncodingUtil.SerializeCBOR(current.document, { ignoreSerializationErrors = true })
	current.document = nil
	if type(cbor) ~= "string" then
		current.failed = true
		return
	end
	current.cbor = cbor
	current.stage = "compress"
end

function SEG.compress(current)
	local cbor = current.cbor
	local payload = "2r." .. C_EncodingUtil.EncodeBase64(cbor)
	if C_EncodingUtil.CompressString then
		local method = Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate or 0
		local level = Enum and Enum.CompressionLevel and Enum.CompressionLevel.Default or 0
		local compressed = C_EncodingUtil.CompressString(cbor, method, level)
		if type(compressed) == "string" then
			local deflated = "2c." .. C_EncodingUtil.EncodeBase64(compressed)
			if #deflated < #payload then
				payload = deflated
			end
		end
	end
	current.cbor = nil
	current.payload = payload
	current.hasher = Everlook.hash.stream(payload)
	current.stage = "hash"
end

function SEG.hash(current)
	if current.hasher:step(HASH_BLOCKS) then
		current.stage = "done"
	end
end

local function finish_job(current)
	local page = current.page
	page.job = nil
	local same = page.version == current.version
	if current.kind == "raw" then
		if same then
			page.raw_dirty = false
			if page.waits and not page.waits.raw_dirty then
				page.waits = nil
			end
		end
		stats.saved = (stats.saved or 0) + 1
	elseif same then
		-- A segment packed before the page changed again is not listed.
		staged[segment_name(page)] = { payload = current.payload, rows = current.rows, sha = current.hasher:hex() }
		stats.encoded = (stats.encoded or 0) + 1
		page.seg_dirty = false
	end
	if not same then
		-- Changed again while it was being saved. It waits out its quiet time again.
		page.touched = now()
		page.first_dirty = page.touched
	end
	settle_queue(page)
	P.trim()
end

-- The engine would not serialize the page. Its changes are not saved, so it stays
-- marked, is never let go, and is left alone for the rest of the session.
local function abandon_job(current)
	current.page.job = nil
	current.page.failed = true
	stats.failed = (stats.failed or 0) + 1
end

-- The page to work on next, and what kind of work. A page that a split is
-- waiting on goes first.
local function pick(force, only)
	local t = now()
	local best, best_kind, best_score
	for index = #queue, 1, -1 do
		local page = queue[index]
		if page.cleared then
			dequeue(page)
		elseif not page.job and not page.failed and (force or (t - page.touched >= QUIET) or (t - page.first_dirty >= MAX_WAIT)) then
			local kind
			if page.raw_dirty then
				kind = "raw"
				if page.waits and page.waits.raw_dirty then
					page = page.waits
					if page.job or page.failed then
						kind = nil
					end
				end
			elseif page.seg_dirty and only ~= "raw" then
				kind = "seg"
			end
			if kind and (only == nil or only == kind) then
				local score = (kind == "raw" and 0 or 1e9) + (page.first_dirty or 0) - (published[segment_name(page)] and 0 or 1e8)
				if not best or score < best_score then
					best, best_kind, best_score = page, kind, score
				end
			end
		end
	end
	return best, best_kind
end

local function credentials()
	if not Everlook.config or not Everlook.config.credentials then
		return nil
	end
	return Everlook.config.credentials()
end

local function clean(text)
	text = type(text) == "string" and text or tostring(text or "")
	return (text:gsub("[^%w%._%-]", "_")):sub(1, 32)
end

-- The manifest the server reads: the header, then every segment saved or
-- staged with its row count and digest, sorted by name.
local function manifest_text()
	local names, pages = {}, {}
	for _, page in pairs(P.all()) do
		local name = segment_name(page)
		if staged[name] or published[name] then
			names[#names + 1] = name
			pages[name] = page
		end
	end
	table.sort(names)
	local entries = {}
	for index = 1, #names do
		local info = staged[names[index]] or published[names[index]]
		entries[index] = names[index] .. "=" .. info.rows .. ":" .. info.sha
	end
	local build, locale, toc = "", "", 0
	if GetBuildInfo then
		local _, client_build, _, client_toc = GetBuildInfo()
		build = clean(client_build)
		toc = tonumber(client_toc) or 0
	end
	if GetLocale then
		locale = clean(GetLocale())
	end
	local version = ""
	if C_AddOns and C_AddOns.GetAddOnMetadata then
		version = clean(C_AddOns.GetAddOnMetadata("Everlook", "Version"))
	end
	return table.concat({ "2", floor(time and time() or 0), build, locale, floor(toc), version, table.concat(entries, ",") }, ";"), names
end

local function start_commit()
	local text, names = manifest_text()
	committing = { text = text, names = names }
	local secret, signer = credentials()
	if secret then
		if pads_secret ~= secret then
			pads, pads_secret = Everlook.hash.hmac_key(secret), secret
		end
		committing.signer = signer
		committing.stream = Everlook.hash.hmac_stream(pads, text)
	end
end

-- Swaps the new payloads, manifest and signature in together, so what the game
-- saves is always a set that agrees with itself.
local function publish_commit()
	local db = EverlookDB
	local done = committing
	committing = nil
	if type(db) ~= "table" then
		return
	end
	local segments = {}
	local bytes = 0
	local fresh = {}
	for index = 1, #done.names do
		local name = done.names[index]
		local info = staged[name]
		local payload = info and info.payload or (type(db.segments) == "table" and db.segments[name])
		if type(payload) == "string" then
			segments[name] = payload
			bytes = bytes + #payload
			fresh[name] = info and { rows = info.rows, sha = info.sha, bytes = #payload } or published[name]
		end
	end
	db.segments = segments
	db.manifest = done.text
	db.signer = done.signer
	db.signature = done.stream and done.stream:hex() or nil
	db.world = nil
	published = fresh
	staged = {}
	total_bytes = bytes
	last_commit = now()
	stats.commits = (stats.commits or 0) + 1
end

local function credentials_changed()
	local db = EverlookDB
	if type(db) ~= "table" or type(db.manifest) ~= "string" then
		return false
	end
	local secret, signer = credentials()
	return signer ~= db.signer or (secret == nil and db.signature ~= nil)
end

local function commit_due(force)
	if next(staged) == nil and not credentials_changed() then
		return false
	end
	if force then
		return true
	end
	for index = 1, #queue do
		if queue[index].seg_dirty then
			return now() - last_commit >= COMMIT_EVERY
		end
	end
	return true
end

-- Once every page is saved as its own string, the old whole-collection copy is
-- not needed, and goes in the same step.
local function finish_migration()
	if not P.migrating then
		return
	end
	for index = 1, #queue do
		if queue[index].raw_dirty then
			return
		end
	end
	if job and job.kind == "raw" then
		return
	end
	local db = EverlookDB
	if type(db) == "table" then
		db.raw = nil
		db.pagesMigrating = nil
	end
	P.migrating = false
	if Everlook.world.migrated then
		Everlook.world.migrated()
	end
	stats.migrated = true
end

local function begin(page, kind)
	local current = { page = page, kind = kind, version = page.version, stage = "load" }
	page.job = current
	if kind == "seg" then
		current.packed = {}
		current.rows = page.count
	end
	return current
end

local function step_job(current)
	if current.failed then
		abandon_job(current)
		return true
	end
	if current.stage == "done" then
		finish_job(current)
		return true
	end
	local stage, began = current.stage, clock()
	local table_of = current.kind == "raw" and RAW or SEG
	table_of[stage](current)
	local spent = stats.stageMs or {}
	stats.stageMs = spent
	local label = current.kind .. "_" .. stage
	spent[label] = floor(((spent[label] or 0) + clock() - began) * 100 + 0.5) / 100
	return false
end

-- Does pieces of work until the time is up or there is none. True while work
-- remains. `force` ignores how long a page has been quiet, `commit` signs
-- what is staged without waiting for the line to empty, `only` limits the
-- work to one kind, and `finishing` starts no new job.
local function work(limit_ms, force, commit, finishing, only)
	local started = clock()
	while true do
		if committing then
			if committing.stream then
				if committing.stream:step(HASH_BLOCKS) then
					publish_commit()
				end
			else
				publish_commit()
			end
		elseif job then
			if step_job(job) then
				job = nil
			end
		else
			local page, kind
			if not finishing then
				page, kind = pick(force, only)
			end
			if page then
				job = begin(page, kind)
			elseif only == nil and commit_due(commit or force) then
				start_commit()
			else
				finish_migration()
				return false
			end
		end
		if clock() - started >= limit_ms then
			return true
		end
	end
end

function S.step(limit_ms, force, commit, only)
	return work(limit_ms or WORK_MS, force, commit, false, only)
end

-- (lines waiting, whether anything is staged, whether a job runs, whether a manifest is being signed)
function S.pending()
	return #queue, next(staged) ~= nil, job ~= nil, committing ~= nil
end

-- One pass of the scheduler. Called by the frame, and by tests.
function S.tick()
	local t = now()
	if t - last_check >= CHECK_EVERY then
		last_check = t
		if credentials_changed() then
			wake()
		end
	end
	if type(InCombatLockdown) == "function" and InCombatLockdown() then
		return
	end
	if t < next_poll then
		return
	end
	local slow = type(GetFramerate) == "function" and (GetFramerate() or 60) < 30
	local budget = slow and SLOW_WORK_MS or WORK_MS
	-- An index still being built and the saving of pages take the frames in turn,
	-- so the pages it changes are saved as it goes and not all held until it ends.
	index_turn = not index_turn
	if index_turn and Everlook.world.index_pending() then
		Everlook.world.index_step(budget)
		return
	end
	if not work(budget, false) then
		if P.over() then
			-- Pages left in memory once moving in was done go a few at a time.
			P.trim()
		elseif #queue == 0 and next(staged) == nil and not Everlook.world.index_pending() then
			if frame then
				frame:Hide()
			end
		else
			-- Pages are waiting out their quiet time. Looking again each frame would be wasted.
			next_poll = t + 0.5
		end
	end
end

local function has_raw_work()
	for index = 1, #queue do
		if queue[index].raw_dirty then
			return true
		end
	end
	return job ~= nil and job.kind == "raw"
end

-- Logout, and a reload. The engine saves the variables right after this, so
-- every page that changed is saved first, whatever it takes, since nothing
-- else would keep its rows. Upload segments are built as far as the limit
-- allows. One that is not finished keeps the copy saved before it and goes
-- first next session.
function S.finish()
	local db = EverlookDB
	if type(db) ~= "table" or not S.enabled() or not P.active() then
		return false
	end
	local started = clock()
	local deadline = started + LOGOUT_MS
	if P.migrating then
		-- The old copy still holds everything, so saving pages can wait for the time.
		while work(math.max(1, deadline - clock()), true, false, false, "raw") and clock() < deadline do
		end
	else
		while job and job.kind == "seg" do
			work(1000, true, false, true)
		end
		while has_raw_work() do
			if not work(1e9, true, false, false, "raw") then
				break
			end
		end
	end
	while work(math.max(1, deadline - clock()), true) and clock() < deadline do
	end
	-- Past the limit nothing new is started. The job in hand is finished, and the
	-- manifest is signed even so: without it, nothing staged is saved.
	while committing or job or commit_due(true) do
		if not work(1000, false, true, true) then
			break
		end
	end
	finish_migration()
	local late = {}
	for index = 1, #queue do
		if queue[index].seg_dirty then
			late[#late + 1] = segment_name(queue[index])
		end
	end
	if #late > 0 then
		table.sort(late)
		db.staleSegments = late
	else
		db.staleSegments = nil
	end
	stats.logoutMs = floor((clock() - started) * 10 + 0.5) / 10
	stats.left = #late
	local page_stats = P.stats()
	stats.decodes, stats.decodeMs, stats.worstDecodeMs = page_stats.decodes, floor(page_stats.decodeMs * 10 + 0.5) / 10, floor(page_stats.worstDecodeMs * 10 + 0.5) / 10
	stats.splits, stats.evictions = page_stats.splits, page_stats.evictions
	stats.memKB = Everlook.world.memory_kb()
	db.flushStats = stats
	return true
end

function S.bytes()
	return total_bytes
end

frame = CreateFrame("Frame")
frame:Hide()
frame:SetScript("OnUpdate", function()
	S.tick()
end)
