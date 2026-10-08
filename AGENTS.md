This is a World of Warcraft AddOn for the Everlook application https://everlook.ing.

Everlook gathers world data for that application. The gathered rows are written to `EverlookDB.world`.

The minimap button is `EverlookMinimapButton`. It shows `assets/logo.tga`.

Lua 5.1 only. No Ace, LibStub, or embeds. Each folder here named `Everlook` or `Everlook_<Name>` is one addon the game loads, and its TOC order is its wiring. `Everlook` is the main addon. It collects and signs the world data and holds the module registry, the settings page, Collected data and the minimap button. Every other folder is a module addon that depends on it, grouped under Everlook in the addon list. Core files take the namespace from `local _, Everlook = ...`, and `world.lua` shares it as the global `Everlook`. A module addon's files start with `local addon_name = ...` and `local Everlook = Everlook`.

Optional modules register with `Everlook.module.register` from `Everlook/module.lua`, and each defaults to disabled. Settings live in `EverlookDB.qol`, outside `EverlookDB.world`. `Everlook/settings.lua` builds the native Everlook Settings page at login, after every module addon has registered. Its subpages in the left list come from the page list in `module.lua` (Quests, Vendors, Loot and mail, Social, Chat, Tooltips, Map, Interface, Smart island, Radial menu) and Collected data, which hosts the data browser as a canvas page. A module names its page and its place on it. See `wiki/qol.md`. The bundled Expressway and Manrope fonts keep their licences in `Everlook_Fonts/assets/`, and `fonts.txt` there says where each came from.

## Direction

Everlook works like Leatrix Plus. It tweaks, hides or automates something the default UI already does, behind an option the player turns on. It never replaces a Blizzard frame or builds a rival UI. An earlier attempt at replacement action bars and unit frames was removed after it proved too costly to get right. The lessons from it are in `wiki/mainline-notes.md`.

## Entry points

The minimap icon and `/everlook` are the only ways in, and both toggle the Everlook settings page. Any new feature gets a control on that page. Slash commands and menus beyond those two are out. The radial menu keybinding is the click binding `CLICK EverlookRadialButton:LeftButton` in `Everlook_RadialMenu/Bindings.xml`. The island's two bindings are in `Everlook_Island/Bindings.xml`. The smart island uses `EVERLOOK_SMART_ISLAND` with `runOnUp` to handle holding and releasing its key. The player sets the radial key on the Radial menu page and the island key on the Smart island page, or under Key Bindings. `EVERLOOK_SMART_ISLAND_DISMISS` dismisses the newest island toast, the keyboard route to its right-click dismiss. Another keybinding needs the same kind of reason.

## The client

Forever is built on Mainline, the retail client. The reference is `Gethe/wow-ui-source` at tag `12.0.0`, in the `Mainline` and `Shared` folders. Before using a frame name, event, function or constant, find it there. `wiki/mainline-notes.md` says how to read that source and records what we have already checked.

## Rules for modules

- A module is its own addon in `Everlook_<Name>`, where the name is its module id in CamelCase. Its TOC has the core's `## Interface`, `## Notes`, and a `## Title` of `Everlook` and the folder's name after the underscore, such as `Everlook AutoRepair`. "Everlook" is in gold (`|cffffd100`). The name after it is in blue (`|cff66bbff`) for a module, or in the island's accent (`|cffad76ef`) for `Everlook_Island` and its `Everlook_Island<Name>` modules. The TOC also has `## Dependencies: Everlook` and `## Group: Everlook`. It has no `## Version`, because pack stamps the core's, and no `## SavedVariables`, because settings live in `EverlookDB`. `tests/scripts_test.py` checks those fields. The module calls `Everlook.module.register` with `addon = addon_name`, a `page` and an `order`, and starts disabled. Add its file to the list in `tests/qol.lua` and give it a row in `wiki/qol.md`.
- Something that adds to another module, such as an island feed, is an extension. It lives in its own addon that also depends on the host's addon, so an island module has `## Dependencies: Everlook, Everlook_Island`, and it calls `Everlook.module.extend`. Its options are saved under the host. The Smart island calls `refresh(force)` and `follow(signal, snapshot, ...)` on its extensions, and an option's `presets` field sets it under each island preset.
- A module that acts for the player checks `Everlook.module.paused()`, so holding Shift pauses it. Work that a protected frame blocks waits until combat ends.
- Turning an option or the whole module off puts back what it changed, and only that.
- Hook in a way that can be undone. Unregister a frame's own events and register them again, or hook its `OnShow`. Reparenting or replacing Blizzard frames is off the table.
- Fail closed. When an API that an automation depends on is missing, the automation does nothing. A guard written as `fn and fn()` fails open, so it cannot protect anything that spends, sells, deletes or accepts.
- Health, power, names, ids and chat text can be secret values in combat and restricted content. Hand them straight to a status bar or `SetText`. Comparing them or doing arithmetic on them raises an error, and an id needs an `issecretvalue` check before it goes into text.
- Tests mock only names that appear in Blizzard's own code. A mock of a function the game lacks lets broken code pass. Write the failing test first. The tests check module logic and nothing about how the game behaves, so a change stays unverified until someone has run it in the game.
- Commit one module at a time as `feat(addon): ...`, so any one of them can be reverted alone. A push to `main` cuts an addon release unless every commit is `docs`, `test`, `chore`, `ci`, `style` or `build`, so wait to be asked before pushing.

