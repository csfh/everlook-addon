# API layers

Blizzard exposes four layers to addon code. `EventUtil` and `Settings` sit in the third one. They are Lua helpers Blizzard wrote so the default UI, and addons, can skip repeated setup.

## Engine API

C code. This is the game.

`C_AddOns`, `C_Item`, `C_Spell`, `C_Timer`, and `CreateFrame` live here. A lot of old globals (`GetItemInfo`, `GetSpellInfo`, `IsAddOnLoaded`) moved into a `C_` namespace on the modern client Forever is built from. Call the namespaced function.

## Widget methods

Engine methods on UI objects.

`frame:RegisterEvent`, `frame:SetScript`, and `frame:SetPoint` are this layer. `EventUtil` calls the same machinery through `EventRegistry` so a file does not have to own a frame just to hear one event.

## FrameXML helpers

Lua in SharedXML, loaded before any addon, left in the global environment.

`EventUtil`, `EventRegistry`, `Settings`, `Mixin`, `CreateFromMixins`, and `CopyTable` are this layer. Everlook waits with `EventUtil.ContinueOnAddOnLoaded`. Each file keeps one job.

`Mixin` and `CreateFromMixins` build objects by copying methods onto a table. Everlook uses a file and a function.

## XML templates

Premade widgets.

The minimap button is a plain `Button` built in Lua. See [Minimap button](minimap.md).

## Sources

- [FrameXML functions](https://warcraft.wiki.gg/wiki/FrameXML_functions)
- [Blizzard settings implementation guide](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua)
