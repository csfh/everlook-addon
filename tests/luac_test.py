"""Checks on the compiled shape of every shipped Lua file.

Lua 5.1 allows 200 locals in a chunk and 60 upvalues in a function, and a file that
goes over fails to load in the game while the tests of other files still pass. This
fails first, with margin. It also lists every global a file writes and fails on one
that is not declared: a SavedVariables name, a key binding label or handler, an XML
mixin, a slash command, or the few names allowed below. A forgotten `local` shows up
here instead of leaking into another addon.
"""
import os
import re
import subprocess
import unittest
from pathlib import Path

ADDON = Path(__file__).resolve().parents[1]
LUAC = "luac5.1"
MAIN_LOCALS_MAX = 180
UPVALUES_MAX = 55
ALLOWED_PREFIXES = ("SLASH_EVERLOOK", "BINDING_HEADER_EVERLOOK", "BINDING_NAME_EVERLOOK")
# Everlook_Data is the data addon's one table, which its generated chunk files call into.
ALLOWED_NAMES = {"SlashCmdList", "Everlook_Data"}


def lua_files():
    for folder in sorted(ADDON.glob("Everlook*")):
        if folder.is_dir():
            yield from sorted(folder.glob("*.lua"))


def declared_globals():
    names = set(ALLOWED_NAMES)
    for toc in ADDON.glob("Everlook*/*.toc"):
        for line in toc.read_text(encoding="utf-8").splitlines():
            match = re.match(r"##\s*SavedVariables(?:PerCharacter)?:\s*(.*)", line)
            if match:
                names.update(name.strip() for name in match.group(1).split(","))
    for bindings in ADDON.glob("Everlook*/Bindings.xml"):
        text = bindings.read_text(encoding="utf-8")
        names.update(re.findall(r"\b([A-Za-z_][A-Za-z_0-9]*)\s*\(", text))
    for xml in ADDON.glob("Everlook*/*.xml"):
        for mixins in re.findall(r'mixin="([^"]*)"', xml.read_text(encoding="utf-8")):
            names.update(name.strip() for name in mixins.split(","))
    return names


def listing(path, deep=False):
    args = [LUAC, "-l", "-p", str(path)] if not deep else [LUAC, "-l", "-l", "-p", str(path)]
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0:
        raise AssertionError(f"{path.relative_to(ADDON)} does not compile: {result.stderr.strip()}")
    return result.stdout


class LuacTest(unittest.TestCase):
    def test_luac_is_installed(self):
        # A missing tool must fail, not skip, so the checks below are never silently off.
        self.assertEqual(subprocess.run([LUAC, "-v"], capture_output=True).returncode, 0, f"{LUAC} is required")

    def test_every_file_compiles_with_room_to_spare(self):
        problems = []
        for path in lua_files():
            text = listing(path, deep=True)
            main = re.search(r"^locals \((\d+)\)", text, re.M)
            if main and int(main.group(1)) > MAIN_LOCALS_MAX:
                problems.append(f"{path.relative_to(ADDON)}: {main.group(1)} locals in the main chunk (max {MAIN_LOCALS_MAX})")
            for count in re.findall(r"^upvalues \((\d+)\)", text, re.M):
                if int(count) > UPVALUES_MAX:
                    problems.append(f"{path.relative_to(ADDON)}: a function has {count} upvalues (max {UPVALUES_MAX})")
        self.assertEqual(problems, [])

    def test_files_write_only_declared_globals(self):
        declared = declared_globals()
        stray = []
        for path in lua_files():
            for name in re.findall(r"SETGLOBAL\s+\S+\s+-?\d+\s*;\s*(\S+)", listing(path)):
                if name in declared or name.startswith(ALLOWED_PREFIXES):
                    continue
                stray.append(f"{path.relative_to(ADDON)}: {name}")
        self.assertEqual(sorted(set(stray)), [])


if __name__ == "__main__":
    unittest.main()
