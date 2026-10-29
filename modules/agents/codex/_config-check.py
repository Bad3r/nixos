# Copyright (c) 2026 Bad3r

import copy
import os
import subprocess
import sys
import tomllib
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from typing import Any

executable, wrapper = sys.argv[1:]


def launch(directory: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [wrapper, "--strict-config", "app-server", "--stdio"],
        env=dict(os.environ, CODEX_HOME=str(directory)),
        input="",
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )


def read_config(path: Path) -> dict[str, Any]:
    return tomllib.loads(path.read_text())


def require(*, condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


generated = Path.cwd() / "generated"
result = launch(generated)
require(condition=result.returncode == 0, message=result.stderr)
config = read_config(generated / "config.toml")
features = subprocess.run(
    [executable, "features", "list"],
    env=dict(os.environ, CODEX_HOME=str(generated)),
    capture_output=True,
    text=True,
    check=True,
    timeout=30,
)
for line in features.stdout.splitlines():
    name, *stage, enabled = line.split()
    if name in config.get("features", {}):
        require(condition=" ".join(stage) != "removed", message=line)
print("Generated configuration accepted; no configured feature is marked removed.")

fixture = Path.cwd() / "merge"
fixture.mkdir()
base = fixture / "config.base.toml"
managed = fixture / "projects.nix.toml"
projects = fixture / "trusted-projects.toml"
overrides = fixture / "overrides.toml"
output = fixture / "config.toml"
stamp = fixture / "config.merge.sha256"
base.write_text("""model_verbosity = "low"
approvals_reviewer = "user"
[approval_policy.granular]
sandbox_approval = true
rules = true
mcp_elicitations = true
request_permissions = true
skill_approval = true
[projects."/fixture/base"]
trust_level = "trusted"
[projects."/fixture/shared"]
trust_level = "trusted"
""")
expected = read_config(base)


def expect_merge(label: str) -> None:
    result = launch(fixture)
    require(condition=result.returncode == 0, message=f"{label}: {result.stderr}")
    actual = read_config(output)
    require(condition=actual == expected, message=f"{label}: expected {expected!r}, got {actual!r}")


expect_merge("base with optional inputs absent")
managed.write_text("""[projects."/fixture/managed"]
trust_level = "trusted"
[projects."/fixture/shared"]
trust_level = "untrusted"
""")
expected["projects"].update(read_config(managed)["projects"])
expect_merge("managed project layer overrides base")

projects.write_text("""[projects."/fixture/user"]
trust_level = "trusted"
[projects."/fixture/shared"]
trust_level = "trusted"
""")
expected["projects"].update(read_config(projects)["projects"])
expect_merge("mutable project layer overrides managed projects")

overrides.write_text("""approval_policy = "never"
approvals_reviewer = "auto_review"
[projects."/fixture/shared"]
trust_level = "untrusted"
""")
expected["approval_policy"] = "never"
expected["approvals_reviewer"] = "auto_review"
expected["projects"].update(read_config(overrides)["projects"])
expect_merge("settings overrides win and replace a policy table with a scalar")

base.write_text(base.read_text().replace('model_verbosity = "low"', 'model_verbosity = "high"'))
expected["model_verbosity"] = "high"
expect_merge("base change invalidates cache and preserves overrides")

managed.write_text(
    managed.read_text() + '\n[projects."/fixture/managed-added"]\ntrust_level = "trusted"\n'
)
expected["projects"]["/fixture/managed-added"] = {"trust_level": "trusted"}
expect_merge("managed project change invalidates cache and preserves overrides")

projects.write_text(
    projects.read_text() + '\n[projects."/fixture/user-added"]\ntrust_level = "trusted"\n'
)
expected["projects"]["/fixture/user-added"] = {"trust_level": "trusted"}
expect_merge("mutable project change invalidates cache and preserves overrides")

overrides.write_text("[approval_policy.granular]\nrules = false\n")
expected["approval_policy"] = copy.deepcopy(read_config(base)["approval_policy"])
expected["approval_policy"]["granular"]["rules"] = False
expected["approvals_reviewer"] = read_config(base)["approvals_reviewer"]
expected["projects"]["/fixture/shared"] = read_config(projects)["projects"]["/fixture/shared"]
expect_merge("partial granular override preserves siblings and removes old override keys")

for path, label in ((projects, "user-managed projects"), (overrides, "user overrides")):
    original = path.read_text()
    previous_output = output.read_bytes()
    previous_stamp = stamp.read_bytes()
    path.write_text("[\n")
    try:
        result = launch(fixture)
        require(condition=result.returncode != 0, message=f"accepted malformed {label}")
        require(condition=label in result.stderr, message=result.stderr)
        require(
            condition=output.read_bytes() == previous_output,
            message=f"malformed {label} replaced valid config",
        )
        require(
            condition=stamp.read_bytes() == previous_stamp,
            message=f"malformed {label} advanced cache stamp",
        )
    finally:
        path.write_text(original)
    expect_merge(f"recovery after malformed {label}")

overrides.unlink()
expected["approval_policy"] = read_config(base)["approval_policy"]
expect_merge("removing overrides restores the managed policy")

projects.unlink()
expected["projects"] = read_config(base)["projects"] | read_config(managed)["projects"]
expect_merge("removing mutable projects removes their entries and restores managed precedence")
print("Configuration layer precedence, regeneration, overrides, and failure recovery passed.")
