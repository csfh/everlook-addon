-- Pages and segments: the collection saved a page at a time, and the upload saved in segments, one per page.
return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)

	local function deep(value)
		if type(value) ~= "table" then
			return value
		end
		local copy = {}
		for key, item in pairs(value) do
			copy[key] = deep(item)
		end
		return copy
	end

	-- The engine's CBOR is a handle to a snapshot, so a page that is read back is a
	-- new table. The snapshots outlive a session, as saved pages do.
	local snapshots = {}

	local function load(setup)
		local Everlook = {}
		local env = setmetatable({}, { __index = _G })
		env._G = env
		env.EventUtil = { ContinueOnAddOnLoaded = function() end, ContinueOnPlayerLogin = function() end }
		env.CreateFrame = function()
			local frame = { shown = true }
			function frame:RegisterEvent() end
			function frame:SetScript(name, handler)
				self[name] = handler
			end
			function frame:Show()
				self.shown = true
			end
			function frame:Hide()
				self.shown = false
			end
			function frame:IsShown()
				return self.shown
			end
			return frame
		end
		env.clock_now = 1000
		env.GetTime = function()
			return env.clock_now
		end
		env.time = function()
			return 1789506741
		end
		env.GetBuildInfo = function()
			return "12.0.5", "66263 (x)", "Oct 1 2026", 120005
		end
		env.GetLocale = function()
			return "enUS"
		end
		env.C_AddOns = { GetAddOnMetadata = function() return "0.30.0" end }
		env.C_EncodingUtil = {
			SerializeCBOR = function(value)
				snapshots[#snapshots + 1] = deep(value)
				return "cbor:" .. #snapshots
			end,
			DeserializeCBOR = function(handle)
				local index = tonumber(tostring(handle):match("^cbor:(%d+)$"))
				return index and deep(snapshots[index]) or nil
			end,
			EncodeBase64 = function(value)
				return value
			end,
			DecodeBase64 = function(value)
				return value
			end,
		}
		env.EverlookDB = {}
		if setup then
			setup(env)
		end
		local files = { "world.lua", "location.lua", "sightings.lua", "npcs.lua", "items.lua", "drops.lua", "hash.lua", "config.lua", "pages.lua", "segments.lua" }
		for index = 1, #files do
			local chunk = assert(loadfile(source(files[index])))
			setfenv(chunk, env)
			chunk("Everlook", Everlook)
		end
		return Everlook, env, snapshots
	end

	-- A fresh session on whatever a database already holds.
	local function open(db, setup)
		local addon, env, snapshots = load(function(e)
			e.EverlookDB = db
			if setup then
				setup(e)
			end
		end)
		addon.config.token = "token-1"
		addon.world.load_saved()
		return addon, env, snapshots
	end

	local function settle(addon)
		local guard = 0
		while addon.segments.step(1000, true, true) do
			guard = guard + 1
			if guard > 100000 then
				error("the encoder did not settle")
			end
		end
	end

	local function manifest_entries(db)
		local entries = {}
		for name, count, sha in db.manifest:gmatch("([%w]+%.%d+%.%d+)=(%d+):(%x+)") do
			entries[name] = { rows = tonumber(count), sha = sha }
		end
		return entries
	end

	local function count_of(map)
		local count = 0
		for _ in pairs(map or {}) do
			count = count + 1
		end
		return count
	end

	-- A page holds a range of one bucket and is cut in two when it is full.
	do
		local addon, env = open({})
		check("a fresh install keeps its collection in pages", addon.pages.active() and addon.world.row_count() == 0)
		for id = 1, 40 do
			addon.world.store("npcs", { id = id * 100, name = "N" .. id })
		end
		check("a full page is one page", #addon.pages.pages("npcs") == 1)
		addon.world.store("npcs", { id = 150, name = "41st" })
		local pages = addon.pages.pages("npcs")
		check("the page that overflows is cut in two", #pages == 2 and pages[1].count + pages[2].count == 41 and addon.pages.total("npcs") == 41)
		local cut = pages[2].start
		check("the cut is at a key, and every row is still found", cut > 100 and addon.world.row("npcs", 150).name == "41st" and addon.world.row("npcs", 4000).name == "N40" and addon.world.row("npcs", 100).name == "N1")
		check("only the cut page's rows moved", pages[1].count == 20 or pages[1].count == 21)
		addon.world.store("drops", { npcId = 7, itemId = 1, drops = 1 })
		addon.world.store("drops", { npcId = 7, itemId = 2, drops = 1 })
		check("a composite key goes by its first part", #addon.pages.pages("drops") == 1 and addon.world.row("drops", "7:2").drops == 1)
		check("a key that cannot be placed is still stored", addon.world.store("npcs", { id = 4000000000, name = "Huge" }) ~= nil and addon.world.row("npcs", 4000000000).name == "Huge")
	end

	-- What is saved comes back, whatever the cache let go.
	do
		local addon, env = open({})
		for id = 1, 700 do
			addon.world.store("maps", { id = id * 10, name = "Map " .. id })
		end
		addon.world.store("npcs", { id = 5, name = "Boar", locations = { { mapId = 1, x = 10, y = 20, seen = 2, zone = "Elwynn" } }, sources = { "target" } })
		check("many pages are made", #addon.pages.pages("maps") > 49)
		check("pages with changes are kept until they are saved", addon.pages.loaded() == #addon.pages.pages("maps") + #addon.pages.pages("npcs"))
		env.clock_now = 5000
		settle(addon)
		for id = 1, 700 do
			addon.world.row("maps", id * 10)
		end
		check("once saved, the cache lets pages go and no row is lost", addon.pages.loaded() <= 49 and addon.world.row_count() == 701 and addon.world.row("maps", 10).name == "Map 1")
		addon.world.flush(true)
		local db = env.EverlookDB
		check("a flush saves every page that changed", count_of(db.pages) == #addon.pages.pages("maps") + #addon.pages.pages("npcs") and db.raw == nil)

		local next_addon = open(db)
		check("the next session knows its rows without reading any page", next_addon.world.row_count() == 701 and next_addon.pages.stats().decodes == 0)
		check("a row is read from its page", next_addon.world.row("maps", 3500).name == "Map 350" and next_addon.pages.stats().decodes == 1)
		local boar = next_addon.world.row("npcs", 5)
		check("a row comes back as it went in", boar.name == "Boar" and boar.locations[1].zone == "Elwynn" and boar.locations[1].seen == 2 and boar.sources[1] == "target")
		local read = 0
		next_addon.world.each("maps", function()
			read = read + 1
		end)
		check("walking a bucket reads every row and keeps within the cache", read == 700 and next_addon.pages.loaded() <= 49)
		check("rows read twice are the same table", next_addon.world.row("maps", 10) == next_addon.world.row("maps", 10))
	end

	-- A changed page is saved before logout lets go of it, however long the limit.
	do
		local addon, env = open({})
		addon.world.store("npcs", { id = 1, name = "Boar" })
		env.clock_now = 5000
		settle(addon)
		addon.world.flush(true)
		local db = env.EverlookDB
		local next_addon, next_env = open(db)
		next_addon.world.store("npcs", { id = 1, name = "Boar", minLevel = 7 })
		next_addon.world.store("npcs", { id = 2, name = "Wolf" })
		local ticks = 0
		next_env.debugprofilestop = function()
			ticks = ticks + 500
			return ticks
		end
		next_addon.world.flush(true)
		local third = open(next_env.EverlookDB)
		check("logout past its time limit still saves what changed", third.world.row("npcs", 1).minLevel == 7 and third.world.row("npcs", 2).name == "Wolf")
	end

	-- Counters mark their page, and a restatement does not.
	do
		local addon, env = open({})
		addon.world.store("drops", { npcId = 1, itemId = 2, drops = 1 })
		addon.world.store("npcs", { id = 1, name = "A", locations = { { mapId = 1, x = 10, y = 10, seen = 1 } } })
		env.clock_now = 5000
		settle(addon)
		check("settling empties the line", addon.segments.pending() == 0)
		addon.world.store("npcs", { id = 1, name = "A", locations = { { mapId = 1, x = 10, y = 10, seen = 0 } } })
		check("an identical restatement marks nothing", addon.segments.pending() == 0)
		addon.world.store("npcs", { id = 1, name = "A", locations = { { mapId = 1, x = 10, y = 10 } } })
		check("a repeat pin marks its page", addon.segments.pending() == 1)
		settle(addon)
		addon.world.count("drops", { npcId = 1, itemId = 2, drops = 3 })
		check("a counter marks its page", addon.segments.pending() == 1 and addon.world.row("drops", "1:2").drops == 4)
		settle(addon)
		collectgarbage("collect")
		collectgarbage("stop")
		local scratch = { npcId = 1, itemId = 2, drops = 1 }
		local before = collectgarbage("count")
		for _ = 1, 1000 do
			addon.world.count("drops", scratch)
		end
		local grown = collectgarbage("count") - before
		collectgarbage("restart")
		check("repeat counts allocate nothing", grown < 2)
	end

	-- The manifest, the digests and the signature agree with the segments.
	do
		local first_snapshot = #snapshots
		local addon, env = open({})
		addon.world.store("maps", { id = 1, name = "Elwynn" })
		addon.world.store("npcs", { id = 1, name = "Boar", locations = { { mapId = 1, x = 10, y = 10, zone = "Elwynn" } } })
		addon.world.store("npcs", { id = 2, name = "Boar", locations = { { mapId = 1, x = 11, y = 10, zone = "Elwynn" } } })
		addon.world.store("npcs", { id = 900, name = "Wolf" })
		addon.world.store("drops", { npcId = 1, itemId = 5, drops = 2 })
		env.clock_now = 5000
		settle(addon)
		local db = env.EverlookDB
		local entries = manifest_entries(db)
		local names, listed, agree = 0, 0, true
		for name, info in pairs(entries) do
			names = names + 1
			listed = listed + info.rows
			if addon.hash.sha256(db.segments[name]) ~= info.sha then
				agree = false
			end
		end
		check("every page is listed with the digest of what is saved", names == 3 and agree and entries["npcs.1.0"].rows == 3)
		check("the manifest counts every row once", listed == addon.world.row_count())
		check("the manifest carries the header the server reads", db.manifest:match("^2;1789506741;66263__x_;enUS;120005;0%.30%.0;") ~= nil)
		check("the signature covers the manifest", db.signature == addon.hash.hmac_sha256("token-1", db.manifest) and db.signer == addon.hash.sha256("token-1"):sub(1, 16))
		local segment_tables, strings = {}, nil
		for index = first_snapshot + 1, #snapshots do
			local snapshot = snapshots[index]
			if snapshot.v == 2 then
				segment_tables[#segment_tables + 1] = snapshot
				if snapshot.b == "npcs" and snapshot.s then
					strings = snapshot.s
				end
			end
		end
		local rows_in_segments = 0
		for _, snapshot in ipairs(segment_tables) do
			rows_in_segments = rows_in_segments + #snapshot.r
		end
		check("the segments together hold the rows document() packs", rows_in_segments == 5 and #addon.world.document().npcs == 3)
		check("a string repeated in a segment is interned in it", strings ~= nil and (strings[1] == "Boar" or strings[2] == "Boar" or strings[1] == "Elwynn" or strings[2] == "Elwynn"))
		check("no whole world is saved beside the manifest", db.world == nil and db.raw == nil)
	end

	-- A source that is a word stays a word.
	do
		local first_snapshot = #snapshots
		local addon, env = open({})
		addon.world.store("items", { id = 1, name = "Linen", sources = { "fishing", "bag" } })
		addon.world.store("items", { id = 2, name = "Linen", sources = { "fishing", "bag" } })
		addon.world.store("items", { id = 3, name = "Wool", sources = { "fishing" } })
		env.clock_now = 5000
		settle(addon)
		local items
		for index = first_snapshot + 1, #snapshots do
			local snapshot = snapshots[index]
			if snapshot.v == 2 and snapshot.b == "items" then
				items = snapshot
			end
		end
		local cells = {}
		for _, row in ipairs(items.r) do
			cells[#cells + 1] = row[#row]
		end
		local words = 0
		for _, cell in ipairs(cells) do
			if cell[1] == "fishing" then
				words = words + 1
			end
		end
		check("sources are never replaced by a string index", items.s ~= nil and words == 3)
	end

	-- Moving from the old whole collection into pages keeps it until every page is saved.
	do
		local raw = { npcs = {}, items = { [9] = { id = 9, name = "Linen" } } }
		for id = 1, 90 do
			raw.npcs[id * 10] = { id = id * 10, name = "N" .. id }
		end
		local db = { raw = raw, world = "1c.legacy", signer = "old", signature = "olds" }
		local addon, env = open(db)
		check("the old copy is opened as pages", addon.world.row_count() == 91 and addon.pages.migrating and db.raw == raw and addon.world.row("npcs", 100).name == "N10")
		addon.world.store("npcs", { id = 55555, name = "New" })
		check("a row stored meanwhile goes in the old copy too", raw.npcs[55555] ~= nil and addon.world.row("npcs", 55555).name == "New")
		addon.world.row("npcs", 100).minLevel = 3
		addon.pages.touch(addon.world.row("npcs", 100))
		check("the old copy is the same rows", raw.npcs[100].minLevel == 3)

		-- Logging out part way keeps the old copy and a consistent partial set of pages.
		local ticks = 0
		env.debugprofilestop = function()
			ticks = ticks + 100
			return ticks
		end
		env.clock_now = 5000
		addon.segments.step(1, true, false, "raw")
		addon.world.flush(true)
		check("a logout before the pages are saved keeps the old copy", db.raw == raw and addon.pages.migrating)

		env.debugprofilestop = nil
		local resumed = open(db)
		check("the next session starts again from the old copy", resumed.world.row_count() == 92 and resumed.pages.migrating)
		env.clock_now = 9000
		settle(resumed)
		check("once every page is saved the old copy goes", db.raw == nil and not resumed.pages.migrating and db.world == nil and db.manifest ~= nil)
		check("and so does the marker that said the move was unfinished", db.pagesMigrating == nil)
		local final = open(db)
		for _ = 1, 10 do
			resumed.segments.tick()
		end
		check("pages kept in memory after the move are let go over time", resumed.pages.loaded() <= 49)
		check("the pages hold everything the old copy did", final.world.row_count() == 92 and final.world.row("npcs", 100).minLevel == 3 and final.world.row("npcs", 55555).name == "New" and final.world.row("items", 9).name == "Linen")
	end

	-- A split that was only half saved is made right on load.
	do
		local addon, env = open({})
		for id = 1, 41 do
			addon.world.store("npcs", { id = id * 100, name = "N" .. id })
		end
		local cut = addon.pages.pages("npcs")[2].start
		env.clock_now = 5000
		settle(addon)
		addon.world.flush(true)
		local db = env.EverlookDB
		-- The first page's saved copy is the one from before the split, whole.
		local whole = {}
		for id = 1, 41 do
			whole[id * 100] = { id = id * 100, name = "OLD" .. id }
		end
		snapshots[#snapshots + 1] = whole
		db.pages["npcs.0"] = "p1.cbor:" .. #snapshots
		local half = open(db)
		local seen, names = 0, {}
		half.world.each("npcs", function(key, row)
			seen = seen + 1
			names[key] = row.name
		end)
		check("rows left in a page by an unfinished split are not read twice", seen == 41 and half.world.row_count() == 41)
		check("the new page's copy of a row wins", names[cut] == "N" .. (cut / 100) and half.world.row("npcs", cut).name == "N" .. (cut / 100))
		check("the first page keeps its own rows", names[100] == "OLD1")
	end

	-- A page cut in two is not listed twice.
	do
		local addon, env = open({})
		for id = 1, 40 do
			addon.world.store("npcs", { id = id * 100, name = "N" .. id })
		end
		env.clock_now = 5000
		settle(addon)
		local before = manifest_entries(env.EverlookDB)
		check("one page is one listed segment", count_of(before) == 1)
		addon.world.store("npcs", { id = 150, name = "Split" })
		local ticks = 0
		env.debugprofilestop = function()
			ticks = ticks + 150
			return ticks
		end
		addon.segments.finish()
		env.debugprofilestop = nil
		local listed = 0
		for _, info in pairs(manifest_entries(env.EverlookDB)) do
			listed = listed + info.rows
		end
		check("rows are listed once however the logout ends", listed > 0 and listed <= 41)
		env.clock_now = 9000
		settle(addon)
		local after = 0
		for _, info in pairs(manifest_entries(env.EverlookDB)) do
			after = after + info.rows
		end
		check("once both halves are packed every row is listed", after == 41 and count_of(manifest_entries(env.EverlookDB)) == 2)
	end

	-- An older build that ran in between leaves a raw beside the pages.
	do
		local addon, env = open({})
		addon.world.store("npcs", { id = 1, name = "Boar" })
		addon.world.store("npcs", { id = 2, name = "Wolf" })
		env.clock_now = 5000
		addon.world.flush(true)
		local db = env.EverlookDB
		check("a finished move leaves no marker", db.raw == nil and db.pagesMigrating == nil and count_of(db.pages) == 1)
		db.raw = { npcs = { [1] = { id = 1, name = "Boar", minLevel = 9 }, [3] = { id = 3, name = "Bear", _seq = 4 } } }
		local back = open(db)
		check("a raw beside saved pages is added to them and not put over them", back.world.row("npcs", 1).minLevel == 9 and back.world.row("npcs", 2).name == "Wolf" and back.world.row("npcs", 3).name == "Bear" and back.world.row("npcs", 3)._seq == nil and db.raw == nil and back.world.row_count() == 3)
	end

	-- Pages that cannot be read leave the saved collection and upload alone.
	do
		local addon, env = open({})
		addon.world.store("npcs", { id = 1, name = "Boar" })
		env.clock_now = 5000
		addon.world.flush(true)
		local db = env.EverlookDB
		local manifest, page = db.manifest, db.pages["npcs.0"]
		local lossy, lossy_env = open(db, function(e)
			e.C_EncodingUtil.DeserializeCBOR = function()
				return { lossy = true }
			end
		end)
		lossy.world.store("npcs", { id = 2, name = "Wolf" })
		lossy.world.flush(true)
		check("a session that cannot read the pages leaves them and the upload as they were", db.pages["npcs.0"] == page and db.manifest == manifest and db.world == nil and db.pagesCheck ~= "ok")
		check("what it collected waits in raw", db.raw ~= nil and db.raw.npcs[2].name == "Wolf")
		local again = open(db)
		check("the next session adds it", again.world.row("npcs", 1).name == "Boar" and again.world.row("npcs", 2).name == "Wolf" and db.raw == nil)
	end

	-- A page the engine will not serialize is not lost, and does not stop logout.
	do
		local addon, env = open({})
		addon.world.store("npcs", { id = 1, name = "Boar" })
		addon.world.store("items", { id = 5, name = "Linen" })
		env.clock_now = 5000
		settle(addon)
		addon.world.flush(true)
		local db = env.EverlookDB
		local next_addon, next_env = open(db)
		next_addon.world.store("npcs", { id = 1, name = "Boar", minLevel = 4 })
		next_addon.world.store("items", { id = 5, name = "Linen", quality = 2 })
		local serialize = next_env.C_EncodingUtil.SerializeCBOR
		next_env.C_EncodingUtil.SerializeCBOR = function(value, options)
			if value[1] and value[1].name == "Boar" then
				return nil
			end
			return serialize(value, options)
		end
		next_addon.world.flush(true)
		check("a page that cannot be saved does not stop logout or the others", db.flushStats.failed == 1 and next_env.EverlookDB.pages["items.0"] ~= nil)
		check("the failure is recorded and the page keeps its changes in memory", next_addon.world.row("npcs", 1).minLevel == 4)
		local third = open(db)
		check("the other page's change was saved", third.world.row("items", 5).quality == 2)
	end

	-- A second session writes only what changed.
	do
		local addon, env = open({})
		for id = 1, 200 do
			addon.world.store("npcs", { id = id * 100, name = "Creature " .. id })
		end
		env.clock_now = 5000
		settle(addon)
		addon.world.flush(true)
		local saved = env.EverlookDB
		local first = {}
		for name, payload in pairs(saved.segments) do
			first[name] = payload
		end
		local next_addon, next_env = open(saved)
		check("a collection saved whole has nothing waiting", next_addon.segments.pending() == 0)
		next_addon.world.store("npcs", { id = 100, name = "Creature 1", minLevel = 7 })
		next_addon.world.store("npcs", { id = 1234567, name = "New" })
		local waiting = next_addon.segments.pending()
		check("only what changed is waiting", waiting >= 2 and waiting <= 3)
		next_env.clock_now = 9000
		settle(next_addon)
		local changed = 0
		for name, payload in pairs(next_env.EverlookDB.segments) do
			if first[name] ~= payload then
				changed = changed + 1
			end
		end
		check("only those segments are written again", changed >= 2 and changed <= 3)
	end

	-- A segment that keeps changing is not packed over and over.
	do
		local addon, env = open({})
		env.clock_now = 100
		addon.world.store("kills", { npcId = 1, kills = 1 })
		env.clock_now = 500
		addon.segments.step(0, false, false)
		local _, _, running = addon.segments.pending()
		check("a page past its longest wait is picked", running == true)
		local scratch = { npcId = 1, kills = 1 }
		addon.world.count("kills", scratch)
		while addon.segments.step(0, false, false) do
			local _, _, still = addon.segments.pending()
			if not still then
				break
			end
		end
		local queued, _, job = addon.segments.pending()
		check("a page touched mid-save waits out its quiet time again", queued == 1 and job == false)
		env.clock_now = 520
		addon.segments.step(0, false, false)
		local _, _, again = addon.segments.pending()
		check("it is saved once it has been quiet", again == true)
	end

	-- A new token signs the same segments again.
	do
		local addon, env = open({})
		addon.world.store("npcs", { id = 1, name = "Boar" })
		env.clock_now = 5000
		settle(addon)
		local db = env.EverlookDB
		local manifest, payload = db.manifest, db.segments["npcs.1.0"]
		addon.config.token = "token-2"
		settle(addon)
		check("a new token signs the manifest again", db.manifest == manifest and db.segments["npcs.1.0"] == payload and db.signature == addon.hash.hmac_sha256("token-2", manifest) and db.signer == addon.hash.sha256("token-2"):sub(1, 16))
		addon.config.token = nil
		db.secret = nil
		settle(addon)
		check("with no token the file is unsigned", db.signature == nil and db.signer == nil and db.manifest == manifest)
	end

	-- Logout builds upload segments within its limit and names the rest.
	do
		local addon, env = open({})
		for id = 1, 400 do
			addon.world.store("npcs", { id = id * 64, name = "Creature " .. id })
		end
		local ticks = 0
		env.debugprofilestop = function()
			ticks = ticks + 25
			return ticks
		end
		addon.world.flush(true)
		local db = env.EverlookDB
		local left = db.staleSegments and #db.staleSegments or 0
		local entries = manifest_entries(db)
		local agree = true
		for name, info in pairs(entries) do
			if addon.hash.sha256(db.segments[name]) ~= info.sha then
				agree = false
			end
		end
		check("logout past its limit saves what it finished and names the rest", left > 0 and agree and db.flushStats.left == left)
		check("what is saved agrees with its signature", db.signature == addon.hash.hmac_sha256("token-1", db.manifest))
		env.debugprofilestop = nil
		local next_addon = open(db)
		check("the next session starts with what was left", next_addon.segments.pending() >= left)
		check("every row is saved in its page whatever the limit", next_addon.world.row_count() == 400 and next_addon.world.row("npcs", 400 * 64).name == "Creature 400")
	end

	-- With time to spare, logout leaves nothing behind.
	do
		local addon, env = open({})
		addon.world.store("npcs", { id = 1, name = "Boar" })
		addon.world.store("items", { id = 5, name = "Linen" })
		addon.world.flush(true)
		local db = env.EverlookDB
		check("logout saves the segments and the signature", db.manifest ~= nil and db.signature ~= nil and db.staleSegments == nil and db.world == nil)
		check("logout records the rows and bytes saved", db.worldRows == 2 and db.worldBytes == #db.segments["npcs.1.0"] + #db.segments["items.1.0"])
	end

	-- The manifest keeps to what the server reads.
	do
		local addon, env = open({})
		addon.world.store("npcs", { id = 1, name = "Boar" })
		addon.world.store("fishingLoot", { mapId = 1, areaId = 2, itemId = 3, casts = 1 })
		env.GetBuildInfo = function() return "x", "build 1;2,3 \195\169", "d", 5 end
		addon.world.flush(true)
		local header, entries = env.EverlookDB.manifest:match("^(2;%d+;[%w%._%-]*;[%w%._%-]*;%d+;[%w%._%-]*);(.*)$")
		check("the header holds only characters the server accepts", header ~= nil and not header:find("%s"))
		local fine = entries ~= nil
		for entry in (entries or ""):gmatch("[^,]+") do
			if not entry:match("^%a+%.%d%d?%.%d+=%d+:%x+$") or #entry:match(":(%x+)$") ~= 64 then
				fine = false
			end
		end
		check("every entry is a name, a count and a digest", fine)
	end

	-- Tooltip lines come from indexes saved as pages, built once and then only kept up to date.
	do
		local addon, env = open({})
		addon.world.store("npcs", { id = 10, name = "Hogger" })
		addon.world.store("items", { id = 20, name = "Cloth" })
		addon.world.store("vendors", { npcId = 10, itemId = 20 })
		addon.world.store("drops", { npcId = 10, itemId = 20, drops = 4 })
		addon.world.store("quests", { id = 176, title = "Wanted", giverId = 10 })
		env.clock_now = 5000
		addon.world.flush(true)
		local db = env.EverlookDB
		check("the indexes are saved as pages and never uploaded", db.pages["ixItemVendors.0"] ~= nil and db.pages["ixNpcQuests.0"] ~= nil and db.segments["ixItemVendors.1.0"] == nil and not db.manifest:find("ix", 1, true) and db.ixVersion == 1)

		local next_addon = open(db)
		local at_login = next_addon.pages.stats().decodes
		local lines = table.concat(next_addon.world.lookup("item", 20), "|")
		check("a tooltip reads its lines from saved pages", lines:find("Vendor: Hogger", 1, true) and lines:find("Dropped by Hogger (4)", 1, true) and next_addon.world.lookup("npc", 10)[2] == "Quest: Wanted")
		check("login reads no page to build them", at_login == 0 and not next_addon.world.index_pending())
		next_addon.world.count("drops", { npcId = 10, itemId = 20, drops = 1 })
		check("a count shows at once", table.concat(next_addon.world.lookup("item", 20), "|"):find("Dropped by Hogger (5)", 1, true) ~= nil)
		next_addon.world.store("quests", { id = 176, giverId = 11 })
		check("a quest that changes giver moves between saved indexes", #next_addon.world.lookup("npc", 10) == 1 and next_addon.world.lookup("npc", 11)[1] == "Quest: Wanted")
		next_addon.world.store("items", { id = 21, name = "Wool" })
		next_addon.world.store("vendors", { npcId = 10, itemId = 21 })
		check("a new row is added to the saved index", next_addon.world.lookup("npc", 10)[1] == "Sells Cloth" and next_addon.world.lookup("npc", 10)[2] == "Sells Wool")
	end

	-- A collection saved before the indexes were pages gets them built in the background.
	do
		local addon, env = open({})
		addon.world.store("npcs", { id = 10, name = "Hogger" })
		addon.world.store("items", { id = 20, name = "Cloth" })
		for id = 1, 3000 do
			addon.world.store("vendors", { npcId = id, itemId = 20 })
		end
		env.clock_now = 5000
		addon.world.flush(true)
		local db = env.EverlookDB
		db.ixVersion = nil
		for name in pairs(db.pages) do
			if name:sub(1, 2) == "ix" then
				db.pages[name] = nil
				db.pageCounts[name] = nil
			end
		end
		local later, later_env = open(db)
		check("an index not built yet says nothing and is being built", later.world.index_pending() and #later.world.lookup("npc", 10) == 0)
		local rounds = 0
		later_env.debugprofilestop = function()
			rounds = rounds + 1
			return rounds
		end
		later.segments.tick()
		check("a frame builds only some of it", later.world.index_pending())
		later_env.debugprofilestop = nil
		while later.world.index_step(1000) do
		end
		check("the index is built from the rows", not later.world.index_pending() and db.ixVersion == 1 and table.concat(later.world.lookup("item", 20), "|"):find("Vendor: Creature", 1, true) == nil and #later.world.lookup("item", 20) == 3 and later.world.lookup("npc", 2000)[1] == "Sells Cloth")
		later_env.clock_now = 9000
		later.world.flush(true)
		local third = open(db)
		check("once built it is not built again", not third.world.index_pending() and third.world.lookup("npc", 2000)[1] == "Sells Cloth")
	end

	-- An entry whose row is gone is skipped.
	do
		local addon, env = open({})
		addon.world.store("npcs", { id = 10, name = "Hogger" })
		addon.world.store("drops", { npcId = 10, itemId = 20, drops = 4 })
		env.clock_now = 5000
		addon.world.flush(true)
		local db = env.EverlookDB
		db.pages["drops.0"] = nil
		db.pageCounts["drops.0"] = nil
		local later = open(db)
		check("a tooltip skips an entry whose row is missing", #later.world.lookup("item", 20) == 0)
	end

	-- A client whose encoder cannot hand a page back whole keeps rows as tables.
	do
		local addon, env = load(function(e)
			e.EverlookDB = { raw = { npcs = { [1] = { id = 1, name = "Boar", locations = { { mapId = 1, x = 1, y = 2 } } } } } }
		end)
		env.C_EncodingUtil.DeserializeCBOR = function(handle)
			local table_back = {}
			table_back.lossy = true
			return table_back
		end
		addon.world.load_saved()
		check("a lossy encoder is noticed and rows stay as tables", not addon.pages.active() and env.EverlookDB.pagesCheck ~= "ok" and env.EverlookDB.raw.npcs[1].name == "Boar" and addon.world.row("npcs", 1).name == "Boar")
		addon.world.store("npcs", { id = 2, name = "Wolf" })
		addon.world.flush(true)
		check("the old whole-world flush is used", env.EverlookDB.raw.npcs[2].name == "Wolf" and env.EverlookDB.manifest == nil)
	end

	-- A client that cannot encode keeps the whole-world path.
	do
		local addon, env = load()
		env.C_EncodingUtil = nil
		addon.world.reset()
		addon.world.load_saved()
		addon.world.store("npcs", { id = 1, name = "Boar" })
		check("without an encoder nothing is paged", addon.pages.enabled() == false and addon.segments.finish() == false and addon.world.row("npcs", 1).name == "Boar")
	end

	-- An engine that will not serialize a page does not stop the rest.
	do
		local addon, env = open({})
		addon.world.store("npcs", { id = 1, name = "Boar" })
		addon.world.store("items", { id = 5, name = "Linen" })
		local serialize = env.C_EncodingUtil.SerializeCBOR
		local refuse = false
		env.C_EncodingUtil.SerializeCBOR = function(value, options)
			if refuse and value.v == 2 and value.b == "npcs" then
				return nil
			end
			return serialize(value, options)
		end
		refuse = true
		env.clock_now = 5000
		settle(addon)
		check("a segment the engine refuses is left out and the others are saved", count_of(manifest_entries(env.EverlookDB)) == 1)
	end
end
