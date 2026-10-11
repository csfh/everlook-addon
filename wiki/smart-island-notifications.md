# Smart Island notifications

Everlook modules and other addons use `Everlook.island`. The Everlook_Island addon puts it on the global `Everlook` table. Call with dot syntax. It is there once that addon loads, even while Smart Island is off in its settings, and missing when a player turns the addon off in the addon list. `Everlook.island` and `Everlook.module` are the supported interface. Other fields on `Everlook` are internal and can change.

For another addon, add `## OptionalDeps: Everlook_Island` to its TOC, then check whether `Everlook` and `Everlook.island` exist before integrating. Integrations stay optional. Notification and subscription handles are separate types of handle; keep them in separate variables.

## Send a notice

```lua
local api = Everlook and Everlook.island
if api then
    local handle, reason = api.notify({
        source = "MyAddon",
        key = "repair-result",
        kind = "repair",
        text = "Equipment repaired",
        detail = "Paid from personal funds",
        money = -21500,
        severity = "success",
        duration = 4,
    })
    -- Save handle if this producer needs to dismiss the notice later.
    -- reason is "disabled" when the player has not enabled Smart Island.
end
```

`notify(payload)` returns a numeric notification handle on success, or `nil, reason` on rejection. The payload must be a plain table without a metatable. Unknown fields are ignored.

| Field | Contract |
| --- | --- |
| `text` | Required nonblank, nonsecret string, at most 512 bytes. WoW font-string formatting is passed through. Toasts wrap the message to their width. |
| `source` | Optional nonblank, nonsecret string, at most 64 bytes. Default `"everlook"`. Use a stable addon/module name. |
| `key` | Optional nonblank, nonsecret string, at most 64 bytes. Updates a matching notice in history, the visible stack, or the queue. Keeps its handle and moves it to the end of history. Visible updates restart their lifetime; queued updates keep their place without starting a timer. Other sources have independent keys. |
| `kind` | Optional nonblank, nonsecret string, at most 32 bytes. Default `"info"`. Chooses a default category icon independently of severity. |
| `duration` | Optional nonsecret, finite number from 1 to 30 seconds. When omitted, the notice uses Notification read time (3 to 10 seconds, default 4). The clock starts when the card is on screen. Time in the queue does not count. Time while the island is open, or while the pointer is on the card, does not count. When the clock ends, the card leaves and a timed inbox row leaves with it. A timed notice that never gets a card uses the same lifetime in the inbox, and that clock pauses while the island is open. |
| `persist` | Optional boolean. Omitted means the notice is timed. `true` keeps the inbox row until the player right-clicks it or the producer withdraws it. The toast still leaves when its read clock ends. Reading the row leaves it in place. A secret or non-boolean value is `invalid_persist`. |
| `stack` | Optional nonblank, nonsecret string, at most 64 bytes. A notice joins a live notice with the same `source` and the same `stack`. The handle stays, `count` increases by one, and the latest text and detail replace the earlier ones. When `count` is greater than 1, the primary line ends with ` ×N`. When both amounts are copper integers, money is added. A timed stack restarts its full lifetime. A matching `source` and `key` updates that exact notice and leaves its count unchanged. Status rows stay separate. `persist` has to match, so a timed notice stays apart from a persistent one. A secret or invalid string is `invalid_stack`. |
| `severity` | `"info"`, `"success"`, `"warning"` or `"error"`; default `"info"`. Explicit labels and colors accompany success, warning and error. Warning/error affect delivery priority. |
| `detail` | Optional nonblank, nonsecret string, at most 512 bytes. Supporting text beneath the primary message. |
| `icon` | Optional nonblank, nonsecret symbolic name, at most 64 bytes. Known names: `generic`, `money`, `bags`, `repair`, `level`, `quest`, `flight`, `mail`, `hearth`, `reputation`, `profession`, `loot`, `clock`. Unknown names use the generic icon. Omission chooses from kind; durability uses repair. Custom texture paths are deferred. |
| `rank` | Optional, `api` 3 or later: `"normal"` (the default) or `"background"`. A background status needs `presentation = "status"` and a valid `capsule`; without one, or with any other `rank` value, the notice is `invalid_rank` (a capsule on a toast is `invalid_capsule`). See **A background status** below. An island older than `api` 3 does not know this key and would show the notice as an ordinary status, so check `Everlook.island.api >= 3` before sending it. |
| `capsule` | Optional, and only when `presentation` is `"status"`. The resting pill's one row; see **The capsule** below. `text` is one plain line of 1 to 64 bytes, without `|` or a newline; `icon`, `trailing` and `progress` are as before, and `arrow`, `ring`, `labels`, `badge` and `min_width` arrived with `api` 3. A clock update keeps the handle and does not mark the notice unread again. |
| `runs` | Optional list of 1 to 6 copied runs, on any presentation. A run is `{ text = "...", tone = "primary" }`, one mark (`icon`, `atlas`, `item_id`, or `spell_id`), or `{ money = -21500 }`. `tone` is `primary`, `secondary`, `accent`, `success`, `warning`, or `error`. The notice `text` stays the tooltip and the plain sentence. Toasts and history draw the compiled runs as their primary line. |
| `money` | Optional signed nonsecret integer in copper, from -9,007,199,254,740,991 to 9,007,199,254,740,991. Native denomination textures and colors include the sign. This exact-integer bound validates display arithmetic; it does not describe the game's currency cap. |
| `progress` | Optional nonsecret finite number from 0 to 1. Omit when progress is unknown. |
| `presentation` | `"toast"`, `"status"` or `"inbox"`; default `"toast"`. Inbox retains a row without a card. Status requires an explicit source and key. |
| `interaction` | `"buttons"`, `"expand"` or `"inbox"`. With actions, the default is `"buttons"`. A notice with no actions stays click-through unless this is `"expand"`. |
| `actions` | Up to two copied actions. Each needs a stable `id`, a visible `label`, and one type. |
| `item_id`, `spell_id` | Optional presentation metadata for a native icon and tooltip. These fields do not click the item or spell. |

