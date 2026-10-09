local _, Everlook = ...

-- The world is saved in segments, each a small document of its own that holds
-- a run of one bucket's rows in the order they were first collected. A row's
-- segment never changes, so a sighting marks one segment dirty and costs a
-- table lookup. Rows found together are saved together, so a session that
-- walks one zone touches few segments. Dirty segments are packed, compressed and hashed a millisecond or so
-- a frame once they have been quiet for a while, and one HMAC over a manifest
-- of their digests signs them all. Logout finishes what is left. The work
-- follows what changed, not how much has been collected.

Everlook.segments = {}
local S = Everlook.segments

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

-- Rows in a full segment, chosen so one is around 30 KB packed. Small rows
-- such as drops fit a thousand, and a creature takes dozens.
local SIZE = {
	maps = 8, factions = 512, spells = 192, skillLines = 512, currencies = 512, items = 128, objects = 128,
	npcs = 40, quests = 24, talents = 512, recipes = 256, kills = 1024, drops = 1024, vendors = 1024,
	merchantCosts = 1024, objectLoot = 1024, fishingLoot = 512, npcSpells = 1024, npcFactions = 1024,
	taxiNodes = 256, taxiRoutes = 512,
}

-- The second part of a segment's name says how rows are grouped. Another way
-- of grouping would take another number.
local GROUPING = 0

local WORK_MS = 1.5
local SLOW_WORK_MS = 0.75
local PACK_MS = 0.5
local HASH_BLOCKS = 6
local QUIET = 15
local MAX_WAIT = 120
local COMMIT_EVERY = 300
local LOGOUT_MS = 400
local CHECK_EVERY = 10

local by_bucket = {}
local seg_of = {}
local segs = {}
local queue = {}
local published = {}
local staged = {}
local job
local committing
local pads, pads_secret
local last_commit = 0
local last_check = 0
local next_poll = 0
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
	return type(C_EncodingUtil) == "table"
		and type(C_EncodingUtil.SerializeCBOR) == "function"
		and type(C_EncodingUtil.EncodeBase64) == "function"
end

local function wake()
	if frame and not frame:IsShown() then
		frame:Show()
	end
end

