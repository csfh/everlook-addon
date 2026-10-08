# Everlook notes

These pages are for people working on this addon. The game does not load this folder. Leave every file here out of the TOCs.

Everlook gathers world data for https://everlook.ing. The site is a database in the same family as Wowhead and Thottbot.

Collectors write rows through `Everlook.world`. The addon saves them as `EverlookDB.world`, one compressed document. The desktop app uploads the SavedVariables file. The collectors cover creatures, items, drops, kills, quests, objects, vendors, spells, factions, recipes, flight points, and fishing.

This addon shows an Everlook logo button on the minimap.

The main addon lives in `Everlook`. Each optional module is its own addon in `Everlook_<Name>` that depends on it. [Quality of life](qol.md) says how a module registers.

## Pages

- [API layers](api-layers.md)
- [EventUtil](event-util.md)
- [Minimap button](minimap.md)
- [Mainline notes](mainline-notes.md)
- [Quality of life](qol.md)
- [Smart Island plan](smart-island-plan.md)
- [Smart Island notification API](smart-island-notifications.md)
- [SavedVariables](saved-variables.md)