Rejections include `disabled`, `invalid_notification`, `invalid_text`, `invalid_source`, `invalid_key`, `invalid_kind`, `invalid_duration`, `invalid_persist`, `invalid_stack`, `invalid_severity`, `invalid_detail`, `invalid_icon`, `invalid_money`, `invalid_progress`, `invalid_presentation`, `invalid_capsule`, `invalid_rank`, `invalid_runs`, `invalid_run`, `invalid_atlas`, `invalid_status_source`, `invalid_status_key`, `invalid_interaction`, `invalid_actions`, `invalid_action`, `invalid_action_id`, `invalid_action_label`, `invalid_action_type`, `invalid_action_callback`, `invalid_action_item`, `invalid_action_spell`, `invalid_item_id` and `invalid_spell_id`. A frozen card rejects `notify` and `dismiss` with `combat_locked`. Accepted fields are copied, so changing the caller's payload has no effect. Invalid input does not add a row or start a timer. Disabled notices are dropped rather than replayed later. No notification data is persisted.

The resting level capsule is 64 × 36, or 88 × 28 with an ongoing activity icon, while up to three toasts appear beneath it. Each toast slides from the island into its own row over 200 ms, using native `OUT` smoothing. Expiration and dismissal fade it back upward over 150 ms. Remaining rows move into the gap after it leaves. New and interrupted motion starts from the current position and opacity.

A burst queues up to five additional notices. Errors promote first, then warnings, then routine notices, preserving arrival order within each tier. At capacity, an incoming notice can evict the oldest lower-priority waiting entry. If every waiting notice has equal or higher priority, the new notice stays in history and uses its ordinary lifetime there. An error can release the oldest visible routine card through its exit. A persistent card keeps its slot until its read clock ends. A released routine card keeps its remaining lifetime in history. A keyed update does not repeatedly preempt cards. When all visible cards are warnings/errors, the unread warning cue stays static while the error waits. Queued notices begin their lifetime when a visible slot becomes free. Toast frames are reused, so repeated notices do not accumulate UI objects.

Up to ten session history rows are kept. A timed row leaves when its clock ends. Past ten rows, the list drops read routine rows first, then unread routine rows, then read warnings, then unread warnings. A persistent row stays until those timed rows are gone. History rows wrap below a fixed summary header. Toast previews show at most three primary lines and two supporting lines, with a More in inbox cue for longer messages; opening the island exposes the complete text. Toast and inbox labels follow the native 14-point primary and 12-point secondary font roles. Money in the summary and notices uses native denomination textures and colors, with a plain-text tooltip. XP stays in a three-unit rail rather than filling notification history. Pointer opening fades the toast stack out over 125 ms and reveals history over 150 ms; keyboard opening hides the stack immediately. Pointer close uses a 125 ms visual fade while capsule input bounds return immediately; existing toast lifetimes pause with their remaining time, and queue promotion waits until closing. A notification first received while open goes into history without creating a toast. Closing the island resumes a paused clock, and when that clock ends the card and the row leave together. Visible rows become read after 750 ms; a quick peek leaves them unread. The capsule shows the retained unread count. The inbox scrolls within a bounded viewport and keeps the inspected row in place as new messages arrive. Right-click a toast or an inbox row to dismiss that notice. There is no close mark. A persistent toast leaves on the read clock and its inbox row stays. Ordinary timed rows leave on their clock. Clear history still clears the rows on screen, including a clock paused while the island is open, and offers a five-second Undo that restores history without replaying toasts. Undo merges later arrivals and retains the ten-row cap. Disabling or reloading clears session history and Undo. A source/key starts a new handle only when it is absent from history, ongoing activities, the visible stack, and the queue.

