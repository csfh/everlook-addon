# Minimap button

`minimap.lua` creates `EverlookMinimapButton` after `ADDON_LOADED`. The icon is `Interface\AddOns\Everlook\assets\logo.tga`.

## Shape and position

The button is the stock minimap-button layout: 31px, a 53px border anchored to `TOPLEFT`, and a 20px icon at `TOPLEFT` 7, -5. It sits on the minimap ring and left-drag moves it. The saved angle is `EverlookDB.minimap.angle`. The starting angle is 160.

The textures are:

- `Interface\Minimap\MiniMap-TrackingBorder`
- `Interface\Minimap\UI-Minimap-Background`
- `Interface\Minimap\UI-Minimap-ZoomButton-Highlight`

Hovering the button shows Everlook, the signing status, the session and total row counts, and a hint. Clicking it with either mouse button opens the Everlook settings page with `Settings.OpenToCategory`, or closes the settings window when that page is already showing. `/everlook` does the same and takes no arguments. They are the only two entry points besides Esc, Options, AddOns, Everlook.

The Everlook page uses `Settings.RegisterVerticalLayoutCategory`. It shows the signing status and an Eager scan button, which runs one pass over bags, worn gear, the spellbook, talents, currencies, professions, nearby units, factions, and quest lines, then stops. Everyday recording stays lazy. The module options are on subpages in the list on the left, made with `Settings.RegisterVerticalLayoutSubcategory`: Quests, Vendors, Loot and mail, Social, Chat, Tooltips, Map, Interface, Smart island, and Radial menu, each with native section headings, checkboxes, and sliders. Collected data is the canvas subpage, made with `Settings.RegisterCanvasLayoutSubcategory`. The settings window parents the browser frame, and it shows the bucket and record lists. The left side shows each bucket that has rows. The right side shows the records of one page of the bucket you pick, since a large collection is saved in pages and never read whole. The arrows move between pages, and a label says which ids the page covers. A number typed in the search box jumps to the page that holds that id. Text narrows the rows of the page you are on, and Enter looks for it in every page, a few at a time, showing matches as they turn up and stopping at 500 or when the page is hidden. A record shows its name, or its id when the row has no name. Drops and other joined rows use collected creature and item names. Clicking the icon or `/everlook` while any of these pages is showing closes the settings window.
