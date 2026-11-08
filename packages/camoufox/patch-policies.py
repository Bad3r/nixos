# Copyright (c) 2026 Bad3r
"""Apply the release's uninstall policy to its locked built-in add-on registry."""

import json
import sys
from pathlib import Path
from zipfile import ZipFile


def main() -> None:
    """Reconcile bundled components and the policy without changing profile data."""
    root = Path(sys.argv[1])
    policy_path = root / "distribution/policies.json"
    document = json.loads(policy_path.read_text())
    policies = document["policies"]
    search = policies["SearchEngines"]
    if search["Default"] != "None" or [e["Name"] for e in search["Add"]] != ["None"]:
        msg = "The search policy changed; review the built-in engine before patching"
        raise ValueError(msg)
    with ZipFile(root / "omni.ja") as archive:
        selector = archive.read(
            "moz-src/toolkit/components/search/SearchEngineSelector.sys.mjs"
        ).decode()
    if '"identifier": "none"' not in selector or '"name": "None"' not in selector:
        msg = "The release no longer supplies the inert None engine"
        raise ValueError(msg)

    archive_path = root / "browser/omni.ja"
    manifest_path = "chrome/browser/content/browser/built_in_addons.json"
    uninstall = set(policies["Extensions"]["Uninstall"])
    with ZipFile(archive_path) as archive:
        manifest = json.loads(archive.read(manifest_path))
        removed = {entry["addon_id"] for entry in manifest["builtins"]} & uninstall
        if removed != {
            "webcompat@mozilla.org",
            "pictureinpicture@mozilla.org",
            "formautofill@mozilla.org",
        }:
            msg = f"The release's built-in uninstall targets changed: {sorted(removed)}"
            raise ValueError(msg)
        manifest["builtins"] = [
            entry for entry in manifest["builtins"] if entry["addon_id"] not in uninstall
        ]
        replacement = archive_path.with_suffix(".patched")
        with ZipFile(replacement, "w") as patched:
            for entry in archive.infolist():
                data = (
                    json.dumps(manifest).encode()
                    if entry.filename == manifest_path
                    else archive.read(entry)
                )
                patched.writestr(entry, data)
    replacement.replace(archive_path)

    # On an upgrade, policy startup can still see the previous cached registry.
    policies["Extensions"]["Uninstall"] = [
        addon_id for addon_id in policies["Extensions"]["Uninstall"] if addon_id not in removed
    ]
    # SearchEngineSelector already supplies this engine; adding it again throws.
    del search["Add"]
    policy_path.write_text(json.dumps(document, indent=2) + "\n")


if __name__ == "__main__":
    main()
