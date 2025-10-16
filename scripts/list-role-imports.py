#!/usr/bin/env python3
"""Enumerate role imports from flake.nixosModules.roles.*.

Produces a discoverability report showing which app modules each role pulls in.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from collections import defaultdict
from typing import Dict, Iterable, List, Sequence, Set, Tuple

ROLE_DEF_RE = re.compile(
    r"flake\.nixosModules\.roles\.(?P<path>(?:\"[^\"]+\"|[A-Za-z0-9_-]+)(?:\.(?:\"[^\"]+\"|[A-Za-z0-9_-]+))*)(?:\.imports)?\s*="
)
NIXOS_MODULE_REF_RE = re.compile(
    r"config\.flake\.nixosModules\.(?P<path>(?:\"[^\"]+\"|[A-Za-z0-9_-]+)(?:\.(?:\"[^\"]+\"|[A-Za-z0-9_-]+))*)"
)
LIST_PATH_RE = re.compile(
    r"lib\.(?:getAttrFromPath|hasAttrByPath|attrByPath)\s*\[(?P<contents>[^\]]+)\]\s*config\.flake\.nixosModules"
)
LIST_ASSIGN_RE = re.compile(r"(?ms)^\s*(?P<name>[A-Za-z0-9_.-]+)\s*=\s*\[(?P<body>.*?)\];")
STRING_RE = re.compile(r'"([^\"]+)"')
GETAPP_RE = re.compile(r"getApp\s+\"([^\"]+)\"")
GETAPPS_RE = re.compile(r"getApps\s+(?P<arg>\[[^\]]*\]|[A-Za-z0-9_.-]+)", re.DOTALL)
INPUTS_MODULE_REF_RE = re.compile(
    r"inputs\.self\.nixosModules\.(?P<path>(?:\"[^\"]+\"|[A-Za-z0-9_-]+)(?:\.(?:\"[^\"]+\"|[A-Za-z0-9_-]+))*)"
)


@dataclass(frozen=True)
class RoleDefinition:
    file: Path
    segments: Tuple[str, ...]

    @property
    def dotted(self) -> str:
        return ".".join(self.segments)


def _split_attr_path(raw: str) -> Tuple[str, ...]:
    segments: List[str] = []
    for part in raw.split("."):
        part = part.strip()
        if part.startswith('"') and part.endswith('"'):
            segments.append(part[1:-1])
        else:
            segments.append(part)
    # Drop trailing helper segments like "imports" that describe attributes rather than path.
    if segments and segments[-1] == "imports":
        segments = segments[:-1]
    return tuple(filter(None, segments))


def parse_role_file(path: Path) -> Tuple[List[RoleDefinition], List[Tuple[str, ...]], List[str]]:
    text = path.read_text(encoding="utf-8")
    roles: List[RoleDefinition] = []
    refs: List[Tuple[str, ...]] = []
    apps: Set[str] = set()

    for match in ROLE_DEF_RE.finditer(text):
        segments = _split_attr_path(match.group("path"))
        if segments:
            roles.append(RoleDefinition(file=path, segments=segments))

    for match in NIXOS_MODULE_REF_RE.finditer(text):
        segments = _split_attr_path(match.group("path"))
        if segments:
            refs.append(segments)

    for match in LIST_PATH_RE.finditer(text):
        contents = match.group("contents")
        segments = tuple(filter(None, [token.strip().strip('"') for token in contents.split()]))
        if segments:
            refs.append(segments)

    for match in INPUTS_MODULE_REF_RE.finditer(text):
        segments = _split_attr_path(match.group("path"))
        if segments:
            refs.append(segments)

    def strip_comments(snippet: str) -> str:
        without_block = re.sub(r"/\*.*?\*/", "", snippet, flags=re.DOTALL)
        lines = [line.split("#", 1)[0] for line in without_block.splitlines()]
        return "\n".join(lines)

    list_assignments: Dict[str, List[str]] = {}
    for match in LIST_ASSIGN_RE.finditer(text):
        name = match.group("name")
        normalized_body = strip_comments(match.group("body"))
        values = STRING_RE.findall(normalized_body)
        if values:
            list_assignments[name] = values

    for match in GETAPP_RE.finditer(text):
        apps.add(match.group(1))

    for match in GETAPPS_RE.finditer(text):
        arg = strip_comments(match.group("arg")).strip()
        if arg.startswith("["):
            apps.update(STRING_RE.findall(arg))
        else:
            apps.update(list_assignments.get(arg, []))

    for name, values in list_assignments.items():
        lowered = name.lower()
        if lowered.endswith("apps") or lowered.endswith("app"):
            apps.update(values)

    return roles, refs, sorted(apps)


def nix_list(strings: Sequence[str]) -> str:
    return "[ " + " ".join(json.dumps(s) for s in strings) + " ]"


def build_nix_expr(
    repo: Path,
    role_def: RoleDefinition,
    stub_paths: Sequence[Sequence[str]],
) -> str:
    repo_json = json.dumps(str(repo))
    role_rel = "/" + str(role_def.file.relative_to(repo)).replace("\\", "/")
    role_path_expr = json.dumps(role_rel)
    role_attr_expr = nix_list(["roles", *role_def.segments])
    stub_json = json.dumps([list(p) for p in stub_paths])

    return f"""
