# Nameplates

The nameplate view gives every kind of plate one layout by working on the game's own plate. It never replaces one:
the game's health bar, cast bar, auras, threat colour and click area stay the game's. This page is for addons that
want a place on a plate.

## Kinds

A plate is one of these, told apart from what the plate says about itself (`IsShowOnlyName`, `IsSimplified`,
`IsFriend`, `IsPlayer`, widgets only, forbidden) and, where it does not say, from the unit.

| Kind | What the view does |
| --- | --- |
| `enemy_npc`, `enemy_player`, `friendly_npc`, `friendly_player` | Names left-aligned, a lead mark across both rows, a subtitle under the health bar. |
| `name_only` | A friendly player shown with only a name. Name left-aligned, a one-row lead mark, a subtitle under the name. |
| `simplified`, `widgets_only`, `forbidden`, `personal` | Left exactly as the game made them. |

The first six come from what the client's plates were seen to hold. The last four are drawn from Blizzard's own code
and have not been seen in the client.

## Providers

```lua
Everlook.nameplates.provide({
    source = "my_addon",           -- required, 1 to 64 characters; providing again with the same source replaces it
    order = 10,                    -- lower is asked first, default 100
    kinds = { "friendly_npc" },    -- optional; the default is every kind the view works on
    lead = function(unit, kind)    -- optional
        return { atlas = "...", file = "Interface\\...", tint = { 1, 1, 1 } }
    end,
    subtitle = function(unit, kind)  -- optional
        return { text = "<Gryphon Master>", color = { 0.1, 1, 0.1 } }
    end,
})
Everlook.nameplates.remove("my_addon")
Everlook.nameplates.refresh()      -- ask again, a moment after the last call
```

Each place goes to the first provider, in order, that answers with a table. A function that fails is skipped and the
failure kept in `Everlook.nameplates.last_error`. A provider is refused with `nil` and a reason: `invalid_spec`,
`invalid_source`, `invalid_order`, `invalid_lead`, `invalid_subtitle` or `invalid_kinds`.

Providers are asked when a plate is added, when `refresh` is called, and when an option changes. They are not asked
when the game lays a plate out again, which can be every frame.

`Everlook.nameplates.kind_of(plate)` returns the kind, or nil when the plate does not say and the unit cannot.
