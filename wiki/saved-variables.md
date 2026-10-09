# SavedVariables

`Everlook/Everlook.toc` declares one account-wide table. The module addons declare none and keep their settings in it:

```
## SavedVariables: EverlookDB
```

The client stores it at:

`WTF/Account/<account>/SavedVariables/Everlook.lua`

Changing a key on `EverlookDB` in Lua updates memory immediately. The client writes the file when you `/reload`, log out, disconnect, or quit. `PLAYER_LOGOUT` fires immediately before that write. There is no API to flush the file on demand.

So Everlook keeps the signed upload up to date as it goes, in pieces, and finishes it in `PLAYER_LOGOUT`. Packing every row and signing the result in one pass cost 60 ms on 1,500 rows and about 450 ms on 10,000, and it grew with everything ever collected. An earlier version did that every five seconds while new rows arrived, which froze the game on that beat. The upload is now a set of segments (see Shape). A sighting marks the one segment that holds the row, and a segment is packed, compressed and hashed about a millisecond a frame once it has been quiet for 15 seconds. Nothing runs in combat, and the budget halves under 30 frames a second. Logout encodes what is left within 400 ms and names anything it could not finish in `EverlookDB.staleSegments`, which goes first next session. What it costs follows what changed in the session, not how much has been collected.

The table is available inside `EventUtil.ContinueOnAddOnLoaded`. During the initial file execution it is still nil, so `minimap.lua` assigns it there:

```lua
EverlookDB = EverlookDB or {}
```

## Shape

The collection is `EverlookDB.pages`, a table of strings. The signed upload is `EverlookDB.segments` with `manifest`, `signer` and `signature` beside it. The minimap angle stays with them.

```lua
EverlookDB = {
	minimap = {
		angle = 160,
	},
	pages = { ["npcs.0"] = "p1....", ["npcs.12480"] = "p1....", ["drops.0"] = "p1...." },
	pageCounts = { ["npcs.0"] = 40, ["npcs.12480"] = 31, ["drops.0"] = 404 },
	segments = { ["npcs.1.0"] = "2c....", ["npcs.1.12480"] = "2c...." },
	manifest = "2;1789506741;66263;enUS;120005;0.30.0;drops.1.0=404:ab12...,npcs.1.0=40:cd34...",
	signer = "...",
	signature = "...",
}
```

Rows used to be saved as Lua tables, in `EverlookDB.raw`. Lua 5.1 stops compiling a chunk at about 262,000 distinct constants, which in this file is somewhere past 160,000 rows, and a file that does not compile loses everything in it. Tables also all sit in memory, about 3.4 KB a row. So the collection is saved as strings instead, and a row is decoded only when something reads it.

A page is the rows of one bucket whose first key falls in a range, saved as `p1.` plus Base64 of raw DEFLATE of CBOR of `{ [key] = row }`. The rows are kept exactly as stored, not packed. The page `npcs.12480` holds creatures from id 12480 up to the next page's start. Which page holds a key is worked out from the key and the list of page starts, which is read from the names in `pages`, so nothing else is saved to find it. A page with more rows than its bucket allows (24 to 1,024) is cut in two at its middle key, and only its own rows move. The page saved first is the new one, so a split cut short loses nothing, and a row left in the old page that belongs to the new one is skipped on load. `pageCounts` gives each page's rows, so the total is known without reading any page.

Up to 48 pages stay decoded, the ones used last. A page with changes that are not saved yet is never let go. A page read back is a new table, and nothing keeps hold of a row between events: a row is looked up when it is needed. A tooltip's lines are written from the rows as they are then.

On load a self-test sends a sample row through the encoder and back. `EverlookDB.pagesCheck` is `ok`, or says what came back different. If it is not `ok`, rows stay as tables in `EverlookDB.raw`, as before, and the whole world is packed at logout.

Some features need to find rows without reading every page, so lists kept beside the rows are saved as pages of their own: `ixItemVendors`, `ixNpcSells`, `ixItemDrops`, `ixNpcCasts`, `ixNpcQuests` and `ixObjectLoot` hold up to three entries for each id a tooltip names, and `ixMapPins` lists, for each map, the quests, objects, flight masters and the creatures that are rare, train or sell that have a place on it. They are updated as rows are stored, saved with the rest, and never uploaded. `EverlookDB.ixVersion` says they were built. A collection saved before they existed gets them built from its rows in the background, a few rows a frame, and tooltips and map pins show nothing until that finishes. An entry whose row is missing is skipped. Raising the version in `world.lua` has every list built again.

A segment is the upload form of one page. Its name is `<bucket>.1.<start>`, and the second part says rows are grouped by page. It is `2c.` or `2r.` plus Base64 of a CBOR map `{v = 2, b = bucket, r = rows, s = strings}`. `2c.` is raw DEFLATE, and `2r.` is the same CBOR when compression does not make it shorter. The rows are packed as in the old whole document, with a string table of their own. A `sources` list is never interned, because the site reads a number there as one of five fixed names.

