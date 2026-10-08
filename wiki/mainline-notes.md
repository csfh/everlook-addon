# Mainline notes

What we checked against `Gethe/wow-ui-source` at tag `12.0.0` while building the addon. Forever is built on Mainline, so the `Mainline` and `Shared` folders are the reference. Check again before leaning on a fact for a newer client build.

## Reading the source

A sparse clone of the add-on folder is enough, and `grep` over it is fast:

```
git clone --depth 1 --filter=blob:none --sparse --branch 12.0.0 https://github.com/Gethe/wow-ui-source.git
cd wow-ui-source && git sparse-checkout set Interface/AddOns
```

GitHub code search runs out of requests quickly, and the empty lines it returns then look like "not found". Clone instead.

The generated API documentation in `Blizzard_APIDocumentationGenerated` covers the newer, namespaced functions. Many old globals such as `AcceptQuest` are missing from it and still work. The test for a global is whether Blizzard's own code calls it. A name that is in neither place is wrong. That is how `GetQuestRequiredMoney` and `IsQuestRepeatable` were caught in the quest automation module, which had guarded paid and repeatable quests with them for a while without any effect.

## Secret values

In combat and restricted content some values come back secret: health, max health, power, unit names, and the text of chat messages (`SecretInChatMessagingLockdown`). A secret value can go into `StatusBar:SetValue` and `FontString:SetText`. Comparing it or doing arithmetic on it is an error. Blizzard's own unit frames pass health and power to their bars unchanged. Class, level, reaction and connection state are not secret.

## Quests

- Paid turn-ins: `GetQuestMoneyToGet()`, which the default quest frame calls.
- Repeatable quests: `C_QuestLog.IsRepeatableQuest(questID)`, with `GetQuestID()` on the open quest frame.
- Gossip quest tables from `C_GossipInfo` carry `repeatable`, `isComplete` and `isIgnored`.
- Quest text is already complete. `QuestInfo.lua` assigns the description with `SetText`, and a search of 12.0.0 finds no read of `instantQuestText`. The gradient constants in `QuestFrame.lua` are unused. Quest log titles gain `[difficultyLevel]` only while `colorblindMode` is on, and only inside `QuestLogQuests_GetTitle`, which uses `C_QuestLog.GetInfo().title` rather than `GetTitleForQuestID`.

## The settings page

The page is a vertical layout category with subcategories under it: `Settings.RegisterVerticalLayoutSubcategory(category, name)` for lists and `Settings.RegisterCanvasLayoutSubcategory(category, frame, name)` for a frame of our own (both are in `Blizzard_Settings.lua`, and `Blizzard_ImplementationReadme.lua` describes them). The settings window parents and anchors a canvas frame, and calls its optional `OnShow`, `OnRefresh`, `OnCommit` and `OnDefault`. Section headings come from `CreateSettingsListSectionHeaderInitializer` and buttons from `CreateSettingsButtonInitializer`. To toggle the page, compare `SettingsPanel:GetCurrentCategory()` with the category and each subcategory it returned, and call `HideUIPanel(SettingsPanel)` when one matches. The game's own Social settings already include Block guild invites (`GetAutoDeclineGuildInvites`), so the addon leaves that alone.

## Hiding things

Each of these elements shows itself in response to events its own frame registers, so unregistering those events hides it and registering them again brings it back. The default UI does the same for error messages in its `/uierrorsoff` command.

| Element | Frame | Events |
| --- | --- | --- |
| Talking head | `TalkingHeadFrame` | `TALKINGHEAD_REQUESTED` |
| Zone and subzone text | `ZoneTextFrame` | `ZONE_CHANGED`, `ZONE_CHANGED_INDOORS`, `ZONE_CHANGED_NEW_AREA` |
| Red error messages | `UIErrorsFrame` | `UI_ERROR_MESSAGE`. `UI_INFO_MESSAGE` and `SYSMSG` are separate. |
| Raid warning | `RaidWarningFrame` | `CHAT_MSG_RAID_WARNING` |

The boss emote frame is the exception. In 12.0 it receives its messages through a private callback, so unregistering events does nothing.

## Chat

