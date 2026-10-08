# EventUtil

`EventUtil` waits for a game event and then runs a callback. The 12.0.0 source is `Interface/AddOns/Blizzard_SharedXML/EventUtil.lua`. Forever tracks that modern UI.

`minimap.lua` uses the addon-load helper:

```lua
local addonName = ...

EventUtil.ContinueOnAddOnLoaded(addonName, function()
	EverlookDB = EverlookDB or {}
end)
```

`ADDON_LOADED` fires after that addon's files have run and after its SavedVariables have been handed to Lua. The callback is the first safe place to read `EverlookDB`.

If the addon is already loaded, the helper runs the callback immediately. Otherwise it listens once:

```lua
function EventUtil.ContinueOnAddOnLoaded(addOnName, callback)
	local isLoadedOrLoading, isLoaded = C_AddOns.IsAddOnLoaded(addOnName)
	if isLoaded then
		callback()
		return
	end

	EventUtil.RegisterOnceFrameEventAndCallback("ADDON_LOADED", callback, addOnName)
end
```

The extra arguments to `RegisterOnceFrameEventAndCallback` must match the event payload. For `ADDON_LOADED` the payload is the addon name, so the callback runs for Everlook and then the handle unregisters.

## Other helpers in the same file

| Function | When the callback runs |
|---|---|
| `ContinueOnAddOnLoaded(addOnName, callback)` | That addon's `ADDON_LOADED`, or immediately if it is already loaded. |
| `ContinueOnPlayerLogin(callback)` | `PLAYER_LOGIN`, or immediately if `IsLoggedIn()` is already true. |
| `ContinueOnVariablesLoaded(callback)` | Blizzard UI variables are loaded. This is the glue and UI parent, not an addon's SavedVariables. |
| `ContinueAfterAllEvents(callback, ...)` | After every named event has fired once. Unknown event names assert through `C_EventUtils.IsEventValid`. |
| `RegisterOnceFrameEventAndCallback(event, callback, ...)` | The next time `event` fires with those arguments. |
| `CreateCallbackHandleContainer()` | A table that can drop a group of callback handles in one `Unregister()`. |

## Which wait to use

SavedVariables and the minimap button belong in `ContinueOnAddOnLoaded`.

A collector that needs the player, the map, or a unit should wait for `ContinueOnPlayerLogin`, or register `PLAYER_ENTERING_WORLD` if it must run again each time the player enters the world. `PLAYER_ENTERING_WORLD` also fires on `/reload`.

## Sources

- [EventUtil.lua at 12.0.0](https://github.com/Gethe/wow-ui-source/blob/12.0.0/Interface/AddOns/Blizzard_SharedXML/EventUtil.lua)
- [FrameXML functions](https://warcraft.wiki.gg/wiki/FrameXML_functions)
