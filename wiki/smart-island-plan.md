# Smart Island plan

Make the island useful in a glance, quiet during play, and easy for other addons to feed. Keep the current level/XP chip, hover preview, click-to-pin, and tap/hold binding. The feature stays optional and starts disabled.

This plan comes from reading `smart_island.lua` and its tests. Appearance, contrast over the game world, UI scale, and feel have not been verified in the client. The notification interface and a bounded animated toast stack are implemented. The rounded surface, fixed summary header and measured history rows are implemented. A ten-entry retained inbox, unread dwell, bounded scrolling and paused inspection lifetimes are implemented. Rich detail, native currency, severity priority and one ongoing-status row are implemented. Pointer transitions, toast handoff and one-shot level feedback are implemented. Source policies and controls are the next stages in the approved plans under plans/. Client appearance remains unverified.

## What the source shows

| Current behavior | Proposed improvement | Player benefit |
| --- | --- | --- |
| Toasts now wrap at up to 320 units wide (`size_toast`); expanded history still uses unwrapped rows. | Refine sizing at different UI scales and wrap full text in the expanded view. | Long notices remain readable in both views. |
| The expanded view centers metric labels across the full frame height (`ensure_frame`). | Give the summary a fixed header row and place notice rows below it. | New history rows do not shift the summary into the list. |
| XP fills the whole surface, including history (`ensure_frame`, `paint_fill`). | Put XP in a thin rail along the header's lower edge. Preserve native status-bar handling of secret XP. | Text keeps a stable background while XP remains visible. |
| Three toasts now have independent lifetimes, with a five-entry queue and keyed updates (`show_toast`, `pump_toasts`). | Add meaningful priority and coalesce routine source events. | Warnings stay visible without routine events filling the queue. |
| Four notices are kept, and leaving the expanded view clears them (`leave_open`). | Separate opening, reading, and dismissing. Retain a small session inbox until explicit dismissal. | A quick hover cannot discard a warning. |
| Money and bag changes produce individual notices (`snapshot_then`). | Batch money deltas and notify for meaningful bag/durability thresholds. | Routine play produces less interruption. |

These are source findings. They do not establish a measured contrast failure or an in-game rendering defect.

## 1. Feed notifications through one interface

Implemented in this change. Everlook modules and other addons use `Everlook.island.notify` and `dismiss`. `register_event` and `unregister_event` let a producer translate a native WoW event into a notice without owning another event frame. Existing island event producers use the same notification path.

Messages have a source, optional source-scoped key, category, text, and banner duration. The island owns copied records, caps its history, ignores notices while disabled, and invalidates superseded timeouts. Notification data remains in memory. Producer errors go to WoW's error handler with event context.

See [the notification API](smart-island-notifications.md) for the complete current contract. This interface supports in-client addon callers. Desktop or web feeds would require a separate transport design.

## 2. Make the surface readable

Use three clear states:

| State | Content | Interaction |
| --- | --- | --- |
| Quiet chip | Level, compact XP rail, and an unread indicator once inbox behavior exists. | Hover previews; click or tap pins; holding the key peeks. |
| Brief notice | Small category icon, primary message, optional supporting detail. | Opening reveals the complete message in the inbox. |
| Expanded | Stable summary header, XP rail, followed by readable notification rows. | Pin stays put; individual dismiss controls acknowledge messages. |

Start the native layout at 28 units high for the chip/header, 12 units of horizontal padding, and 8 units between an icon and its text. These are starting values to check against WoW UI scale, rather than CSS pixels. Keep the visual target small while giving it a forgiving mouse area that does not block nearby game controls.

Use a primary label one step above the secondary text. Secondary metrics and timestamps use a quieter color; currency keeps gold, silver, and copper coloring and native coin textures. Category icons supplement words. Warning meaning must remain clear without relying on color.

Measure notice text before sizing. Start with a 240–360 unit notice width, clamp to the available screen width, and reserve space for the icon and padding. In the expanded view, wrap message bodies to two or three lines and keep the full text reachable. Keep the header at a fixed height even when history grows. Verify font behavior for long localized strings and large currency values.