`dismiss(handle)` returns `true` when it removes a history row or live status, removes a waiting toast, or starts a visible toast's exit; otherwise `false`. It does not dismiss other notices. It invalidates that toast's timeout, and its visible slot becomes free when the exit finishes. Repeated dismissal of a toast already leaving returns `false`. Old handles, timers, and animation completions cannot affect notices created after disabling and re-enabling the island.

## Actions

```lua
api.notify({
    source = "MyAddon",
    key = "ready",
    text = "Hearthstone ready",
    interaction = "buttons",
    item_id = 6948,
    actions = {
        { id = "hearth", label = "Hearth", type = "item", item_id = 6948 },
        { id = "look", label = "Inspect", type = "callback", on_click = function(handle, action_id) end },
    },
})
```

An action is `callback` with `on_click(handle, action_id)`, `item` with `item_id`, or `spell` with `spell_id`. A callback is unavailable in combat unless that action sets `allow_in_combat = true`. Item and spell actions are secure buttons parented to UIParent and lined up with the toast. The button runs only from the player's click. The island does not use the item or cast the spell. Callback, item, and spell buttons share one row in the order they were given, so a secure button does not cover the action beside it.

`buttons` draws the actions on the toast. `expand` opens that notice in the inbox when the card is clicked. `inbox` keeps the toast click-through and shows the actions on the open notice. Hovering a toast keeps it on screen, brings it back if it was already leaving, and does not open the island preview. When the pointer leaves, its clock starts again from the notice's full time. The first action on a notice is the one to press, and it is blue: a deep blue fill inside the game's own gold border (the same as the card's, scaled to fit the button, and a thin gold line where the game cannot draw it), lighter under the pointer with the words turning white, and darker while pressed. The others are the island's quiet grey outline. Blue is the one color on a card. A card with buttons keeps its left clicks; only a notice with no actions, or one set to `inbox`, lets them through to the game. Opening the island ends that pause, because hiding the card does not send a leave event, and closing resumes the remaining time. A keyed update, a removed notice, or a reused frame will not run the action that used to be there. Callback errors go to the addon error handler.

Entering combat freezes a visible armed card: its position, scale, action, and expiry. Its stack slot stays reserved. A protected notice that arrives during combat says it is available after combat and stays unarmed until combat ends. The player's secure dismiss still works during combat. Programmatic dismiss, history clearing, and turning the module off leave a frozen card in place until combat ends or that secure dismiss is applied. Combat that starts during an entrance does not move the secure frame.

## Change a notice that is showing

`notify` returns a handle. Three calls change that notice later, so a producer does not build a new one or reach into the Island's frames. Each returns the handle or `true` on success, and `nil` with a reason on failure.

| Call | What it does |
| --- | --- |
| `update(handle, changes)` | Changes any field a notice takes except `source` and `key`. The result goes through the same checks as `notify`, so a bad value is refused with the same reason. A notice made without a key gets a private one. A change that leaves the notice's text alone does not mark it unread. |
| `set_actions(handle, list)` | Replaces the buttons. An empty list removes them, and a notice whose interaction was the default `buttons` becomes click-through. |
| `set_action_enabled(handle, action_id, enabled)` | Greys out or restores one callback button. It returns `true` when the state changed and `false` when it already was that way. A disabled button does not run. Item and spell buttons are armed by the secure card and cannot be toggled (`action_not_toggleable`). |

An action can also start disabled with `enabled = false` in its table. A notice in combat lock answers `combat_locked`, an unknown handle `unknown_handle`, and an unknown action `unknown_action`.

```lua
local handle = api.notify({ source = "MyAddon", key = "trade", text = "Trade ready",
    actions = { { id = "accept", label = "Accept", type = "callback", on_click = accept } } })
api.set_action_enabled(handle, "accept", false)  -- until the other side confirms
api.update(handle, { detail = "Waiting for them" })
```

## Built-in feeds

Smart island has eight optional feeds. Each starts off, and the first scan is quiet. Missing or secret data does not invent a milestone.

Quest ready keeps one notice for quests that become ready to turn in during this session. One quest uses its title. Several use a count, such as "3 quests ready". View quest and Pin apply to the latest quest in that notice. When none of those quests are still ready, the notice is withdrawn. Quests that were already ready on the first scan stay quiet. Next quest keeps one notice on the suggested quest until you dismiss it or the suggestion changes. Toasts repeat at most every 30 seconds. Pin and Skip are the actions. Skip holds that quest out of the suggestion until it is released, leaves the log, or the session ends.

Rare loot uses the player's own loot-window, straight-to-bag, and bonus-roll messages, including localized positional counts. Crafted items and other players' loot stay out. Rare or better is included. The same item within two seconds stays one notice and keeps that item's count in the title. A different rare item joins the notice while it is still up. A missing stack format still announces a single item. Inspect shows the tooltip.

Reputation announces a faction when its standing rank increases, and later increases join that notice while it is up. Open reputation toggles the reputation pane. Professions announces a 25-point skill milestone or a learned recipe, and combines those within two seconds. A later milestone joins that notice while it is still up. Open professions toggles the profession book.

Hearthstone announces when an owned Hearthstone finishes its own cooldown. The notice stays until you dismiss it or the stone goes on cooldown. A stone that is already ready at login stays quiet, and the pause after a spell stays quiet. Hearth is the item button and Inspect sits beside it. Inspect shows the tooltip. New mail keeps one notice while unread mail is waiting. It stays until you dismiss it or the mail is read. Remind in five minutes snoozes that notice.

Session recap posts every 30 minutes and stays for 12 seconds. Opening the island pauses that clock. Show recap, on the Smart island settings, posts one immediately. The notice expands to completed quests, experience gained, net money, and elapsed time. Experience is marked incomplete when a reading is missing or a level was skipped. At the level cap, an empty experience bar counts as no experience gained.

The Smart island page lists **Show notification toasts** and **Reduce toast motion** under Notices. Turning toasts off clears the stack and queue while keeping history. Reduced motion keeps fades and removes sliding from toasts and pointer transitions, including when changed during an exit. It also snaps the resting pill and the open island to their new size. Pointer open grows the pill's chrome into the island over 150 ms, and pointer close shrinks it over 125 ms. The summary and both panes are clipped to that chrome. The closed face fades out as the open face fades in. Visual frames still rise six units on open and four on close. Buttons keep their final bounds. A completed activity uses a 150 ms success fade within its normal completion toast. Turning Smart Island off clears all notices and cancels visual work. Keyboard peeking and pinning stay immediate. Plain toasts let mouse clicks through to the game.

## Pointing something out

Alt-right-click is the `EVERLOOK_SHARE` binding, which the Everlook_IslandShare addon declares. Its default key is Alt-right-click, and Key Bindings can change it. Smart island has to be on, and so does Share an Alt-right-click.

The click names one subject. A mouseover unit comes first, then an item on the tooltip, then a quest id on the frame under the cursor, then a spell on the tooltip, then the first line of a tooltip while the cursor is over the world. You, a secret name, a keyboard focus, and a cursor with no name stay quiet. The same subject is ignored for the next 0.4 seconds.

The character says that name. An item says its item link when the link is only an item. The island shows the plain name. In a party, the click also sends one addon message on the `Everlook` prefix over `PARTY`. An instance group that is not a home party uses `INSTANCE_CHAT`. In a raid, the message stays with your party group.

A party member with Smart island on sees that message as a notice. The line is the sender's name, a colon, and the subject. The sender's realm is left off when it matches yours. Each sender keeps one notice, and a later point replaces it. A plain whole item id or spell id is shown as the native icon. A message that is not this version-1 text is ignored, so color codes and links from another player do not reach the island. Turning Share an Alt-right-click off stops your own sharing. Notices from other players still arrive.

## The capsule

A status can set the closed pill's one row, with the same parts as a row in the open island:

```lua
api.notify({
    source = "MyAddon", key = "trip", text = "Flying to Ratchet", presentation = "status",
    capsule = {
        icon = "flight",                 -- a mark
        text = "Ratchet",                -- the title, up to 64 bytes
        arrow = function() return angle end,   -- an angle in radians, or a function that gives one
        ring = { fraction = 0.4, tone = "accent" },
        labels = { "~5 yd", { text = "20", tone = "primary" } },   -- up to three, a trailing counts as one
        badge = "45%",                   -- up to 16 bytes
        min_width = 300,                 -- hold this width instead of fitting the words, 64 to 360
    },
})
```

Every part is optional, but a capsule needs at least one. `text` is the title, and it gives way with an ellipsis before the parts after it do. A `trailing` string or mark is the last label, so `labels` and `trailing` together may not pass three. `progress` is shown as a purple percent badge only when the capsule has no `trailing`, `labels` or `badge`; a `badge` wins over it. The row is laid out as in the open island: a mark 9 from the left, the title 34 from the left (12 without a mark), the ring after the title, the labels and badge after it, a 12 gap, and a 12 inset at the right. A producer that updates the words of the capsule with `update` sets them in place: a new distance, a new fraction or a turn of the arrow never fades. Adding or removing a part does.

An `arrow` function follows the same contract as in a row: it is asked when the capsule is drawn and then at most ten times a second while the capsule shows, only a finite number turns the arrow, and one that throws is reported once and not called again until another function is set. A capsule that sets `min_width` is that wide, plus the room for the unread count, and does not resize as its words change.

## A background status

A status with `rank = "background"` is the capsule's standing state rather than an event. It holds the closed pill while nothing else claims it, and gives way to any normal status:

```lua
api.notify({
    source = "MyAddon", key = "quest", text = "Excavation", detail = "~885 yd",
    presentation = "status", rank = "background",
    capsule = { icon = "quest", text = "Excavation", labels = { "~885 yd" } },
})
```

The capsule shows, from first to last: a normal status, the newest background status, then the resting level chip. A background status never expires on the 30-second clock, so the producer withdraws it with `dismiss`. It is not kept in history, shows no toast, never marks the island unread, and does not count toward the ten live statuses. It does not appear in the open island's activity row. Updates keep the handle and the rank. Turning the island off clears every background status, so a producer that wants one back pushes it again when the island is enabled. The island's own quest tracker is a background status.

## Ongoing activity

```lua
local handle = api.notify({
    source = "MyAddon",
    key = "trip",
    text = "Flying to Ratchet",
    detail = "30 seconds elapsed",
    progress = 0.5,
    presentation = "status",
})
-- Updating the same source/key refreshes one identity.
api.notify({
    source = "MyAddon",
    key = "trip",
    text = "Arrived at Ratchet",
    severity = "success",
    presentation = "toast",
})
```

One compact activity row sits below the expanded summary. Without a `capsule`, the closed pill shows the status's category icon beside the level and widens from 64 to 88. With a `capsule`, the level steps aside and the pill shows the leading mark, the readout, and the trailing text when it fits. The pill is 36 pixels tall and is one row: a mark 9 from the left, the readout 34 from the left (12 when there is no mark), then the trailing text or percent, with a 12 gap before it and a 12 inset at the right. Its width is the measured content plus those insets, from 64 up to the smaller of 280 and the screen width minus 32. Past that ceiling the readout is cut short with an ellipsis and the trailing part stays. The tooltip still carries `text`. The unread count stays in the open island while a capsule is showing. The 3-pixel rail shows capsule progress, or the notice progress, in the accent color. With no progress number, the rail keeps showing experience.

The pill eases its width over 0.15 seconds when the measured size changes by 4 pixels or more, using the same `OUT` smoothing as the rest of the island. A change of icon or trailing text crossfades the old and new mark and the old and new line over that same 0.15 seconds. A readout or progress tick replaces in place. Pointer open and close grow this same chrome, and the hit width is the target size on that paint. **Reduce toast motion** snaps the width and still crossfades. The level chip does not gain a loop of its own.

A mark is a known symbolic name, an atlas token of at most 64 bytes matching letters, digits, `_` and `-`, an item id, or a spell id. The closed pill calls `SetAtlas` for an atlas. A run compiles an atlas to `|A:Name:16:16|a`. An unknown atlas or an item whose texture is not loaded yet uses the generic mark until a later paint can resolve it. File paths are rejected.

The most recently started status owns the row, while earlier statuses remain in history. Progress, detail, and capsule clock updates keep ownership and do not rearm unread. Up to ten concurrent live statuses are retained. Every update refreshes a 30-second liveness deadline; an abandoned status becomes history only. Dismissing the owner restores an earlier live activity if present. Completion updates the same source/key to toast presentation, or the producer can dismiss the handle. Moving a toast to status/inbox withdraws its old card and waiting entry.

Clear history removes the inbox entries and toasts; a live activity remains active until its producer completes, dismisses or stops updating it. Undo restores history without replay. Disabling clears live activities and invalidates their deadlines. Neither a stale deadline nor a toast timeout can affect the completed notice.

## Put content in the open island

A section is a block of content your addon places in one of the open island's two panes. It shows while the island is open and never as a toast. Everlook draws it; your addon decides what it says and when it changes.

```lua
local api = Everlook.island
if api and type(api.section) == "function" then
    local handle = api.section({
        source = "MyAddon",
        key = "bosses",
        region = "pane_b",          -- header, metrics, pane_a (beside the quests) or pane_b (above the notifications)
        title = "Bosses",
        order = 500,                -- optional, 100 to 999, lower is higher in the pane
        blocks = {
            { kind = "text", text = "Phase two starts at 40 percent." },
            { kind = "row",
              row = { icon = "quest", title = "Ragnaros", ring = { fraction = 0.4, tone = "warning" },
                      labels = { "3/8" }, badge = "60%" },
              action = { id = "mark", label = "Mark", on_click = function(handle, action_id) end },
              tooltip = { title = "Ragnaros", lines = { "Fire Lord" } } },
        },
    })
    -- Later, with the same functions as a notice:
    api.update(handle, { blocks = { ... } })    -- replaces the blocks, keeps the handle
    api.dismiss(handle)
end
```

`Everlook.island.api` is a whole number that goes up only when something is added, so an addon can test for what it needs. `section` is there from version 1, `react` from version 2, and the capsule's `arrow`, `ring`, `labels`, `badge` and `min_width` from version 3.

`section` returns a handle, or `nil` and a reason. A second `section` call with the same `source` and `key` replaces that section and returns the same handle, so it is safe to push your sections again at login. Sections are never saved: they are gone after a reload, and your addon pushes them again. `update(handle, changes)` takes `title`, `order`, `blocks` and `expires`. `blocks` replaces the whole list; leave a field out to keep it. A section cannot change its `source`, `key` or `region`. `dismiss(handle)` removes it and returns `true`. A handle from `section` and a handle from `notify` are both numbers from one counter and work in the same `update` and `dismiss`.

**Regions.** `header` (rows along the top of the open island, the first the level line), `metrics` (cells under it, four across, two when the island is one pane), `pane_a` and `pane_b`. A header row is set a size larger than a pane row. A section that names another region is rejected with `invalid_region`. A pane with no quest shows the first section's title as its heading. When pane A holds a section and there is no quest, the island opens with two panes anyway.

**Order.** Sections sort by `order`, then by when they were first made. Everlook's own sources take 0 to 99. Yours is 100 to 999, 500 if you leave it out, and the notification history always comes last.

**Blocks.** A block is a table with a `kind` and nothing else but that kind's fields. An unknown key is rejected, so a later release can add fields without breaking yours.

| Kind | Fields |
| --- | --- |
| `row` | `row` (below), optional `action`, optional `tooltip`, and an optional `role` of `text` (the default) or `title`, which sets the row's title in the larger type. A row that has an action or a tooltip lights under the pointer |
| `text` | `text`, up to 320 bytes and four lines, or `runs`, up to six `{ text, tone }` pieces in tones, such as `"ready to turn in"` in `success`. A text right after a row is read as that row's detail and sits close under it |
| `heading` | `text`, up to 48 bytes |
| `gap` | `size` of `within` (4), `near` (8) or `section` (16) |
| `meter` | `label` (32 bytes), `value` (24 bytes), `fraction` from 0 to 1 and an optional `tone`: a name over a value with a thin bar under them |
| `cells` | `cells`, one to six of `{ icon, label, value, tone, tooltip, ring = { fraction, tone } }`: the island's own metric cell, two across in a pane. `icon` is a mark, `label` is 24 bytes, `value` is 24 bytes of text or `{ money = copper }`, which is drawn with the game's coin marks, `tone` colors the value, `tooltip` is 96 bytes of plain text, and a cell with no `ring` shows the empty one. A click on a cell does what a click beside it does |
| `table` | `title` (32 bytes), `columns` (one to three names of 12 bytes), `rows` (one to eight, each a name and one value for every column, 24 bytes each), optional `footer` (160 bytes) and an optional `action` (an `id`, a `label` and `on_click`). The title and the column heads share a heading line, the figures sit right-aligned in 84 wide columns, and an action is a small button after the title, with `label` as its words |

A row has any of `icon` (a mark, as for a capsule), `arrow` (an angle in radians, or a function that returns one), `title` (64 bytes), `ring = { fraction, tone }` with `fraction` from 0 to 1, up to three `labels` (24 bytes each, or `{ text, tone }`) and a `badge` (16 bytes). An `arrow` function is how a direction that changes as you move stays right: the island calls it when it draws the row and then at most ten times a second, only while the row shows, and only a finite number turns the arrow (anything else hides it). A function that throws is reported to the error handler once and not called again until you push the section again.

A tone is `primary`, `secondary`, `muted`, `accent`, `gold`, `success`, `warning` or `error`. An action has an `id`, a `label` (24 bytes) and `on_click(handle, action_id)`. It shows as a small outlined button at the right of the row, in the island's quiet style (a thin outline, no color), and it is a plain button: a section never carries an item or a spell. Errors in `on_click` go to the addon error handler. A tooltip is a `title` and up to six `lines` of plain text.

All text is plain: a pipe, which starts a colour code, a link or a texture, is rejected.

**Limits.** At most 12 sections in the island, 30 blocks in a section, and 8 KB of text for one source. A section that pushes the island or the source past a limit gets `nil, "limit"`. A section can set `expires` (1 to 3600 seconds) to be removed when it is not updated in that time; without it, a section stays until you dismiss it.

**Reasons.** `disabled` (Smart Island is off), `invalid_section`, `invalid_source`, `invalid_key`, `invalid_region`, `invalid_title`, `invalid_order`, `invalid_expires`, `invalid_blocks`, `invalid_block`, `invalid_row`, `invalid_action`, `invalid_action_id`, `invalid_action_label`, `invalid_action_callback`, `invalid_tooltip`, `invalid_update`, `unknown_handle`, `limit`. Turning Smart Island off removes every section.

## Flash the island

A reaction is a brief color on the island's body: a soft tint over it, a line along its straight edges, or both. It says that something happened and carries no content, so it does not replace a notice. It never makes a sound, moves the island or changes its size, and it plays whether the island is closed or open.

```lua
local api = Everlook and Everlook.island
if api and type(api.react) == "function" then
    api.react("kill")
    api.react({ kind = "loot", strength = 0.5, source = "MyAddon" })
end
```

An addon names a kind, and Everlook decides the color, the length and the brightness; it cannot pass a color or a time. `strength` (0 to 1) replaces the kind's own brightness. `react` returns `true`, or `nil` and a reason.

| Kind | Color | Shape |
| --- | --- | --- |
| `kill` | accent | tint and edge, 0.32 s |
| `loot` | green | tint, 0.24 s |
| `level` | gold | tint and edge, 0.6 s |
| `warning` | amber | edge with a light tint, two beats, 0.48 s |
| `error` | red | edge with a light tint, one beat, 0.32 s |
| `info` | grey | tint, 0.2 s |

A new warning or error notice flashes by itself. The tint is never brighter than 18 percent opacity. A reaction that starts within a quarter of a second of another joins it, keeping the louder one, and at most four start in any second; the fifth gets `nil, "limited"`. With **Reduce toast motion** on, a reaction is one short fade from a lower brightness and has no ramp or second beat.

Reasons: `disabled` (Smart Island is off, or **Show reactions** is), `do_not_disturb`, `invalid_reaction` (an unknown kind, an unknown field, or a source that is not text) and `limited`.

The island does not decide that a kill or a level-up happened. **Everlook_IslandReactions** does, with settings under Notices: a level up flashes by default, a kill that gives experience and your own loot do not until you turn them on. This client cannot read the combat log, so a kill is an experience message for one, and a kill that gives none (a grey one) gives no flash. Your own addon can ask for a reaction from an event callback as well; see below.

## Feed a WoW event

```lua
local api = Everlook and Everlook.island
local subscription
if api then
    subscription = api.register_event("QUEST_TURNED_IN", function(event, quest_id, xp, money)
        -- This example deliberately formats none of the event values.
        -- Check issecretvalue before comparing or formatting a value.
        return {
            source = "MyAddon",
            kind = "quest",
            text = "Quest turned in",
        }
    end)
end

-- When this integration is disabled:
if api and subscription then
    api.unregister_event(subscription)
    subscription = nil
end
```

`register_event(event, callback)` returns a numeric subscription handle, or `nil, reason`: `invalid_event`, `invalid_callback`, or `unavailable`. The native client must accept the event. Event names must be nonblank, nonsecret strings of at most 64 bytes. The callback must be a nonsecret function.

The callback receives `(event, ...)` with the original native arguments, including nil arguments. Return a notification payload to publish or `nil` to skip. A payload may also carry `reaction = "kill"` (or any kind above): the island flashes, and the rest of the payload is published as usual. A payload with only `reaction` flashes and adds no notice. Callbacks run only while Smart Island is enabled. They survive a disable/re-enable; the producer removes them when its own integration is switched off. Reloading drops all subscriptions.

Multiple producers may subscribe to one event independently. `unregister_event(handle)` returns `true` for an existing subscription and `false` otherwise. Removing the last subscription unregisters the native event. A subscription removed during dispatch does not run later in that dispatch; a newly added one starts on the next event. Disabling the island during dispatch skips the remaining callbacks.

A callback error or invalid returned payload goes to WoW's error handler with the event name. Other producers still receive the event. Producers must handle secret native arguments safely before building text; the notification interface rejects secret fields without formatting or logging them. Item and spell clicks belong on the action buttons described above.

## Existing producers and verification

Completed quests use the quest name from the last log scan, including a quest that is not the one in the capsule and when the capsule is off. Later turn-ins join that notice while it is up, and reward money adds up. A quest already gone from that scan stays Quest #id. Readable money is included. Level gains publish one success notice using a readable event value even when the getter lags. Bag warnings cross the configured general free-slot threshold (default five), strengthen at zero, and resolve after recovery two slots above the threshold. Specialty and reagent capacity are excluded; unavailable classification gives no inferred warning. Durability shows the lowest readable equipped percentage and warns at 30%, 10% and zero, with a five-point recovery margin. Bag and durability warnings leave the screen on the read clock. The island row stays until you right-click it or the condition recovers. Conditions update one key and resolve when the condition ends. Turning a condition source off dismisses its warning.

Auto repair can report one confirmed result with its personal or guild payment. It waits for an inventory-durability event and a readable zero remaining repair cost, with a bounded three-second observation for a delayed getter. Closing the merchant or disabling Auto repair cancels the observer. Known insufficient personal funds can produce a warning; an attempted request cannot produce success. Matching pending routine-money totals are consumed; mixed totals stay intact.

Sell junk reports confirmed stack proceeds before its total is reset, while retaining its chat report. Its feed can be disabled independently. Each repair result joins an open repair notice. Each junk sale joins an open sale notice. A successful result can consume an exactly matching pending net money summary; a mixed batch remains intact.

Flight activity defaults off and requires Flight time as well as Smart Island. It starts on confirmed taxi travel, refreshes at most once a second, and uses measured elapsed time. A learned duration adds an approximate remaining time and bounded progress; an unknown duration has neither invented estimate nor progress. The closed pill shows that remaining time once a duration is known, and the elapsed time before that, with the destination beside it when the name is short enough. Arrival completes that same identity once. Flight time offers an explicit Island-only option, with the ordinary timer as a fallback.

Routine money notices default off. When enabled, signed changes settle after 750 ms of quiet, with a three-second maximum batch. The default minimum is one silver; the total always updates. Disabling cancels a pending batch, and other readout events do not consume its baseline. `PLAYER_XP_UPDATE` continues updating the native status bar without producing a notice. No new event feeds are enabled automatically.

The addon suite covers external delivery, copied payloads, keyed updates, source isolation, independent expiry, bounded stacking and queuing, frame reuse, interrupted motion, reduced motion, dismissal, stale callbacks, long text, history bounds, secret/invalid inputs, disabled state, event arguments, independent subscriptions, cleanup, dispatch mutation, and producer failures. Client appearance and event delivery from a real external addon remain unverified.

Native names were checked in the exported Mainline source:

- [Frame registration methods](https://github.com/Gethe/wow-ui-source/blob/e3ecc27b64d30fdc735a3f6579b866858f9f9df1/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleFrameAPIDocumentation.lua): `RegisterEvent` returns a registration boolean; `UnregisterEvent` removes the event.
- [Error handling](https://github.com/Gethe/wow-ui-source/blob/f3166dfd584ccf4f7a8e57549e95f9908693c7f9/Interface/AddOns/Blizzard_SharedXMLBase/ErrorUtil.lua): `geterrorhandler` supplies the native error handler.
- [Quest events](https://github.com/Gethe/wow-ui-source/blob/f3166dfd584ccf4f7a8e57549e95f9908693c7f9/Interface/AddOns/Blizzard_APIDocumentationGenerated/QuestLogDocumentation.lua): `QUEST_TURNED_IN` supplies quest ID, XP, and money; `QUEST_WATCH_LIST_CHANGED` has optional arguments. Both inform the local event tests.
- [Native toast animation example](https://github.com/Gethe/wow-ui-source/blob/f3166dfd584ccf4f7a8e57549e95f9908693c7f9/Interface/AddOns/Blizzard_HelpPlate/Blizzard_HelpPlate.lua): creates `Translation` and `Alpha` animations on an animation group. The island uses `OUT` smoothing rather than this example's `IN`.
- [Smoothed animation progress](https://github.com/Gethe/wow-ui-source/blob/f3166dfd584ccf4f7a8e57549e95f9908693c7f9/Interface/AddOns/Blizzard_SharedXML/AnimationTemplates.lua): uses `GetSmoothProgress` to interpolate offsets.

- [Native animation targets](https://github.com/Gethe/wow-ui-source/blob/f3166dfd584ccf4f7a8e57549e95f9908693c7f9/Interface/AddOns/Blizzard_PlayerChoice/Blizzard_PlayerChoiceCypherOptionTemplate.lua): `Animation:SetTarget` directs translations to separate visual frames.
