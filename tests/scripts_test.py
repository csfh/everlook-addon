import hashlib
import hmac
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile
import unittest


ADDON = Path(__file__).resolve().parents[1]


class AddonScriptsTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="everlook-scripts-")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.addon = self.base / "repo with spaces" / "addon"
        self.core = self.addon / "Everlook"
        (self.addon / "scripts").mkdir(parents=True)
        self.core.mkdir()
        self.addons = self.base / "game with spaces" / "AddOns"
        self.destination = self.addons / "Everlook"
        self.template = (ADDON / "Everlook" / "sign_template.lua").read_text()
        (self.core / "sign_template.lua").write_text(self.template)
        (self.core / "Everlook.toc").write_text("## Interface: 16001\n## Title: Everlook\n## Version: 0.1.0\n")
        (self.core / "world.lua").write_text("local _, Everlook = ...\n")
        (self.addon / "LICENSE").write_text("MIT License\n")
        self.module = self.addon / "Everlook_SellJunk"
        self.module.mkdir()
        (self.module / "Everlook_SellJunk.toc").write_text(
            "## Interface: 16001\n## Title: Sell junk\n## Dependencies: Everlook\n\nsell_junk.lua\n")
        (self.module / "sell_junk.lua").write_text("local addon_name = ...\n")
        for name in ("sync.sh", "pack.sh"):
            shutil.copyfile(ADDON / "scripts" / name, self.addon / "scripts" / name)
        script = self.addon / "scripts" / "sync.sh"
        script.write_text(re.sub(r'^addons=.*$', f'addons="{self.addons}"', script.read_text(), flags=re.MULTILINE))

    def sync(self, succeeds=True):
        result = subprocess.run(
            ["bash", str(self.addon / "scripts" / "sync.sh")],
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode == 0, succeeds, result.stderr)

    def pack(self, output, version="0.1.0"):
        environment = {**os.environ, "UV_CACHE_DIR": str(self.base / "uv-cache"), "UV_PYTHON": sys.executable}
        result = subprocess.run(
            ["bash", str(self.addon / "scripts" / "pack.sh"), version, str(output)],
            capture_output=True, text=True, env=environment,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return tarfile.open(output / f"Everlook-{version}.tar.gz")

    def test_creates_stub_and_symlink(self):
        self.sync()
        self.assertTrue(self.destination.is_symlink())
        self.assertEqual(self.destination.resolve(), self.core)
        self.assertEqual((self.core / "sign.lua").read_text(), self.template)
        self.assertEqual((self.core / "sign.lua").stat().st_mode & 0o777, 0o600)

    def test_links_every_module_folder(self):
        self.sync()
        linked = self.addons / "Everlook_SellJunk"
        self.assertTrue(linked.is_symlink())
        self.assertEqual(linked.resolve(), self.module)

    def test_backs_up_a_real_module_folder(self):
        (self.addons / "Everlook_SellJunk").mkdir(parents=True)
        (self.addons / "Everlook_SellJunk" / "old.lua").write_text("old")
        self.sync()
        backups = list(self.addons.glob("Everlook_SellJunk.backup.*/Everlook_SellJunk"))
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / "old.lua").read_text(), "old")
        self.assertTrue((self.addons / "Everlook_SellJunk").is_symlink())

    def test_removes_a_link_whose_module_folder_is_gone(self):
        self.sync()
        dropped = self.addon / "Everlook_Dropped"
        dropped.mkdir()
        (dropped / "Everlook_Dropped.toc").write_text("## Interface: 16001\n")
        self.sync()
        shutil.rmtree(dropped)
        self.sync()
        self.assertFalse(os.path.lexists(self.addons / "Everlook_Dropped"))
        self.assertTrue((self.addons / "Everlook_SellJunk").is_symlink())

    def test_moves_the_token_from_before_the_split(self):
        token = "Everlook.config.token = 'legacy-test-token'\n"
        (self.addon / "sign.lua").write_text(token)
        self.sync()
        self.assertFalse((self.addon / "sign.lua").exists())
        self.assertEqual((self.core / "sign.lua").read_text(), token)

    def test_preserves_local_token_on_repeated_sync(self):
        self.sync()
        token = "Everlook.config.token = 'local-test-token'\n"
        (self.core / "sign.lua").write_text(token)
        self.sync()
        self.assertEqual((self.core / "sign.lua").read_text(), token)

    def test_carries_installed_token_when_local_file_is_missing(self):
        self.destination.mkdir(parents=True)
        token = "Everlook.config.token = 'installed-test-token'\n"
        (self.destination / "sign.lua").write_text(token)
        self.sync()
        self.assertEqual((self.core / "sign.lua").read_text(), token)
        backups = list(self.addons.glob("Everlook.backup.*/Everlook"))
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / "sign.lua").read_text(), token)

    def test_keeps_local_token_over_an_installed_token(self):
        self.destination.mkdir(parents=True)
        (self.destination / "sign.lua").write_text("Everlook.config.token = 'older'\n")
        (self.core / "sign.lua").write_text("Everlook.config.token = 'current'\n")
        self.sync()
        self.assertEqual((self.core / "sign.lua").read_text(), "Everlook.config.token = 'current'\n")

    def test_refuses_a_local_sign_file_symlink(self):
        outside = self.base / "protected.lua"
        outside.write_text("protected")
        (self.core / "sign.lua").symlink_to(outside)
        self.sync(succeeds=False)
        self.assertEqual(outside.read_text(), "protected")
        self.assertFalse(self.destination.exists())

    def test_release_uses_clean_template_with_or_without_local_token(self):
        for local in (False, True):
            with self.subTest(local_token=local):
                if local:
                    (self.core / "sign.lua").write_text("Everlook.config.token = 'never-package-me'\n")
                with self.pack(self.base / f"release-{local}") as archive:
                    self.assertNotIn("Everlook/sign_template.lua", archive.getnames())
                    stub = archive.extractfile("Everlook/sign.lua")
                    self.assertIsNotNone(stub)
                    self.assertEqual(stub.read().decode(), self.template)
                    for member in archive.getmembers():
                        if member.isfile():
                            self.assertNotIn(b"never-package-me", archive.extractfile(member).read())

    def test_release_carries_the_license_inside_the_core_folder(self):
        with self.pack(self.base / "licensed") as archive:
            self.assertEqual(archive.extractfile("Everlook/LICENSE").read().decode(), "MIT License\n")
            self.assertNotIn("LICENSE", archive.getnames())

    def test_pack_refuses_to_run_without_a_license(self):
        (self.addon / "LICENSE").unlink()
        result = subprocess.run(
            ["bash", str(self.addon / "scripts" / "pack.sh"), "0.1.0", str(self.base / "unlicensed")],
            capture_output=True, text=True,
            env={**os.environ, "UV_CACHE_DIR": str(self.base / "uv-cache"), "UV_PYTHON": sys.executable},
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing LICENSE", result.stderr)

    def test_release_ships_every_folder_with_the_core_version(self):
        with self.pack(self.base / "release", version="2.3.4") as archive:
            names = archive.getnames()
            self.assertIn("Everlook/world.lua", names)
            self.assertIn("Everlook_SellJunk/sell_junk.lua", names)
            toc = archive.extractfile("Everlook_SellJunk/Everlook_SellJunk.toc").read().decode()
        self.assertEqual(toc.count("## Version:"), 1)
        self.assertIn("## Interface: 16001\n## Version: 2.3.4\n", toc)
        self.assertNotIn("## Version", (self.module / "Everlook_SellJunk.toc").read_text())

    def test_release_also_ships_a_zip_with_the_same_folders(self):
        output = self.base / "release-zip"
        self.pack(output, version="2.3.4").close()
        for name in ("Everlook-2.3.4.zip", "Everlook-latest.zip"):
            with zipfile.ZipFile(output / name) as archive:
                names = archive.namelist()
                self.assertIn("Everlook/Everlook.toc", names)
                self.assertIn("Everlook/world.lua", names)
                self.assertIn("Everlook/LICENSE", names)
                self.assertIn("Everlook_SellJunk/sell_junk.lua", names)
                # Windows Explorer needs forward slashes and no leading folder above the addons.
                self.assertTrue(all("\\" not in entry and not entry.startswith("/") for entry in names))
                toc = archive.read("Everlook_SellJunk/Everlook_SellJunk.toc").decode()
            self.assertIn("## Version: 2.3.4", toc)
        self.assertEqual((output / "Everlook-2.3.4.zip").read_bytes(), (output / "Everlook-latest.zip").read_bytes())


class LayoutTest(unittest.TestCase):
    """Each folder in addon/ named Everlook or Everlook_<Name> is one addon the game loads."""

    @staticmethod
    def fields(toc):
        fields, files = {}, []
        for line in toc.read_text().splitlines():
            if line.startswith("## "):
                key, _, value = line[3:].partition(":")
                fields[key.strip()] = value.strip()
            elif line.strip() and not line.startswith("#"):
                files.append(line.strip())
        return fields, files

    def folders(self):
        return sorted(path for path in ADDON.iterdir() if path.is_dir() and re.fullmatch(r"Everlook(_[A-Za-z0-9]+)?", path.name))

    def test_every_listed_file_exists_and_every_file_is_listed(self):
        for folder in self.folders():
            with self.subTest(addon=folder.name):
                toc = folder / f"{folder.name}.toc"
                self.assertTrue(toc.is_file(), f"{folder.name} needs {toc.name}")
                _, files = self.fields(toc)
                for name in files:
                    path = name.replace("\\", "/")
                    if folder.name == "Everlook" and path == "sign.lua":
                        continue
                    self.assertTrue((folder / path).is_file(), f"{folder.name}.toc lists missing {name}")
                listed = {name.replace("\\", "/") for name in files}
                for path in folder.rglob("*"):
                    relative = path.relative_to(folder).as_posix()
                    if path.suffix in (".lua", ".xml") and path.name != "Bindings.xml" and not relative.startswith("sign"):
                        self.assertIn(relative, listed, f"{folder.name}.toc does not load {relative}")

    # The addon list shows these titles. "Everlook" is in the gold of the game's
    # own titles, and the folder's name after it is colored by kind: the island
    # and its modules in the island's accent, every other module in blue.
    GOLD, MODULE, ISLAND = "ffd100", "66bbff", "ad76ef"

    @staticmethod
    def is_island(name):
        return name.startswith("Island")

    def test_titles_name_the_folder_and_color_its_kind(self):
        prefix = f"|cff{self.GOLD}Everlook|r"
        for folder in self.folders():
            with self.subTest(addon=folder.name):
                fields, _ = self.fields(folder / f"{folder.name}.toc")
                if folder.name == "Everlook":
                    self.assertEqual(fields.get("Title"), prefix)
                    continue
                name = folder.name.removeprefix("Everlook_")
                color = self.ISLAND if self.is_island(name) else self.MODULE
                self.assertEqual(fields.get("Title"), f"{prefix} |cff{color}{name}|r")

    def test_modules_depend_on_everlook_and_sit_in_its_group(self):
        core, _ = self.fields(ADDON / "Everlook" / "Everlook.toc")
        names = {folder.name for folder in self.folders()}
        for folder in self.folders():
            if folder.name == "Everlook":
                continue
            with self.subTest(addon=folder.name):
                fields, _ = self.fields(folder / f"{folder.name}.toc")
                name = folder.name.removeprefix("Everlook_")
                island_module = self.is_island(name) and name != "Island"
                dependencies = [part.strip() for part in fields.get("Dependencies", "").split(",")]
                self.assertEqual(dependencies, ["Everlook", "Everlook_Island"] if island_module else ["Everlook"])
                for dependency in dependencies:
                    self.assertIn(dependency, names)
                self.assertEqual(fields.get("Interface"), core["Interface"])
                self.assertEqual(fields.get("Group"), "Everlook")
                self.assertTrue(fields.get("Notes"))
                self.assertNotIn("Version", fields, "pack.sh stamps the version")
                self.assertNotIn("SavedVariables", fields, "settings live in EverlookDB")


class HashCompatibilityTest(unittest.TestCase):
    def test_matches_standard_hashing_at_padding_and_key_boundaries(self):
        lengths = [0, 1, 31, 55, 56, 63, 64, 65, 119, 120, 127, 128, 129, 1024]
        for index, length in enumerate(lengths):
            with self.subTest(length=length):
                message = bytes((byte * 37 + 11) % 256 for byte in range(length))
                key = bytes((byte * 17 + 193) % 256 for byte in range([0, 1, 64, 65, 131][index % 5]))
                def literal(data):
                    return '"' + ''.join(f"\\{byte:03d}" for byte in data) + '"'
                script = (
                    'local addon = {}\n'
                    'assert(loadfile(arg[1]))("Everlook", addon)\n'
                    f'print(addon.hash.sha256({literal(message)}))\n'
                    f'print(addon.hash.hmac_sha256({literal(key)}, {literal(message)}))\n'
                )
                result = subprocess.run(
                    ["lua5.1", "-", str(ADDON / "Everlook" / "hash.lua")], input=script,
                    capture_output=True, text=True,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.splitlines(), [
                    hashlib.sha256(message).hexdigest(),
                    hmac.new(key, message, hashlib.sha256).hexdigest(),
                ])


if __name__ == "__main__":
    unittest.main()
