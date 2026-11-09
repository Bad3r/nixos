# Copyright (c) 2026 Bad3r
"""packages/camoufox/update.py against a mocked GitHub release list and PyPI."""

import contextlib
import importlib.util
import io
import json
import shutil
import sys
import tarfile
import tempfile
import unittest
import unittest.mock
from pathlib import Path
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from types import ModuleType

SOURCE = Path(sys.argv.pop(1) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2])
FILES = [
    "packages/camoufox/update.py",
    "packages/camoufox/default.nix",
    "scripts/updater_bootstrap.py",
]
DIGEST = "ab" * 32
PINNED = {
    "version": "158.0.1-beta.41",
    "srcHash": "sha256-old",
    "libraryVersion": "0.5.9",
    "libraryHash": "sha256-old",
    "fpgenVersion": "1.3.0",
    "fpgenHash": "sha256-old",
    "modelUrl": "https://github.com/scrapfly/fingerprint-generator/releases/download/m/x.zip",
    "modelHash": "sha256-old",
}


def release(version: str) -> dict[str, Any]:
    """A GitHub release of the browser with its Linux asset."""
    name = f"camoufox-{version}-lin.x86_64.zip"
    return {
        "tag_name": f"v{version}",
        "draft": False,
        "prerelease": False,
        "assets": [{"name": name, "digest": f"sha256:{DIGEST}"}],
    }


def sdist(version: str, browser: str) -> bytes:
    """A launcher sdist naming its browser and model."""
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w:gz") as archive:
        for name, data in (
            ("browser-pin.json", {"tag": f"v{browser}"}),
            ("fpgen-model.json", {"url": PINNED["modelUrl"], "sha256": DIGEST}),
        ):
            raw = json.dumps(data).encode()
            info = tarfile.TarInfo(f"camoufox-{version}/src/camoufox/{name}")
            info.size = len(raw)
            archive.addfile(info, io.BytesIO(raw))
    return buffer.getvalue()


class UpdateTest(unittest.TestCase):
    """One updater run per case, in a copy of the checkout's updater files."""

    def setUp(self) -> None:
        """Copy the updater and its library into a fresh checkout with the pinned hashes."""
        self.root = Path(tempfile.mkdtemp(prefix="camoufox-update-"))
        self.addCleanup(shutil.rmtree, self.root)
        (self.root / "flake.nix").write_text("")
        for name in FILES:
            (self.root / name).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(SOURCE / name, self.root / name)
        shutil.copytree(SOURCE / "scripts/updater", self.root / "scripts/updater")
        self.hashes = self.root / "packages/camoufox/hashes.json"
        self.hashes.write_text(json.dumps(PINNED))
        self.downloads: list[str] = []

    def load(self) -> ModuleType:
        """Import the copied update.py as a fresh module."""
        path = self.root / "packages/camoufox/update.py"
        spec = importlib.util.spec_from_file_location(f"camoufox_update_{id(self)}", path)
        if spec is None or spec.loader is None:
            self.fail("update.py did not load")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def run_update(self, browsers: list[str], launchers: dict[str, str]) -> str:
        """Run main() with these browser releases and launcher versions -> paired browser."""
        module = self.load()
        tarballs = {f"https://pypi.invalid/{v}": sdist(v, b) for v, b in launchers.items()}

        def fetch_json(url: str) -> Any:  # noqa: ANN401
            if "api.github.com" in url:
                return [release(v) for v in browsers]
            if url.endswith("/camoufox/json"):
                return {
                    "releases": {
                        v: [
                            {
                                "packagetype": "sdist",
                                "url": f"https://pypi.invalid/{v}",
                                "digests": {"sha256": DIGEST},
                            }
                        ]
                        for v in launchers
                    }
                }
            if url.endswith("/fpgen/json"):
                return {
                    "releases": {"1.4.0": [{"packagetype": "sdist", "digests": {"sha256": DIGEST}}]}
                }
            raise AssertionError(url)

        def urlopen(url: str, timeout: float) -> io.BytesIO:  # noqa: ARG001
            self.downloads.append(url.rsplit("/", 1)[1])
            return io.BytesIO(tarballs[url])

        out = io.StringIO()
        with (
            unittest.mock.patch.object(module, "fetch_json", fetch_json),
            unittest.mock.patch.object(module.urllib.request, "urlopen", urlopen),
            unittest.mock.patch.object(sys, "argv", ["update.py"]),
            contextlib.redirect_stdout(out),
        ):
            module.main()
        return out.getvalue()

    def test_browser_without_a_launcher_yet_is_skipped(self) -> None:
        """A browser release no launcher names yet keeps the pins and exits normally."""
        out = self.run_update(["159.0-beta.1"], {"0.5.9": "158.0.1-beta.41", "0.5.8": "157"})
        self.assertIn("No camoufox launcher on PyPI pairs with browser 159.0-beta.1 yet", out)
        self.assertEqual(json.loads(self.hashes.read_text()), PINNED)
        self.assertEqual(self.downloads, ["0.5.9"])

    def test_paired_launcher_moves_every_pin(self) -> None:
        """The newest launcher naming the browser is taken with its model."""
        out = self.run_update(
            ["159.0-beta.1"], {"0.6.0": "159.0-beta.1", "0.5.9": "158.0.1-beta.41"}
        )
        self.assertIn("Updated", out)
        pins = json.loads(self.hashes.read_text())
        self.assertEqual(
            (pins["version"], pins["libraryVersion"], pins["fpgenVersion"]),
            ("159.0-beta.1", "0.6.0", "1.4.0"),
        )
        self.assertEqual(self.downloads, ["0.6.0"])


if __name__ == "__main__":
    unittest.main()
