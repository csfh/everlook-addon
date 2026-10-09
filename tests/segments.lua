-- Segments: the world saved in pieces, each packed and hashed once, signed through a manifest.
return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)

	local function load()
		local Everlook = {}
		local tables = {}
		local env = setmetatable({}, { __index = _G })
		env._G = env
		env.time_now = 1000
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
		env.GetTime = function()
			return env.time_now
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
		-- The engine's CBOR is a handle to the table, so a test can read what was packed.
		env.C_EncodingUtil = {
			SerializeCBOR = function(value)
				tables[#tables + 1] = value
				return "cbor:" .. #tables
			end,
			EncodeBase64 = function(value)
				return value
			end,
		}
		env.EverlookDB = {}
		local files = { "world.lua", "location.lua", "sightings.lua", "npcs.lua", "items.lua", "drops.lua", "hash.lua", "config.lua", "segments.lua" }
		for index = 1, #files do
			local chunk = assert(loadfile(source(files[index])))
			setfenv(chunk, env)
			chunk("Everlook", Everlook)
		end
		return Everlook, env, tables
	end

	local function settle(addon)
		local guard = 0
		while addon.segments.step(1000, true, true) do
			guard = guard + 1
			if guard > 10000 then
				error("the segment encoder did not settle")
			end
		end
	end

	local function stored(bucket, rows)
		return rows
	end

	-- Rows land in segments in the order they were first collected.
	do
		local addon, env = load()
		addon.world.reset()
		for id = 1, 40 do
			addon.world.store("npcs", { id = id * 977, name = "N" .. id })
		end
		check("rows of one bucket fill a segment before the next", addon.segments.pending() == 1)
		addon.world.store("npcs", { id = 1, name = "41st" })
		check("a full segment starts another", addon.segments.pending() == 2)
		addon.world.store("drops", { npcId = 70, itemId = 5, drops = 1 })
		addon.world.store("drops", { npcId = 4000000000, itemId = 6, drops = 1 })
		addon.world.store("drops", { npcId = -5, itemId = 7, drops = 1 })
		check("a key's size does not matter, only when the row came", addon.segments.pending() == 3)
		check("a row carries its place", addon.world.row("npcs", 977)._seq == 0 and addon.world.row("npcs", 1)._seq == 40)

		env.GetTime = function() return 5000 end
		env.EverlookDB.raw = nil
		addon.world.flush(true)
		local next_addon, next_env = load()
		next_env.EverlookDB = env.EverlookDB
		next_addon.world.load_saved()
		next_addon.world.store("npcs", { id = 2, name = "42nd" })
		check("a new row after a reload is numbered after the saved ones", next_addon.world.row("npcs", 2)._seq == 41 and next_addon.world.row("npcs", 977)._seq == 0)

		local legacy, legacy_env = load()
		legacy_env.EverlookDB = { raw = { npcs = { [5] = { id = 5, name = "A" }, [6] = { id = 6, name = "B" }, [7] = { id = 7, name = "C", _seq = 9 } } } }
		legacy.world.load_saved()
		local seen = {}
		for id = 5, 7 do
			seen[legacy.world.row("npcs", id)._seq] = true
		end
		check("saved rows with no place are numbered after those with one", seen[9] and seen[10] and seen[11])
	end

	-- Only a change marks a segment, and only its own.
	do
		local addon, env = load()
		addon.world.reset()
		addon.world.store("npcs", { id = 1, name = "A", locations = { { mapId = 1, x = 10, y = 10, seen = 1 } } })
		addon.world.store("npcs", { id = 500, name = "Far" })
		env.GetTime = function() return 5000 end
		settle(addon)
		check("settling empties the line", addon.segments.pending() == 0)
		addon.world.store("npcs", { id = 1, name = "A", locations = { { mapId = 1, x = 10, y = 10, seen = 0 } } })
		check("an identical restatement marks nothing", addon.segments.pending() == 0)
		addon.world.store("npcs", { id = 1, name = "A", locations = { { mapId = 1, x = 10, y = 10 } } })
		check("a repeat pin marks its segment", addon.segments.pending() == 1)
		settle(addon)
		addon.world.count("drops", { npcId = 1, itemId = 2, drops = 1 })
		settle(addon)
		addon.world.count("drops", { npcId = 1, itemId = 2, drops = 3 })
		check("a counter marks its segment", addon.segments.pending() == 1)
		settle(addon)
		addon.world.store("npcs", { id = 1, minLevel = 4 })
		check("only the segment that changed is marked", addon.segments.pending() == 1)
		collectgarbage("collect")
		collectgarbage("stop")
		local before = collectgarbage("count")
		local scratch = { npcId = 1, itemId = 2, drops = 1 }
		for _ = 1, 1000 do
			addon.world.count("drops", scratch)
		end
		local grown = collectgarbage("count") - before
		collectgarbage("restart")
		check("repeat counts allocate nothing", grown < 2)
	end

	-- The manifest, the digests and the signature agree with the segments.
	local function manifest_entries(db)
		local entries = {}
		for name, count, sha in db.manifest:gmatch("([%w]+%.%d+%.%d+)=(%d+):(%x+)") do
			entries[name] = { rows = tonumber(count), sha = sha }
		end
		return entries
	end

	do
		local addon, env, tables = load()
		addon.config.token = "token-1"
		addon.world.reset()
		addon.world.store("maps", { id = 1, name = "Elwynn" })
		addon.world.store("npcs", { id = 1, name = "Boar", locations = { { mapId = 1, x = 10, y = 10, zone = "Elwynn" } } })
		addon.world.store("npcs", { id = 2, name = "Boar", locations = { { mapId = 1, x = 11, y = 10, zone = "Elwynn" } } })
		addon.world.store("npcs", { id = 900, name = "Wolf" })
		addon.world.store("drops", { npcId = 1, itemId = 5, drops = 2 })
		env.GetTime = function() return 5000 end
		settle(addon)
		local db = env.EverlookDB
		local entries = manifest_entries(db)
		local names, rows_listed = 0, 0
		local digests_agree = true
		for name, info in pairs(entries) do
			names = names + 1
			rows_listed = rows_listed + info.rows
			if addon.hash.sha256(db.segments[name]) ~= info.sha then
				digests_agree = false
			end
		end
		check("every segment is listed with the digest of what is saved", names == 3 and digests_agree)
		check("the manifest counts every row once", rows_listed == addon.world.row_count())
		check("the manifest carries the header the server reads", db.manifest:match("^2;1789506741;66263__x_;enUS;120005;0%.30%.0;") ~= nil)
		check("the signature covers the manifest", db.signature == addon.hash.hmac_sha256("token-1", db.manifest) and db.signer == addon.hash.sha256("token-1"):sub(1, 16))
		check("a segment saved holds the rows of one bucket", tables[1].b ~= nil and tables[1].v == 2 and type(tables[1].r) == "table")

		-- Every row is in one segment, and the segments hold what document() packs.
		local document = addon.world.document()
		local expected, found = {}, {}
		for _, bucket in ipairs({ "maps", "npcs", "drops" }) do
			expected[bucket] = #document[bucket]
			found[bucket] = 0
		end
		local first_cells = {}
		for _, document_table in ipairs(tables) do
			found[document_table.b] = (found[document_table.b] or 0) + #document_table.r
			for _, packed in ipairs(document_table.r) do
				first_cells[document_table.b .. ":" .. packed[1]] = true
			end
		end
		check("the segments together hold the rows document() packs", found.maps == expected.maps and found.npcs == expected.npcs and found.drops == expected.drops)
		check("each row is in the segment its first key names", first_cells["npcs:900"] and first_cells["npcs:1"] and first_cells["npcs:2"] and first_cells["drops:1"] and first_cells["maps:1"])
		local strings = nil
		for _, document_table in ipairs(tables) do
			if document_table.b == "npcs" and document_table.s then
				strings = document_table.s
			end
		end
		check("a string repeated in a segment is interned in it", strings ~= nil and (strings[1] == "Boar" or strings[2] == "Boar" or strings[1] == "Elwynn" or strings[2] == "Elwynn"))
		check("a world is not saved whole beside the manifest", db.world == nil)
	end

	-- A source that is a word stays a word, because the site reads a number there as a fixed name.
	do
		local addon, env, tables = load()
		addon.config.token = "token-1"
		addon.world.reset()
		addon.world.store("items", { id = 1, name = "Linen", sources = { "fishing", "bag" } })
		addon.world.store("items", { id = 2, name = "Linen", sources = { "fishing", "bag" } })
		addon.world.store("items", { id = 3, name = "Wool", sources = { "fishing" } })
		env.GetTime = function() return 5000 end
		settle(addon)
		local items
		for _, document in ipairs(tables) do
			if document.b == "items" then
				items = document
			end
		end
		local source_cells = {}
		for _, row in ipairs(items.r) do
			source_cells[#source_cells + 1] = row[#row]
		end
		check("sources are never replaced by a string index", items.s ~= nil and items.s[1] == "Linen" and source_cells[1][1] == "fishing" and source_cells[1][2] == "bag" and source_cells[3][1] == "fishing")
		check("the other columns are still interned", type(items.r[1][2]) == "number" and items.r[1][2] == items.r[2][2])
	end

	-- A segment that keeps changing is not packed over and over.
	do
		local addon, env = load()
		addon.config.token = "token-1"
		addon.world.reset()
		local scratch = { npcId = 1, itemId = 2, drops = 1 }
		env.GetTime = function() return 100 end
		addon.world.store("drops", { npcId = 1, itemId = 2, drops = 1 })
		env.GetTime = function() return 500 end
		addon.segments.step(0, false, false)
		local _, _, running = addon.segments.pending()
		check("a segment past its longest wait is picked", running == true)
		addon.world.count("drops", scratch)
		while addon.segments.step(0, false, false) do
			local _, _, still = addon.segments.pending()
			if not still then
				break
			end
		end
		local queued, _, job = addon.segments.pending()
		check("a segment touched mid-pack waits out its quiet time again", queued == 1 and job == false)
		env.GetTime = function() return 520 end
		addon.segments.step(0, false, false)
		local _, _, again = addon.segments.pending()
		check("it is packed once it has been quiet", again == true)
	end

	-- Logging out while the move to segments is unfinished saves a consistent, partial set.
	do
		local addon, env = load()
		addon.config.token = "token-1"
		env.EverlookDB = { raw = { npcs = {} }, world = "1c.legacy", signer = "old", signature = "olds" }
		addon.world.reset()
		for id = 1, 120 do
			env.EverlookDB.raw.npcs[id] = { id = id, name = "N" .. id, _seq = id - 1 }
		end
		addon.world.load_saved()
		local ticks = 0
		env.debugprofilestop = function()
			ticks = ticks + 60
			return ticks
		end
		addon.world.flush(true)
		local db = env.EverlookDB
		local entries = manifest_entries(db)
		local agree, count = true, 0
		for name, info in pairs(entries) do
			count = count + 1
			if addon.hash.sha256(db.segments[name]) ~= info.sha then
				agree = false
			end
		end
		local left = db.staleSegments and #db.staleSegments or 0
		check("a logout mid-move saves a manifest that agrees with its segments", db.world == nil and count > 0 and agree and left > 0 and count + left == 3)
		check("what was left is signed for", db.signature == addon.hash.hmac_sha256("token-1", db.manifest))
		local next_addon, next_env = load()
		next_addon.config.token = "token-1"
		next_env.EverlookDB = db
		next_addon.world.reset()
		next_addon.world.load_saved()
		check("the segments it left come back waiting", next_addon.segments.pending() == left)
	end

	-- A second session writes only what changed.
	do
		local addon, env = load()
		addon.config.token = "token-1"
		addon.world.reset()
		for id = 1, 200 do
			addon.world.store("npcs", { id = id * 100, name = "Creature " .. id })
		end
		env.GetTime = function() return 5000 end
		settle(addon)
		addon.world.flush(true)
		local saved = env.EverlookDB
		local first_segments = {}
		for name, payload in pairs(saved.segments) do
			first_segments[name] = payload
		end

		local next_addon, next_env = load()
		next_addon.config.token = "token-1"
		next_env.EverlookDB = saved
		next_addon.world.reset()
		next_addon.world.load_saved()
		check("a world saved whole has nothing waiting", next_addon.segments.pending() == 0)
		next_addon.world.store("npcs", { id = 100, name = "Creature 1", minLevel = 7 })
		next_addon.world.store("npcs", { id = 1234567, name = "New" })
		check("only what changed is waiting", next_addon.segments.pending() == 2)
		next_env.GetTime = function() return 9000 end
		settle(next_addon)
		local changed = 0
		for name, payload in pairs(next_env.EverlookDB.segments) do
			if first_segments[name] ~= payload then
				changed = changed + 1
			end
		end
		check("only those segments are written again", changed == 2)
		local kept, listed = 0, 0
		for name in pairs(manifest_entries(next_env.EverlookDB)) do
			listed = listed + 1
			if first_segments[name] == next_env.EverlookDB.segments[name] then
				kept = kept + 1
			end
		end
		check("the other segments are kept as they were saved", listed > 2 and kept == listed - 2)
	end

	-- Moving from a whole world to segments happens in one step.
	do
		local addon, env = load()
		addon.config.token = "token-1"
		env.EverlookDB = { raw = { npcs = { [1] = { id = 1, name = "Boar" }, [2] = { id = 2, name = "Wolf" } } }, world = "1c.legacy", signer = "old", signature = "olds" }
		addon.world.reset()
		addon.world.load_saved()
		check("the whole world waits for the segments", addon.segments.pending() == 1 and env.EverlookDB.world == "1c.legacy" and env.EverlookDB.signature == "olds")
		env.GetTime = function() return 5000 end
		while addon.segments.step(1, true, false) do
			check("the whole world is kept until the segments are signed", env.EverlookDB.world == "1c.legacy" and env.EverlookDB.manifest == nil)
		end
		settle(addon)
		check("the segments replace it together", env.EverlookDB.world == nil and type(env.EverlookDB.manifest) == "string" and env.EverlookDB.signature == addon.hash.hmac_sha256("token-1", env.EverlookDB.manifest))
	end

	-- An older addon that ran in between leaves a world beside a manifest.
	do
		local addon, env = load()
		env.EverlookDB = {
			raw = { npcs = { [1] = { id = 1, name = "Boar" } } },
			world = "1c.newer",
			manifest = "2;1;b;l;1;v;npcs.0.0=1:" .. string.rep("a", 64),
			segments = { ["npcs.0.0"] = "2r.x" },
		}
		addon.world.reset()
		addon.world.load_saved()
		check("a manifest beside a whole world is not trusted", env.EverlookDB.manifest == nil and env.EverlookDB.segments == nil and addon.segments.pending() == 1)
	end

	-- A new token signs the same segments again.
	do
		local addon, env = load()
		addon.config.token = "token-1"
		addon.world.reset()
		addon.world.store("npcs", { id = 1, name = "Boar" })
		env.GetTime = function() return 5000 end
		settle(addon)
		local db = env.EverlookDB
		local manifest, payload = db.manifest, db.segments["npcs.0.0"]
		addon.config.token = "token-2"
		settle(addon)
		check("a new token signs the manifest again", db.manifest == manifest and db.segments["npcs.0.0"] == payload and db.signature == addon.hash.hmac_sha256("token-2", manifest) and db.signer == addon.hash.sha256("token-2"):sub(1, 16))
		addon.config.token = nil
		db.secret = nil
		settle(addon)
		check("with no token the file is unsigned", db.signature == nil and db.signer == nil and db.manifest == manifest)
	end

	-- Logout finishes the line within a limit and says what it left.
	do
		local addon, env = load()
		addon.config.token = "token-1"
		addon.world.reset()
		for id = 1, 200 do
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
		check("logout past its limit saves what it finished and names the rest", type(db.staleSegments) == "table" and #db.staleSegments > 0 and agree and db.flushStats.left == #db.staleSegments)
		check("what is saved agrees with its signature", db.signature == addon.hash.hmac_sha256("token-1", db.manifest))

		local next_addon, next_env = load()
		next_addon.config.token = "token-1"
		next_env.EverlookDB = db
		next_addon.world.reset()
		next_addon.world.load_saved()
		check("the next session starts with what was left", left > 0 and next_addon.segments.pending() >= left)
	end

	-- With time to spare, logout leaves nothing behind and flush does not pack the whole world.
	do
		local addon, env = load()
		addon.config.token = "token-1"
		addon.world.reset()
		addon.world.store("npcs", { id = 1, name = "Boar" })
		addon.world.store("items", { id = 5, name = "Linen" })
		addon.world.flush(true)
		local db = env.EverlookDB
		check("logout saves the segments and the signature", db.manifest ~= nil and db.signature ~= nil and db.staleSegments == nil and db.world == nil)
		check("logout records the rows and bytes saved", db.worldRows == 2 and db.worldBytes == #db.segments["npcs.0.0"] + #db.segments["items.0.0"])
	end

	-- The manifest keeps to what the server reads.
	do
		local addon, env = load()
		addon.config.token = "token-1"
		addon.world.reset()
		addon.world.store("npcs", { id = 1, name = "Boar" })
		addon.world.store("fishingLoot", { mapId = 1, areaId = 2, itemId = 3, casts = 1 })
		env.GetBuildInfo = function() return "x", "build 1;2,3 \195\169", "d", 5 end
		addon.world.flush(true)
		local manifest = env.EverlookDB.manifest
		local header, entries = manifest:match("^(2;%d+;[%w%._%-]*;[%w%._%-]*;%d+;[%w%._%-]*);(.*)$")
		check("the header holds only characters the server accepts", header ~= nil and not header:find("%s"))
		local fine = entries ~= nil
		for entry in (entries or ""):gmatch("[^,]+") do
			if not entry:match("^%a+%.%d%d?%.%d+=%d+:%x+$") or #entry:match(":(%x+)$") ~= 64 then
				fine = false
			end
		end
		check("every entry is a name, a count and a digest", fine)
	end

	-- A client that cannot encode keeps the whole-world path.
	do
		local addon, env = load()
		env.C_EncodingUtil = nil
		addon.world.reset()
		addon.world.store("npcs", { id = 1, name = "Boar" })
		check("without an encoder the segments are off", addon.segments.enabled() == false and addon.segments.finish() == false)
	end

	-- An engine that will not serialize a segment does not stop the rest.
	do
		local addon, env = load()
		addon.config.token = "token-1"
		addon.world.reset()
		addon.world.store("npcs", { id = 1, name = "Boar" })
		addon.world.store("items", { id = 5, name = "Linen" })
		local first = true
		local serialize = env.C_EncodingUtil.SerializeCBOR
		env.C_EncodingUtil.SerializeCBOR = function(value, options)
			if first then
				first = false
				return nil
			end
			return serialize(value, options)
		end
		env.GetTime = function() return 5000 end
		settle(addon)
		local entries = manifest_entries(env.EverlookDB)
		local count = 0
		for _ in pairs(entries) do
			count = count + 1
		end
		check("a segment the engine refuses is left out and the others are saved", count == 1 and env.EverlookDB.manifest ~= nil)
	end
end