Use one dark surface with a subtle border. Readability over bright terrain, busy cities, and dark interiors determines the final opacity and text colors. Resolve textures and frame methods against the Mainline source before implementing them.

Acceptance: no overlap or lost text at supported UI scales; summary placement stays fixed as notices arrive; money remains legible; every supported state works with the existing keybinding.

## 3. Make notification behavior predictable

Keep the implemented separate toast and history lifetimes. A toast expires independently of its history row; extend history retention across opening and closing, until explicit dismissal or session-history eviction. Hovering reads the inbox without deleting it. Clear history when disabling the module and on reload.

Build on the three active toast slots and bounded queue. Pause reading time while the player is inspecting a notice. Preserve implemented source/key updates and timer resets. Do not play expired queue entries. When a burst reaches the limit, coalesce routine updates and retain warnings before routine information. Add explicit severity only when the queue/rendering behavior uses it; the current `kind` field is a category.

Try a 10-row inbox while retaining the current five-entry waiting queue; verify that these limits feel quiet in real play. Show an unread count. Provide clear per-row dismissal and a single clear-history control inside the expanded view.

Keep protected actions outside notification callbacks. If actionable notices become useful, design their secure-button behavior as a separate slice and test it during combat. Do not accept arbitrary click callbacks in notification records.

Acceptance: preserve the bounded burst and keyed-update behavior already tested; a hover must no longer erase history; disabling and stale callbacks must stay deterministic.

## 4. Connect useful sources

Keep the four existing sources: level, money, durability, and free bags. Add source toggles and thresholds on the Smart island page, under Activity, before widening the default feed.

| Source | Proposed message policy |
| --- | --- |
| Level | One completion notice with level and a restrained success treatment. |
| Money | Coalesce related gains/spending over a short window; preserve the signed net amount. |
| Durability | Notify when crossing configured thresholds, with recovery clearing that warning. |
| Bags | Notify near full and at full; avoid repeating a notice for every occupied slot. |
| Auto repair / sell junk | Publish the module's result with rich currency and a source-scoped key. |
| Quest turn-in | Optional concise completion notice; avoid showing duplicate XP/money notices from the same transaction. |
| Other addons | Opt-in integrations through the public API; document source/key conventions and lifecycle cleanup. |

Callers must check secret event values before formatting, comparing, or concatenating them. The island validates the message boundary and continues to pass secret XP directly to the native status bar. Avoid adding health, power, chat, or names to the built-in feed.

Acceptance: modules remain independently optional; the default UI remains intact; thresholds prevent routine event spam; producer tests verify results and cleanup through the public interface.

## 5. Tune the toast motion in the client

The toast slice implements native translation and alpha animation with `OUT` smoothing: 200 ms for entrance and reflow, 150 ms for exit. Toasts emerge from the island, settle into separate rows, and fade slightly upward when leaving. Retargeting samples the current smoothed position and opacity. Frames are reused and disabling invalidates pending timers and animation completions.

The reduced-motion setting removes translation and retains fades, including when changed during an exit. Keyboard peeking and pinning remain immediate; metric updates stay still. Opening the island hides the stack immediately and uses history instead.

Client acceptance: verify the impression of notices emerging from the island, the spacing between stacked rows, long-text movement, interrupted updates, exit/reflow timing, and the fade-only setting. Tune motion after that review. Native appearance and feel remain unverified.

## Delivery and verification

Deliver the remaining stages as small addon commits: layout refinements, retained inbox and priority behavior, then source policies. The API and animated stack already have their own commits. Each stage keeps its own regression tests and can be reverted alone. Run `just test addon`, Lua 5.1 syntax checks, and `git diff --check` for each implementation stage.

A client review must cover the quiet chip, brief notice, empty expanded view, long text, full inbox, burst queue, hover, pin, hold/release, disabling, reload, and combat. Check at normal and high UI scale over bright and dark backgrounds, with another addon producing messages and with unavailable/secret values. Also check that the island does not take input intended for nearby Blizzard UI.

No game input was sent during this work. The proposed visual changes remain unverified until someone reviews them in the client.