- The chat windows are listed in the global `CHAT_FRAMES`. Each has `editBox` and `ScrollBar` keys, and a tab named `ChatFrame<N>Tab`.
- The game sets a fade time of 120 seconds when a window loads (`ChatFrameOverrides.lua`). A search of the chat code found nothing that changes it later, and nothing that re-anchors the edit box after the XML does.
- `UPDATE_CHAT_WINDOWS` and `UPDATE_FLOATING_CHAT_WINDOWS` fire when the windows are rebuilt.
- The buttons are `ChatFrameMenuButton`, `ChatFrameChannelButton`, `ChatFrameToggleVoiceDeafenButton`, `ChatFrameToggleVoiceMuteButton` and `QuickJoinToastButton`. The game can show them again, so hide them with an `OnShow` hook.
- Chat text can be secret, so a message filter that rewrites text must pass secret text through untouched. Clickable web addresses are not built yet for that reason.

## Prompts and invites

- Summons: `CONFIRM_SUMMON` passes the summon type and whether it skips the starting area. Accept with `C_SummonInfo.ConfirmSummon()`. Starting area summons and `Enum.SummonReason.Scenario` change where you are, so they stay manual.
- Resurrections: `AcceptResurrect()`, then hide the popups `RESURRECT`, `RESURRECT_NO_SICKNESS` and `RESURRECT_NO_TIMER`.
- Party invites: `AcceptGroup()` and `DeclineGroup()`, then hide `PARTY_INVITE`.
- Deleting a good item shows the `DELETE_GOOD_ITEM` popup. Its Yes button enables when the edit box text equals `DELETE_ITEM_CONFIRM_STRING`. Reach the box with `dialog:GetEditBox()` in `OnShow(dialog, data)`.

## Tooltips

`TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, callback)` calls `callback(tooltip, data)`. The types used are `Item` (0), `Spell` (1) and `Unit` (2). The site's pages take the game id: `/database/items/{id}`, `/database/spells/{id}`, `/database/npcs/{id}`, `/database/objects/{id}` and `/quests/{id}`.

## From the removed replacement UI

The replacement action bars and unit frames are gone, but a tweak that touches those areas will meet the same facts:

- Action bar pages come from `ActionButtonUtil.ActionBarType`: `BonusBar` is 6, so `[bonusbar:n]` is page 6 plus n and skyriding (`bonusbar:5`) is page 11. `VehicleBar` is 16, `TempShapeshiftBar` is 17 and `OverrideBar` is 18. `ActionBarController` sets the main bar's `actionpage` in that order: vehicle, override, temporary shapeshift, bonus (on page 1), then the plain page.
- A secure action button finds its slot with `SecureActionButtonMixin:CalculateAction`, which adds the button id to the page. Flyout slots call `SpellFlyout:Toggle`, which needs `GetPopupDirection`, `TogglePopup` and `IsPopupOpen` on the button.
- An addon function that Blizzard's secure click code calls taints the code that runs after it. Flyouts in combat are where that shows.
- `PlayerFrameBottomManagedFramesContainer` holds the class resource bars. It is a sibling of `PlayerFrame` anchored to its bottom edge, so hiding the player frame does not hide them.
- A search of 12.0.0 found no code that moves `MainActionBar`, the stance bar, the pet bar or the unit frames back out of a hidden parent.

## Radial menu and secure actions

The game's own ping wheel is closed to addons. `C_Ping.TogglePingListener` is marked `HasRestrictions`, and calling it from addon code raised the blocked action warning in the game on 2026-10-04. `C_Ping.SendMacroPing`, `FocusUnit`, `SetRaidTarget` and `C_FriendList.AddFriend` carry the same flag. The stock wheel, `RadialWheelFrameTemplate` in `Blizzard_SharedXML`, did draw for our frame, but its wedge text did not show with text-only wedges. Its frame art is also named for the wedge count (`Radial_Wheel_Frame_Count_<n>`) and the Lua does not say which counts exist. The radial menu therefore draws its own ring of labels in `radial_wheel.lua`.