let
  repo = {repo_json};
  flake = builtins.getFlake ("path:" + repo);
  lib = flake.inputs.nixpkgs.lib;
  stubModule = {{ imports = [ ]; }};
  stubPaths = builtins.fromJSON ''{stub_json}'';
  stubModules = lib.foldl (acc: path: lib.recursiveUpdate acc (lib.setAttrByPath path stubModule)) {{ apps = {{ }}; }} stubPaths;
  mkApp = name: {{ kind = "app"; inherit name; }};
  helper = {{
    getApp = mkApp;
    getApps = names: map mkApp names;
    getAppOr = name: _: mkApp name;
    hasApp = _: true;
  }};
  config = {{
    flake = {{
      lib.nixos = helper;
      nixosModules = stubModules;
    }};
    _module.args = {{
      nixosAppHelpers = helper;
      inputs = {{
        self = {{
          nixosModules = stubModules;
        }};
      }};
    }};
  }};
  roleModule = import (repo + {role_path_expr});
  result = roleModule {{ inherit lib config; }};
  roleAttr = lib.getAttrFromPath {role_attr_expr} result.flake.nixosModules;
  imports = roleAttr.imports or [ ];
in map (entry:
  if entry ? kind && entry.kind == "app" then
    {{ kind = "app"; name = entry.name; }}
  else
    let
      entryType = builtins.typeOf entry;
      file =
        if entryType == "set" && entry ? _file then entry._file else null;
      tag =
        if entryType == "set" && entry ? name then entry.name else null;
    in
    {{
      kind = "module";
      file = file;
      type = entryType;
      tag = tag;
    }}
) imports
"""


def collect_stub_paths(refs: Iterable[Sequence[str]]) -> List[List[str]]:
    paths = {tuple(ref) for ref in refs if ref}
    paths.add(("apps",))
    paths.add(("base",))
    return [list(path) for path in sorted(paths)]


def relativize(path_str: str, repo: Path) -> str:
    path = Path(path_str)
    try:
        return str(path.resolve().relative_to(repo))
    except (ValueError, RuntimeError):
        return path_str


def summarize_other(entry: dict, repo: Path, fallback_file: Path) -> Tuple[str, dict]:
    entry_type = entry.get("type")
    tag = entry.get("tag")
    file = entry.get("file")
    if not file and entry_type == "lambda":
        file = str(fallback_file)
    summary = tag or entry_type or "unknown"
    if file:
        summary = f"{summary}@{relativize(file, repo)}"
    return summary, {
        "type": entry_type,
        "tag": tag,
        "file": file,
    }


def run_nix(expr: str, cwd: Path) -> List[dict]:
    try:
        out = subprocess.run(
            [
                "nix",
                "eval",
                "--impure",
                "--accept-flake-config",
                "--json",
                "--expr",
                expr,
            ],
            cwd=cwd,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        sys.stderr.write(exc.stderr)
        raise
    return json.loads(out.stdout)


def format_table(rows: Sequence[Tuple[str, List[str], List[str]]]) -> str:
    lines = []
    header = f"{'Role':30} | Apps | Other"
    lines.append(header)
    lines.append("-" * len(header))
    for role, apps, others in rows:
        app_list = ", ".join(apps)
        other_list = ", ".join(others)
        lines.append(f"{role:30} | {app_list} | {other_list}")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--format", choices=["table", "json"], default="table")
    parser.add_argument(
        "--repo",
        type=str,
        help="Path to the repository root (defaults to the script location)",
    )
    parser.add_argument(
        "--offline",
        action="store_true",
        help="Skip Nix evaluation and rely on static parsing (suitable for CI)",
    )
    args = parser.parse_args()

    repo = Path(args.repo).resolve() if args.repo else Path(__file__).resolve().parent.parent
    role_dir = repo / "modules" / "roles"
    role_files = sorted(role_dir.rglob("*.nix"))

    role_defs: List[RoleDefinition] = []
    stub_refs: List[Tuple[str, ...]] = []
    role_attr_refs: Dict[str, Set[str]] = defaultdict(set)
    file_app_map: Dict[Path, List[str]] = {}

    for path in role_files:
        roles, refs, apps = parse_role_file(path)
        role_defs.extend(roles)
        stub_refs.extend(refs)
        ref_strings = {".".join(r) for r in refs if r and r[0] != "apps"}
        for role in roles:
            role_attr_refs[role.dotted].update(ref_strings)
        file_app_map[path] = apps

    if not role_defs:
        print("No roles detected", file=sys.stderr)
        return 1

    stub_paths = collect_stub_paths(stub_refs)
    rows: List[Tuple[str, List[str], List[str]]] = []
    results = {}

    for role in sorted(role_defs, key=lambda r: r.dotted):
        offline_apps = file_app_map.get(role.file, [])
        apps: List[str] = []
        other_summaries: List[str] = []
        other_details: List[dict] = []

        if args.offline:
            apps = list(offline_apps)
        else:
            expr = build_nix_expr(repo, role, stub_paths)
            raw_entries = run_nix(expr, repo)
            for entry in raw_entries:
                if entry.get("kind") == "app":
                    apps.append(entry["name"])
                else:
                    summary, detail = summarize_other(entry, repo, role.file)
                    other_summaries.append(summary)
                    other_details.append(detail)

            if not apps:
                apps = list(offline_apps)

        apps = sorted(dict.fromkeys(apps))
        ref_list = sorted(role_attr_refs.get(role.dotted, set()))
        display = ref_list if ref_list else other_summaries
        rows.append((role.dotted, apps, display))
        results[role.dotted] = {
            "apps": apps,
            "other_imports": {
                "attr_paths": ref_list,
                "evaluation": other_details,
            },
        }

    if args.format == "json":
        json.dump(results, sys.stdout, indent=2, sort_keys=True)
        print()
    else:
        print(format_table(rows))

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError:
        raise SystemExit(1)
