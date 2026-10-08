# Everlook addon

A World of Warcraft addon that collects world data for [Everlook](https://everlook.ing), plus a set of optional quality-of-life modules. The core addon (`Everlook`) records what your character sees into `EverlookDB.world` and signs it. Each `Everlook_<Name>` folder is a module addon that depends on the core and starts disabled.

## Install

Use the Everlook desktop app, which installs and updates the addon and places your account's signing token. Or download the archive from https://everlook.ing/download/addon and unpack its folders into `Interface/AddOns`.

## Develop

Link every folder into your game's `AddOns` directory with:

```sh
EVERLOOK_ADDONS_DIR="/path/to/World of Warcraft/<flavor>/Interface/AddOns" bash scripts/sync.sh
```

The script links each `Everlook*` folder. If a real folder is already there, it moves it aside to a backup first. It also creates `Everlook/sign.lua` from `sign_template.lua`. That file holds your account's signing token, is ignored by git, and must never be committed.

Lua 5.1 only. No Ace, LibStub, or embeds. See [AGENTS.md](AGENTS.md) for the rules modules follow, and [wiki](wiki/README.md) for notes on the client API and saved variables.

## Test

```sh
lua5.1 tests/run.lua
python3 tests/scripts_test.py
```

## Package

```sh
bash scripts/pack.sh <version> <output dir>
```

This writes `Everlook-<version>.tar.gz` and `Everlook.json`. It ships `sign_template.lua` as the stub and stamps the core's version into each module's TOC.

## Third-party assets

The bundled fonts keep their own licenses. See `Everlook_Fonts/assets/`.

## License

MIT. See [LICENSE](LICENSE). Copyright (c) 2026 Christoffer Hallas.

If you send a pull request or other contribution, you agree to the [CLA](CLA.md).