local function mark_dirty(seg, quiet_already)
	seg.version = seg.version + 1
	seg.touched = quiet_already and (now() - QUIET) or now()
	if not seg.queued then
		seg.queued = true
		seg.first_dirty = seg.touched
		queue[#queue + 1] = seg
		wake()
	end
end

local next_seq = {}

local function segment_at(bucket, position)
	local list = by_bucket[bucket]
	if not list then
		list = {}
		by_bucket[bucket] = list
	end
	local seg = list[position]
	if not seg then
		seg = { bucket = bucket, name = bucket .. "." .. GROUPING .. "." .. position, rows = {}, count = 0, version = 0 }
		list[position] = seg
		segs[seg.name] = seg
	end
	return seg
end

-- A row's place is its sequence number, kept on the row so it comes back
-- with the saved rows. It is not a column, so it is never uploaded.
local function place(bucket, row)
	if not internal.keys[bucket] then
		return nil
	end
	local seq = row._seq
	if type(seq) ~= "number" or seq < 0 or seq ~= floor(seq) then
		seq = next_seq[bucket] or 0
		row._seq = seq
	end
	if seq >= (next_seq[bucket] or 0) then
		next_seq[bucket] = seq + 1
	end
	local seg = segment_at(bucket, floor(seq / (SIZE[bucket] or 256)))
	seg.count = seg.count + 1
	seg.rows[seg.count] = row
	seg_of[row] = seg
	return seg
end

-- A row that was just stored for the first time.
function S.add(bucket, row)
	local seg = place(bucket, row)
	if seg then
		mark_dirty(seg)
	end
end

-- A row whose content or counts changed.
function S.touch(row)
	local seg = seg_of[row]
	if seg then
		mark_dirty(seg)
	end
end

function S.reset()
	by_bucket, seg_of, segs, queue, published, staged, next_seq = {}, {}, {}, {}, {}, {}, {}
	job, committing = nil, nil
	total_bytes = 0
	last_commit = now()
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

-- Called once the saved rows are in place, while the loading screen is up.
function S.rebuild()
	S.reset()
	local rows = internal.rows()
	local buckets = internal.buckets
	for index = 1, #buckets do
		local bucket = buckets[index]
		local bucket_rows = rows[bucket]
		if bucket_rows then
			-- Rows that already have a number keep it, so new ones are numbered after them.
			for _, row in pairs(bucket_rows) do
				if type(row) == "table" and type(row._seq) == "number" and row._seq >= (next_seq[bucket] or 0) then
					next_seq[bucket] = floor(row._seq) + 1
				end
			end
			for _, row in pairs(bucket_rows) do
				if type(row) == "table" then
					place(bucket, row)
				end
			end
		end
	end
	read_saved()
	local stale = type(EverlookDB) == "table" and type(EverlookDB.staleSegments) == "table" and EverlookDB.staleSegments or {}
	local named = {}
	for index = 1, #stale do
		named[stale[index]] = true
	end
	if type(EverlookDB) == "table" then
		EverlookDB.staleSegments = nil
	end
	for name, seg in pairs(segs) do
		local info = published[name]
		if not info or info.rows ~= seg.count or named[name] then
			mark_dirty(seg, true)
		end
	end
end

-- Stages of one segment's encoding. Each call does a small piece and returns.
local function pack_step(current)
	local seg = current.seg
	local began = clock()
	-- A creature with thousands of pins is slow to pack, so the clock is read per row.
	while current.index <= seg.count do
		current.packed[#current.packed + 1] = internal.pack_row(seg.bucket, seg.rows[current.index])
		current.index = current.index + 1
		if clock() - began >= PACK_MS then
			break
		end
	end
	if current.index > seg.count then
		current.index = 1
		current.stage = "count"
	end
end

-- Strings that repeat inside the segment are written once and pointed to. Both
-- passes go a row at a time against the clock.
local function count_step(current)
	local packed = current.packed
	local began = clock()
	current.counts = current.counts or {}
	local skip = sources_column[current.seg.bucket]
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
		current.document = { v = 2, b = current.seg.bucket, r = packed }
		current.stage = "cbor"
	end
end

local function replace_step(current)
	local packed = current.packed
	local began = clock()
	local skip = sources_column[current.seg.bucket]
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
	current.document = { v = 2, b = current.seg.bucket, r = packed, s = current.strings }
	current.strings, current.indexes = nil, nil
	current.stage = "cbor"
end

local function cbor_step(current)
	local cbor = C_EncodingUtil.SerializeCBOR(current.document, { ignoreSerializationErrors = true })
	current.document = nil
	if type(cbor) ~= "string" then
		current.failed = true
		return
	end
	current.cbor = cbor
	current.stage = "compress"
end

local function compress_step(current)
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

local function hash_step(current)
	if current.hasher:step(HASH_BLOCKS) then
		current.stage = "done"
	end
end

local STAGES = { pack = pack_step, count = count_step, replace = replace_step, cbor = cbor_step, compress = compress_step, hash = hash_step }

local function dequeue(seg)
	for index = 1, #queue do
		if queue[index] == seg then
			queue[index] = queue[#queue]
			queue[#queue] = nil
			break
		end
	end
	seg.queued = false
	seg.first_dirty = nil
end

local function finish_job(current)
	local seg = current.seg
	staged[seg.name] = { payload = current.payload, rows = seg.count, sha = current.hasher:hex() }
	stats.encoded = (stats.encoded or 0) + 1
	if seg.version == current.version then
		dequeue(seg)
	else
		-- Touched again while it was being packed. It stays queued and waits out
		-- its quiet time again, or a busy segment would be packed over and over.
		seg.touched = now()
		seg.first_dirty = seg.touched
	end
end

-- The segment to encode next: one never saved first, then the one waiting longest.
local function pick(force)
	local t = now()
	local best, best_score
	for index = 1, #queue do
		local seg = queue[index]
		if force or (t - seg.touched >= QUIET) or (t - seg.first_dirty >= MAX_WAIT) then
			local score = seg.first_dirty - (published[seg.name] and 0 or 1e9)
			if not best or score < best_score then
				best, best_score = seg, score
			end
		end
	end
	return best
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
	local names = {}
	for name in pairs(segs) do
		if staged[name] or published[name] then
			names[#names + 1] = name
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
	return force or #queue == 0 or now() - last_commit >= COMMIT_EVERY
end

-- Does pieces of work until the time is up or there is none. True while work
-- remains. `force` ignores how long a segment has been quiet, and `commit`
-- signs what is staged without waiting for the line to empty.
local function work(limit_ms, force, commit, finishing)
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
			if job.failed then
				-- The engine would not serialize it. Leave it queued for the next session.
				dequeue(job.seg)
				job = nil
			elseif job.stage == "done" then
				finish_job(job)
				job = nil
			else
				-- Where the time goes, kept with the saved variables so a slow one can be read back.
				local stage, began = job.stage, clock()
				STAGES[stage](job)
				local spent = stats.stageMs or {}
				stats.stageMs = spent
				spent[stage] = floor(((spent[stage] or 0) + clock() - began) * 100 + 0.5) / 100
			end
		else
			local seg = not finishing and pick(force) or nil
			if seg then
				job = { seg = seg, version = seg.version, index = 1, packed = {}, stage = "pack" }
			elseif commit_due(commit or force) then
				start_commit()
			else
				return false
			end
		end
		if clock() - started >= limit_ms then
			return true
		end
	end
end

function S.step(limit_ms, force, commit)
	return work(limit_ms or WORK_MS, force, commit)
end

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
	if not work(slow and SLOW_WORK_MS or WORK_MS, false) then
		if #queue == 0 and next(staged) == nil then
			if frame then
				frame:Hide()
			end
		else
			-- Segments are waiting out their quiet time. Looking again each frame would be wasted.
			next_poll = t + 0.5
		end
	end
end

-- Logout, and a reload. The engine saves the variables right after this, so
-- whatever is still in line is finished here, within a limit. A segment that
-- does not make it keeps the last copy that was saved and goes first next time.
function S.finish()
	local db = EverlookDB
	if type(db) ~= "table" or not S.enabled() then
		return false
	end
	local started = clock()
	local deadline = started + LOGOUT_MS
	while work(math.max(1, deadline - clock()), true) and clock() < deadline do
	end
	-- Past the limit nothing new is started. The segment in hand is finished, and
	-- the manifest is signed even so: without it, nothing staged is saved.
	while committing or job or commit_due(true) do
		if not work(1000, false, true, true) then
			break
		end
	end
	local late = {}
	for index = 1, #queue do
		late[#late + 1] = queue[index].name
	end
	if #late > 0 then
		table.sort(late)
		db.staleSegments = late
	else
		db.staleSegments = nil
	end
	stats.logoutMs = floor((clock() - started) * 10 + 0.5) / 10
	stats.left = #late
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
