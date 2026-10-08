# SavedVariables

`Everlook/Everlook.toc` declares one account-wide table. The module addons declare none and keep their settings in it:

```
## SavedVariables: EverlookDB
```

The client stores it at:

`WTF/Account/<account>/SavedVariables/Everlook.lua`

Changing a key on `EverlookDB` in Lua updates memory immediately. The client writes the file when you `/reload`, log out, disconnect, or quit. `PLAYER_LOGOUT` fires immediately before that write. There is no API to flush the file on demand.

So Everlook packs and signs the world document in `PLAYER_LOGOUT` and at no other time. Packing walks every row, and the HMAC runs in Lua: on a world of 1,500 rows one pass took about 60 ms, and on 10,000 rows about 450 ms. An earlier version did this every five seconds while new rows arrived, which froze the game on that beat. Doing it sooner only costs frames, since nothing reads the string before the client writes the file.

The table is available inside `EventUtil.ContinueOnAddOnLoaded`. During the initial file execution it is still nil, so `minimap.lua` assigns it there:

```lua
EverlookDB = EverlookDB or {}
```

## Shape

The collection is `EverlookDB.raw`, a table of rows. The signed upload is `EverlookDB.world` with `signature` beside it. The minimap angle stays with them.

```lua
EverlookDB = {
	minimap = {
		angle = 160,
	},
	raw = {
		npcs = {
			[448] = { id = 448, name = "Hogger" },
		},
	},
	world = "1c....",
	signature = "...",
}
```

`world` is `1c.` or `1r.` plus Base64. `1c.` is raw DEFLATE of CBOR. `1r.` is the same CBOR without compression, used when compression does not make the string shorter. The site turns that document back into quest, item, drop, and NPC rows. `signature` is the HMAC of that string.

`minimap.angle` is written when the button is dragged. The button texture is always `assets/logo.tga`.

## Load

On addon load, `EverlookDB.raw` becomes the row table. A later sighting merges into those rows. The load line reports the count.

Logout packs `raw` into `world` when the rows changed, then signs that string. The addon leaves `world` unread. A logout with no new sighting leaves the signed string where it is.

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
