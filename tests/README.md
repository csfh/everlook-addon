# How the addon is tested

Three layers, from cheapest to closest to the game. All of them run before a push that releases the addon (`just prepush addon`).

| Layer | Run with | What it proves |
| --- | --- | --- |
| Lua suite | `lua5.1 tests/run.lua` | Module logic on plain Lua 5.1 with stand-ins for the game's API. Fast; runs in public CI. |
| Script and layout checks | `python3 tests/scripts_test.py`, `python3 tests/luac_test.py`, `cd scripts && python3 -m unittest risky_uses_test` | The packed release (folders, versions, media, checksums, the same bytes twice), that every TOC lists real files, `luac5.1` limits (200 locals, 60 upvalues) and stray globals. Run in public CI. |
| Harness | `just test harness` from the repository root | The real addon files on frames with the game's strata, mouse, clock and animation rules (the private `harness/`). Not in public CI. |

Rules for writing a test (they come from mistakes already made):

- A stand-in widget lists the methods it has and raises on any other. A catch-all that does nothing lets a typo pass.
- Mock only names that appear in Blizzard's own code (wow-ui-source 12.0.0, `Mainline` and `Shared`).
- Write the failing test first, and check that it fails for the reason you think by running it against the old code.
- `run.lua` and `qol.lua` are near Lua's limit of 200 locals in one function: new checks go in a `do ... end` block, or in a file of their own that `run.lua` loads.
- A new module folder is added to `scripts/folders.txt` and to the list in `qol.lua`; `scripts_test.py` unpacks a real release and runs the suite against it.
- A fact about the game that the tests assume belongs in `harness/docs/engine-facts.md`, marked with the build it was checked on.

`tests/world_fixture.lua` writes the golden world document the site's tests read: `just fixture world`.