`manifest` lists every segment with its row count and the SHA-256 of its stored text. `signature` is the HMAC of the manifest, so it covers every segment through its digest. The manifest, the segments and the signature are swapped in together once everything staged is hashed, so what the game saves always agrees with itself. A new token signs the manifest again and leaves the segments alone.

A page and its segment are both saved in the background once the page has been quiet for 15 seconds. At logout every page that changed is saved first, whatever it takes, because nothing else would keep its rows. Segments are built as far as 400 ms allows, and the rest are named in `EverlookDB.staleSegments` and go first next session.

An older `raw` is moved into pages in the background. Its tables stay the saved copy, and stay in memory as the rows, until every page is saved, and then it is dropped in the same step. A row stored meanwhile goes into both. A logout before that leaves `raw` as it was, and the next session starts the move again. Before the first full set of segments is signed, an older `world` and its `signature` stay where they are, and the commit that writes `manifest` removes `world`. A client that cannot encode keeps writing `world` as before, and the site reads either. If a `world` and a `manifest` are both present, an older addon ran in between and the manifest is dropped.

`EverlookDB.flushStats` holds how many pages and segments were saved, how long each stage took in total (`stageMs`), how long logout took, how many segments it left, and how many pages were decoded and how slowly.

`minimap.angle` is written when the button is dragged. The button texture is always `assets/logo.tga`.

## Load

On addon load, `EverlookDB.raw` becomes the row table. A later sighting merges into those rows. The load line reports the count.

On load, the page list comes from the names in `pages`, and the manifest says which segments are already saved. A segment whose row count differs from its page, or that logout left unfinished, is queued.

The world document includes the character's current talent rank. Classic talents store the rank from `GetTalentInfo`. Retail nodes store `node.currentRank`. `world.lua` packs both into the talents bucket. With a profession window open, `recipes.lua` records the recipe ids from `C_TradeSkillUI.GetAllRecipeIDs()`.

## Experience ledger

`EverlookDB.experience` holds the Smart island hour and day totals. Each key is a character GUID that starts with `Player-`. The value keeps a baseline (`level`, `xp`, `xp_max`) and one row per minute that earned experience. A row stores `total`, `quest`, `kill`, `other`, `unsorted`, `levels`, and whether that minute lost a reading. The next save drops rows older than 25 hours. `/reload` keeps the ledger. On Forever 1.60.1 a full client restart can skip loading account SavedVariables and then overwrite the file, so this table can vanish with the rest of `EverlookDB`. It lives in that same account file. The world document leaves it out.

`EverlookDB.npc_titles_cvars` holds the values of `nameplateShowFriendlyNpcs`, `UnitNameNPC` and `UnitNameFriendlySpecialNPCName` from before NPC names on nameplates switched them. It exists only while the module is on with its switch option, and the module puts those values back and deletes the table when it goes off. The world document leaves it out.

`EverlookDB.island_history` holds the Smart island inbox between sessions. Each key is a character GUID. The value has `saved_at` (server time) and up to 30 `rows`, each with `source`, `key`, `kind`, `text`, `detail`, `severity`, `icon`, `money`, `count`, `unread` and `age` in seconds. Rows that track a live condition, carry actions or are a status are left out. The island writes the table in `PLAYER_LOGOUT`, loads it once per session, and drops buckets and rows older than 24 hours. The world document leaves it out.

## Load failure on this beta

On Forever 1.60.1 the client writes `WTF/Account/<account>/SavedVariables/` and then does not load those files back into Lua on the next UI load. `ADDON_LOADED` still fires. `EverlookDB` arrives nil. The addon builds a fresh table, and the next save writes that over the file. A dragged angle or an unsent world document from the previous session is replaced by that fresh table.

This was checked when the addon still had an **Enabled** checkbox. After turning it on and reloading, `Everlook.lua` contained `enabled = true`. The checkbox was off again after a full client restart. A later save left the file at `enabled = false`.

The same bug is reported for every addon, and for some Blizzard UI, in [UI/Addon settings wiped on client restart](https://us.forums.blizzard.com/en/wow/t/uiaddon-settings-wiped-on-client-restart/2353992). Files directly under `WTF/SavedVariables/` (such as `Blizzard_Console.lua`) still load. Account SavedVariables do not.

Everlook will keep writing `EverlookDB` the normal way and wait for that client bug to be fixed.

## Sources

- [Saving variables between game sessions](https://warcraft.wiki.gg/wiki/Saving_variables_between_game_sessions)
- [PLAYER_LOGOUT](https://warcraft.wiki.gg/wiki/PLAYER_LOGOUT)
- [SavedVariables](https://warcraft.wiki.gg/wiki/SavedVariables)