No addon API gives the world point under the cursor. `GetCursorPosition` is a screen position, and `C_PingSecure.GetTargetWorldPing` is secure only. A ping sent from an addon wheel can therefore only land where the cursor is when the call runs.

The macro wedges use Blizzard's slash commands: `/ping` (aliases 1 attack, 2 warning, 3 on my way, 4 assist, from `SlashCommandsOverrides.lua`), `/readycheck`, `/countdown <seconds>`, `/invite`, `/ginvite`, `/friend` and `/duel` with a `Name-Realm`. `/trade` and `/inspect` only read the target, so those stay plain calls on a unit token.

Marks previously used `/tm [@mouseover,exists]`, which loses its unit when the cursor moves away during the flick. `SecureTemplates.lua` provides a native `raidtarget` action, taking `unit`, `marker` and `action` attributes. `action = "set"` keeps an existing identical mark; `action = "clear"` removes it. The radial menu uses a GUID-verified token captured at opening or resolved at release, and clears these attributes after the secure handler runs. Tests cover leaving the enemy, hovering another enemy, reused tokens and clearing marks.

Focus also lost its unit through `/focus [@mouseover,exists]`. It now uses `SecureTemplates.lua`'s native `focus` action with the same GUID-verified token as the marks.

`SlashCommands.lua` calls `FollowUnit(msg)` for `/follow`. Blizzard's `UnitPopupFollowButtonMixin:OnClick` instead passes its native full name and `true` for exact lookup. The first radial fix copied that call but built a different name: it always added the realm. `Blizzard_UnitPopup/Mainline/UnitPopupUtils.lua:GetFullPlayerName` omits your realm, and Forever handles regional surnames with a separate separator. The radial menu now captures `NameUtil.GetUnmodifiedUnitFullName("mouseover")` from `Blizzard_FrameXMLUtil/NameUtil.lua` (or its Camelot override), with `GetUnitName("mouseover", true)` as the older-client fallback. It preserves that value for key release and omits Follow if the name is unavailable or secret. `PlayerScriptDocumentation.lua` documents the exact-match argument and does not mark `FollowUnit` with `HasRestrictions`, unlike the ping and marking APIs. The revised names and native focus action still need a Forever client check.

The key is a click on a `SecureActionButtonTemplate` button bound with a `CLICK EverlookRadialButton:LeftButton` binding in `Bindings.xml`. The button registers `AnyDown` and `AnyUp`. `SecureActionButton_OnClick` acts on key down when `useOnKeyDown` is true, and the default comes from the `ActionButtonUseKeyDown` CVar, so the button sets `useOnKeyDown` to false and acts only on key up. The click scripts run in order: `PreClick`, the secure handler, `PostClick`. Key down opens the wheel from `PreClick`. Key up writes `type` and `macrotext` from `PreClick`, the secure handler runs the macro, and `PostClick` clears them. Writing a protected button's attributes is not allowed in combat, which is why the wheel does not open then. A quick way to get combat support is the secure snippet that EllesmereUI's Quickdraw uses, which chooses the wedge inside the restricted environment. The `Blizzard_PingUI.toc` in the Forever source says `AllowLoadGameType: mainline`, and Quickdraw's own comments say snippets cannot compile on the Forever beta, so that route is unconfirmed.

The wheel samples the cursor again on key release. Reading only the selection saved by `OnUpdate` lost a flick that finished between rendered frames, or fired a previously highlighted wedge after the cursor returned to the centre. Local regression tests run the real wheel and menu together for Focus, Follow, Skull and centre cancellation. A separate local harness ran the unmodified Forever [`SecureTemplates.lua`](https://github.com/Gethe/wow-ui-source/blob/e3ecc27b64d30fdc735a3f6579b866858f9f9df1/Interface/AddOns/Blizzard_FrameXML/SecureTemplates.lua) click handler: Focus failed without an intervening render before the fix and dispatched on key release afterwards. The harness mocks native APIs, so it cannot verify the client's protected-call restrictions or confirm the reported in-game failure is resolved.

A `/ping` with a bracket and no target does nothing (`SlashCommandsOverrides.lua` returns early), so the ping wedges use the plain form and ping whatever is under the cursor.

## Mouse focus over the world

In Forever, `GetMouseFoci()` returns an empty table while the cursor is over the 3D world, not `{ WorldFrame }`. It lists a frame only when interface is under the cursor. The radial menu treats an empty list, or a list that starts with `WorldFrame`, as the world. Seen in the game on 2026-10-04, after a check written from the 12.0.0 source found nothing under the cursor and quietly did nothing. The player's `scriptErrors` setting was 0 at the time, so a Lua error would have been silent too.

## Smart island readouts

The island is Everlook's own `Button` on `UIParent`. It does not hide, reparent, or replace `StatusTrackingBarManager`, the override XP bar, or `EverlookMinimapButton`. Closed size is a small count chip (48×20). Open it is one data bar.

Experience uses the same calls as `OverrideActionBarMixin:UpdateXpBar` in `Blizzard_OverrideActionBar/OverrideActionBar.lua`: `UnitXP("player")`, `UnitXPMax("player")`, `UnitLevel("player")`, then `StatusBar:SetMinMaxValues` and `SetValue`. The bar receives those values directly. A fill percent is only computed when `issecretvalue` says they are usable. `PLAYER_XP_UPDATE` and `PLAYER_LEVEL_UP` are the events that bar already registers.

Money is `GetMoney()`, which Catalog Shop and the store UI also read. Bags follow those same files: `C_Container.GetContainerNumFreeSlots` from `BACKPACK_CONTAINER` through `NUM_BAG_SLOTS`. Durability is `GetInventoryItemDurability(slot)` as `EquipmentManager.lua` reads it, over `INVSLOT_FIRST_EQUIPPED` to `INVSLOT_LAST_EQUIPPED` when those names exist. The clock is `GetGameTime()`, the function `Blizzard_TimeManager.lua` binds. Coordinates reuse `C_Map.GetBestMapForUnit` / `GetPlayerMapPosition` and `Everlook.coordinates.format`, and only when the coordinates module is on.

Health, power, names, and ids stay unread. Those can be secret in combat. Hour and day totals come from plain `UnitXP`, `UnitXPMax`, and `UnitLevel`. A plain `CHAT_MSG_COMBAT_XP_GAIN` string names the kill slice of that total. A secret experience line stays as it arrived.

The island key is a second `runOnUp` binding, the same pattern as `EVERLOOK_RADIAL_MENU`. A tap and a hold have to be distinct, which a settings checkbox cannot do.

## Forever swing timers

The swing timers are absent from the 12.0.0 tag. Their reference is the exported Forever source at [`e3ecc27`](https://github.com/Gethe/wow-ui-source/tree/e3ecc27b64d30fdc735a3f6579b866858f9f9df1). `Blizzard_SwingTimer.xml` names the three frames. `EditModeSettingDisplayInfo.lua` defines Scale as a displayed percent from 50 to 200 in steps of 10; the stored raw value is a step index. `GetSettingValue` returns the displayed value. `UpdateSystemSettingValue` converts it to a raw index and writes `systemInfo.settings`, while `UpdateSystemSetting` also updates the Edit Mode dialog and manager. These tables are shared layout state, so the option must not write either them or `settingMap`. `EditModeSystemTemplates.lua` applies the percent through `SetScale(percent / 100)` in `UpdateSystemSettingScale`; the option uses that visual setter alone, outside combat. `UpdateSystem` initializes a frame and reapplies layouts, so the option hooks both it and the scale update. The tracker similarly uses `ObjectiveTrackerManager:SetTextSize` without writing the Edit Mode text setting. Tests assert that the underlying layout values and dirty flags stay unchanged. Taint behavior still needs a client check.

## Container loot ownership

`Blizzard_APIDocumentationGenerated/LootDocumentation.lua` defines `LOOT_OPENED` with `autoLoot` and `isFromItem` booleans. The item flag alone cannot identify which bag item opened it. `Blizzard_ObjectAPI/ItemLocation.lua` provides `CreateFromBagAndSlot`, and `ItemDocumentation.lua` documents `C_Item.GetItemGUID`. The opener compares that GUID against every source of a slot before calling `LootSlot`.

The legacy `GetLootSourceInfo` global is not called by the 12.0.0 FrameXML export. Its Lua API name is present in the installed Forever `WowB.exe`, and Everlook's existing drop collector already uses it. The [API reference](https://warcraft.wiki.gg/wiki/API_GetLootSourceInfo) documents alternating source GUID and quantity returns, including Item GUIDs for containers. Missing, secret or mismatched source GUIDs leave loot manual. The GUID correspondence still needs a client check; mocks do not establish it. Polling never claims a loot window, and an empty visible loot window also blocks another container use.

## Tracker font object types

The tracker font guard accepts both Lua tables and native userdata exposing `GetFont`, matching the Fonts module's handling of Font objects. A table-only guard silently skipped the tracker before `SetTextSize` could run. The regression fixture uses userdata and checks enabling, sliders, late initialization, layout refresh and combat restoration.

`Blizzard_ObjectiveTrackerShared.xml` makes each line's Text and Dash inherit `ObjectiveTrackerLineFont`; tracker headers use `ObjectiveTrackerHeaderFont`. `Blizzard_ObjectiveTrackerManager.lua:SetTextSize` selects the shared fonts' parents and updates the tracker. The fonts module therefore changes the underlying named fonts and leaves those two shared fonts and their text regions inheriting them. Calling `SetFont` directly on an existing text region pins its size and prevents this propagation. The paired-module regression checks the fonts module at offset 0 with the tracker at size 18, matching the reported saved preferences.

## Font families and alphabets

Every game font in `Blizzard_Fonts_Shared` is a `FontFamily` with five members: `roman`, `russian`, `korean`, `simplifiedchinese` and `traditionalchinese`. `ChatFontNormal` inherits `NumberFont_Shadow_Med`, whose roman member is `ARIALN.TTF`, Korean `2002.TTF` and simplified Chinese `ARHei.ttf` (`Mainline/Fonts.xml`). Names in the world have one global per alphabet in `GameFontStyles.xml`: `UNIT_NAME_FONT_ROMAN`, `_CYRILLIC`, `_KOREAN` and `_CHINESE`. `NAMEPLATE_FONT` holds the name of a font object (`GameFontWhite`), not a file, so the Fonts module leaves it alone.

`SetFont` on a font from a family replaces only the member for the client's own alphabet and keeps the others. The 12.0.0 source does not say this. The evidence is ls_Glass: its message font showed squares for other scripts until it called `CopyFontObject(ChatFontNormal)` before `SetFont` (commit "Add workaround for squares instead of characters"). ElvUI's `GenerateFontMembers` keeps the game's Korean and Chinese members, and Chattynator and ls_Glass replace only the member for the client's own alphabet. How the client renders one line that mixes alphabets is still unchecked.

Chat windows are Lua frames. `ScrollingMessageFrameMixin` comes from `FontableFrameMixin`, whose `SetFont` copies the current font object into `CreateFont(tostring(self))` and changes the copy. That copy is a global, so a walk over `_G` finds it. Message lines are font strings in `FontStringContainer` that follow the window's font object. `ChatFrameMixin:OnLoad` sets `ChatFontNormal`, and `UPDATE_CHAT_WINDOWS` and `FCF_SetChatWindowFontSize` call `SetFont` with the file from `GetFont()` and the tab's size, so a window keeps whatever file it was last given. `CHAT_FRAMES` lists every window, temporary ones included.

Nameplate names inherit `SystemFont_NamePlate` or `SystemFont_NamePlate_Outlined` (`Blizzard_NamePlates`). Unit frame names inherit `GameFontNormalSmall`: `PlayerName`, `PetName`, `TargetFrame.TargetFrameContent.TargetFrameContentMain.Name` (the focus frame uses the same template), `totFrame.Name`, and each party member's `Name` and `PetFrame.Name`. Party members come from `PartyFrame.PartyMemberFramePool` in `InitializePartyMemberFrames`. Raid-style frames inherit `GameFontHighlightSmall`, and `DefaultCompactUnitFrameSetup` scales the name with `SetFont` on the file `GetFont()` returns, from a size cached on the first setup.
