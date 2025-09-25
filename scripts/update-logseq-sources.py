#!/usr/bin/env python3
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.parse
from pathlib import Path


def run(cmd, *, cwd=None, capture=False):
    result = subprocess.run(cmd, cwd=cwd, text=True, capture_output=capture, check=True)
    return result.stdout if capture else None


def run_optional(cmd, *, cwd=None):
    return subprocess.run(cmd, cwd=cwd, text=True, capture_output=True)


def ensure(condition, message):
    if not condition:
        sys.stderr.write(message + "\n")
        sys.exit(1)


def nix_str(value: str) -> str:
    """Return a JSON-escaped string suitable for embedding in a Nix expression."""
    return json.dumps(str(value))


def main():
    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent
    logseq_arg = sys.argv[1] if len(sys.argv) > 1 else repo_root / "inputs/logseq"
    logseq_repo = Path(os.environ.get("LOGSEQ_SOURCE_DIR", logseq_arg)).resolve()

    ensure(logseq_repo.is_dir(), f"error: unable to locate logseq source at '{logseq_repo}'")

    pkg_dir = repo_root / "packages/logseq-fhs"
    git_deps_file = pkg_dir / "git-deps.nix"
    yarn_deps_file = pkg_dir / "yarn-deps.nix"
    resources_workspace_dir = pkg_dir / "resources-workspace"
    placeholder_patch = pkg_dir / "main-placeholder.patch"

    rg_proc = run_optional(["rg", ":git/(url|sha)", "-l"], cwd=logseq_repo)
    ensure(rg_proc.returncode in (0, 1), rg_proc.stderr)

    placeholder_files = [
        "bb.edn",
        "deps.edn",
        "clj-e2e/deps.edn",
        "deps/cli/bb.edn",
        "deps/cli/nbb.edn",
        "deps/common/bb.edn",
        "deps/common/deps.edn",
        "deps/common/nbb.edn",
        "deps/db/bb.edn",
        "deps/db/deps.edn",
        "deps/db/nbb.edn",
        "deps/graph-parser/bb.edn",
        "deps/graph-parser/deps.edn",
        "deps/graph-parser/nbb.edn",
        "deps/outliner/bb.edn",
        "deps/outliner/deps.edn",
        "deps/outliner/nbb.edn",
        "deps/publishing/bb.edn",
        "deps/publishing/nbb.edn",
        "deps/shui/deps.edn",
    ]

    git_ref_files = [line.strip() for line in rg_proc.stdout.splitlines() if line.strip()]
    missing = [rel for rel in git_ref_files if rel not in placeholder_files]
    if missing:
        sys.stderr.write("Placeholder patch is missing the following files:\n")
        for rel in missing:
            sys.stderr.write(f"  {rel}\n")
        sys.exit(1)

    print("\n--- Prefetching git dependencies ---")

    git_order = [
        "bb_tasks_src",
        "bb_tasks_db_src",
        "rum_src",
        "datascript_src",
        "cljs_time_src",
        "cljc_fsrs_src",
        "cljs_http_missionary_src",
        "clj_fractional_indexing_src",
        "wally_src",
        "nbb_test_runner_src",
        "cognitect_test_runner_src",
        "electron_node_gyp_src",
        "electron_forge_maker_appimage_src",
    ]

    git_meta = {
        "bb_tasks_src": ("logseq", "bb-tasks", "70d3edeb287f5cec7192e642549a401f7d6d4263"),
        "bb_tasks_db_src": ("logseq", "bb-tasks", "1d429e223baeade426d30a4ed1c8a110173a2402"),
        "rum_src": ("logseq", "rum", "5d672bf84ed944414b9f61eeb83808ead7be9127"),
        "datascript_src": ("logseq", "datascript", "45f6721bf2038c24eb9fe3afb422322ab3f473b5"),
        "cljs_time_src": ("logseq", "cljs-time", "5704fbf48d3478eedcf24d458c8964b3c2fd59a9"),
        "cljc_fsrs_src": ("rcmerci", "cljc-fsrs", "0e70e96a73cf63c85dcc2df4d022edf12806b239"),
        "cljs_http_missionary_src": ("RCmerci", "cljs-http-missionary", "d61ce7e29186de021a2a453a8cee68efb5a88440"),
        "clj_fractional_indexing_src": ("logseq", "clj-fractional-indexing", "1087f0fb18aa8e25ee3bbbb0db983b7a29bce270"),
        "wally_src": ("logseq", "wally", "8571fae7c51400ac61c8b1026cbfba68279bc461"),
        "nbb_test_runner_src": ("nextjournal", "nbb-test-runner", "b379325cfa5a3306180649da5de3bf5166414e71"),
        "cognitect_test_runner_src": ("cognitect-labs", "test-runner", "dfb30dd6605cb6c0efc275e1df1736f6e90d4d73"),
        "electron_node_gyp_src": ("electron", "node-gyp", "06b29aafb7708acef8b3669835c8a7857ebc92d2"),
        "electron_forge_maker_appimage_src": ("logseq", "electron-forge-maker-appimage", "4bf4d4eb5925f72945841bd2fa7148322bc44189"),
    }

    git_hashes = {}
    for name in git_order:
        owner, repo, rev = git_meta[name]
        url = f"https://github.com/{owner}/{repo}"
        print(f"\n[{name}] {url} @ {rev}")
        json_text = run(["nix", "run", "nixpkgs#nix-prefetch-git", "--", "--quiet", url, rev], capture=True)
        git_hashes[name] = json.loads(json_text)["hash"]

    git_lines = [
        "{ fetchFromGitHub }:",
        "let",
        "  fetchGitHub =",
        "    { owner, repo, rev, hash }:",
        "    fetchFromGitHub {",
        "      inherit owner repo rev hash;",
        "    };",
        "in",
        "{",
    ]
    for name in git_order:
        owner, repo, rev = git_meta[name]
        hash_value = git_hashes[name]
        git_lines.append(f"  {name} = fetchGitHub {{")
        git_lines.append(f"    owner = \"{owner}\";")
        git_lines.append(f"    repo = \"{repo}\";")
        git_lines.append(f"    rev = \"{rev}\";")
        git_lines.append(f"    hash = \"{hash_value}\";")
        git_lines.append("  };\n")
    git_lines.append("}")
    git_deps_file.write_text("\n".join(git_lines) + "\n")

    git_deps_abs = str(git_deps_file)
    system = run(["nix", "eval", "--impure", "--raw", "--expr", "builtins.currentSystem"], capture=True).strip()
    flake_path = str(repo_root)
    nix_flake = nix_str(flake_path)
    nix_system = nix_str(system)
    nix_git_deps = nix_str(git_deps_abs)

    git_paths = json.loads(
        run(
            [
                "nix",
                "eval",
                "--impure",
                "--json",
                "--expr",
                "let flake = builtins.getFlake "
                + nix_flake
                + "; pkgs = import flake.inputs.nixpkgs { system = "
                + nix_system
                + "; }; gitDeps = import "
                + nix_git_deps
                + " { inherit (pkgs) fetchFromGitHub; }; in pkgs.lib.mapAttrs (_: v: builtins.toString v) gitDeps",
            ],
            capture=True,
        )
    )

    electron_node_gyp_rev = git_meta["electron_node_gyp_src"][2]
    electron_forge_rev = git_meta["electron_forge_maker_appimage_src"][2]
    node_gyp_hash = git_hashes["electron_node_gyp_src"]
    node_expr = (
        "let\n"
        f"  flake = builtins.getFlake {nix_flake};\n"
        f"  pkgs = import flake.inputs.nixpkgs {{ system = {nix_system}; }};\n"
        "  electronNodeGypSrc = pkgs.fetchFromGitHub {\n"
        "    owner = \"electron\";\n"
        "    repo = \"node-gyp\";\n"
        f"    rev = {nix_str(electron_node_gyp_rev)};\n"
        f"    hash = {nix_str(node_gyp_hash)};\n"
        "  };\n"
        "  nodeGypArchive = \"node-gyp-${electronNodeGypSrc.rev}\";\n"
        "  nodeGypTarball = pkgs.runCommand \"logseq-node-gyp-tgz\" {} ''\n"
        "    mkdir -p $out\n"
        "    tar --directory ${electronNodeGypSrc} --transform='s,^\\.,package,' -czf $out/${nodeGypArchive}.tgz .\n"
        "  '';\n"
        "  nodeGypUnpacked = pkgs.runCommand \"logseq-node-gyp-unpacked\" {} ''\n"
        "    mkdir -p $out\n"
        "    tar -xzf ${nodeGypTarball}/${nodeGypArchive}.tgz -C $out\n"
        "    mv $out/package $out/node-gyp\n"
        "  '';\n"
        "in nodeGypUnpacked\n"
    )
    with tempfile.NamedTemporaryFile("w", suffix=".nix", delete=False) as tmp:
        tmp.write(node_expr)
        tmp_path = Path(tmp.name)
    try:
        node_gyp_unpacked = run(["nix", "build", "--impure", "--print-out-paths", "-f", str(tmp_path)], capture=True).strip()
    finally:
        tmp_path.unlink(missing_ok=True)
    node_gyp_dir = Path(node_gyp_unpacked) / "node-gyp"

    maker_path = git_paths["electron_forge_maker_appimage_src"]

    local_node_gyp = ".nix-cache/git/electron-node-gyp"
    local_maker = ".nix-cache/git/electron-forge-maker-appimage"

    with tempfile.TemporaryDirectory() as patched_dir_str:
        patched_dir = Path(patched_dir_str)
        shutil.copytree(logseq_repo, patched_dir, dirs_exist_ok=True)
        shutil.rmtree(patched_dir / ".git", ignore_errors=True)
        subprocess.run(["patch", "-p1", "-i", str(placeholder_patch)], cwd=patched_dir, check=True)

        resources_dir = patched_dir / "resources"
        resources_dir.mkdir(parents=True, exist_ok=True)
        vendored_pkg = resources_workspace_dir / "package.json"
        vendored_lock = resources_workspace_dir / "yarn.lock"
        ensure(vendored_pkg.exists(), f"missing vendored {vendored_pkg}")
        ensure(vendored_lock.exists(), f"missing vendored {vendored_lock}")
        shutil.copy2(vendored_pkg, resources_dir / "package.json")
        shutil.copy2(vendored_lock, resources_dir / "yarn.lock")

        placeholder_map = {f"@{name}@": git_paths[name] for name in git_order}
        for rel in placeholder_files:
            target = patched_dir / rel
            text = target.read_text()
            for marker, value in placeholder_map.items():
                text = text.replace(marker, value)
            target.write_text(text)

        def rewrite_static_lock(lock_path: Path) -> None:
            content = lock_path.read_text()

            resolved_re = re.compile(r'resolved "(https://registry\.yarnpkg\.com/[^"]+)"')

            def sanitize(component: str) -> str:
                return ''.join(ch if ch.isalnum() or ch == '.' else '_' for ch in component)

            def mapped_filename(url: str) -> str:
                if url.startswith('file:'):
                    return url.split('/', 1)[-1]
                parsed = urllib.parse.urlparse(url)
                if parsed.scheme not in ('http', 'https'):
                    return url
                path_parts = parsed.path.strip('/').split('/')
                if len(path_parts) < 3 or path_parts[-2] != '-':
                    return url

                filename = urllib.parse.unquote(path_parts[-1])
                base, _, ext = filename.rpartition('.')
                if not base or not ext:
                    return url

                if path_parts[0].startswith('@') and len(path_parts) >= 2:
                    scope_raw = path_parts[0][1:]
                    pkg_name = path_parts[1]
                    prefix = f"_{sanitize(scope_raw)}_{sanitize(pkg_name)}"
                else:
                    pkg_name = path_parts[0]
                    prefix = sanitize(pkg_name)

                package_basename = path_parts[1] if path_parts[0].startswith('@') and len(path_parts) >= 2 else path_parts[0]
                version_prefix = f"{package_basename}-"
                if base.startswith(version_prefix):
                    version_part = base[len(version_prefix):]
                else:
                    parts = base.split('-', 1)
                    version_part = parts[1] if len(parts) == 2 else ''

                if not version_part:
                    return url

                tail = f"{sanitize(package_basename)}_{sanitize(version_part)}.{ext}"
                return f"{prefix}___{tail}"

            def repl(match: re.Match) -> str:
                url = match.group(1)
                return f'resolved "file:.nix-cache/resources/{mapped_filename(url)}"'

            lock_path.write_text(resolved_re.sub(repl, content))

        for lock_path in patched_dir.rglob("yarn.lock"):
            text = lock_path.read_text()
            text = text.replace(
                "\"electron-forge-maker-appimage@https://github.com/logseq/electron-forge-maker-appimage.git\"",
                f"\"electron-forge-maker-appimage@file:{local_maker}\"",
            )
            text = text.replace(
                f"git+https://github.com/logseq/electron-forge-maker-appimage.git#{electron_forge_rev}",
                f"file:{local_maker}",
            )
            text = text.replace(
                f"https://github.com/logseq/electron-forge-maker-appimage.git#{electron_forge_rev}",
                f"file:{local_maker}",
            )
            text = text.replace(
                "\"electron-forge-maker-appimage@file:@electron_forge_maker_appimage_src@\"",
                f"\"electron-forge-maker-appimage@file:{local_maker}\"",
            )
            text = text.replace(
                'resolved "file:@electron_forge_maker_appimage_src@"',
                f'resolved "file:{local_maker}"',
            )
            text = text.replace(
                f"git+https://github.com/electron/node-gyp.git#{electron_node_gyp_rev}",
                f"file:{local_node_gyp}",
            )
            text = text.replace(
                f"https://github.com/electron/node-gyp#{electron_node_gyp_rev}",
                f"file:{local_node_gyp}",
            )
            lock_path.write_text(text)

            rel_parts = lock_path.relative_to(patched_dir).parts
            if rel_parts and rel_parts[0] == "static":
                rewrite_static_lock(lock_path)

        (patched_dir / ".nix-cache" / "resources").mkdir(parents=True, exist_ok=True)

        local_node_gyp_dir = patched_dir / local_node_gyp
        shutil.rmtree(local_node_gyp_dir, ignore_errors=True)
        local_node_gyp_dir.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(node_gyp_dir, local_node_gyp_dir)

        local_maker_dir = patched_dir / local_maker
        shutil.rmtree(local_maker_dir, ignore_errors=True)
        local_maker_dir.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(Path(maker_path), local_maker_dir)

        yarn_entries = [
            ("root", "yarn.lock"),
            ("scripts", "scripts/yarn.lock"),
            ("libs", "libs/yarn.lock"),
            ("deps_common", "deps/common/yarn.lock"),
            ("deps_db", "deps/db/yarn.lock"),
            ("deps_graph_parser", "deps/graph-parser/yarn.lock"),
            ("deps_outliner", "deps/outliner/yarn.lock"),
            ("deps_publishing", "deps/publishing/yarn.lock"),
            ("deps_cli", "deps/cli/yarn.lock"),
            ("packages_amplify", "packages/amplify/yarn.lock"),
            ("packages_tldraw", "packages/tldraw/yarn.lock"),
            ("packages_ui", "packages/ui/yarn.lock"),
            ("resources", "resources/yarn.lock"),
        ]
        source_roots = {
            "root": ".",
            "scripts": "scripts",
            "libs": "libs",
            "deps_common": "deps/common",
            "deps_db": "deps/db",
            "deps_graph_parser": "deps/graph-parser",
            "deps_outliner": "deps/outliner",
            "deps_publishing": "deps/publishing",
            "deps_cli": "deps/cli",
            "packages_amplify": "packages/amplify",
            "packages_tldraw": "packages/tldraw",
            "packages_ui": "packages/ui",
            "resources": ".",
        }

        yarn_hashes = {}
        hash_pattern = re.compile(r"sha256-[0-9A-Za-z+/=]+|[0-9a-z]{52}")
        debug_hashes = os.environ.get("LOGSEQ_SOURCES_DEBUG_HASHES")

        debug_hashes = os.environ.get("LOGSEQ_SOURCES_DEBUG_HASHES")
        debug_dump = os.environ.get("LOGSEQ_SOURCES_DEBUG_DUMP")

        for attr, rel in yarn_entries:
            target_lock = patched_dir / rel
            print(f"\n[{attr}] {rel}")
            ensure(target_lock.exists(), f"expected lockfile {target_lock} missing")
            proc = subprocess.run(
                ["nix", "run", "nixpkgs#prefetch-yarn-deps", "--", str(target_lock)],
                text=True,
                capture_output=True,
            )
            ensure(proc.returncode == 0, proc.stderr)
            match = None
            for line in proc.stdout.splitlines():
                candidate = line.strip()
                if hash_pattern.fullmatch(candidate):
                    match = candidate
            ensure(match, f"unable to parse sha256 from prefetch-yarn-deps output for {rel}\nstdout: {proc.stdout}\nstderr: {proc.stderr}")
            if match.startswith("sha256-"):
                match = run(
                    ["nix", "hash", "to-base32", match],
                    capture=True,
                ).strip()
            elif debug_hashes:
                # Also show sri form for base32 outputs so the comparison is easier
                sri = run(
                    [
                        "nix",
                        "hash",
                        "convert",
                        "--hash-algo",
                        "sha256",
                        "--from",
                        "nix32",
                        "--to",
                        "sri",
                        match,
                    ],
                    capture=True,
                ).strip()
                print(f"  sri: {sri}")
            yarn_hashes[attr] = match
            if debug_hashes:
                if not match.startswith("sha256-"):
                    sri = run(
                        [
                            "nix",
                            "hash",
                            "convert",
                            "--hash-algo",
                            "sha256",
                            "--from",
                            "nix32",
                            "--to",
                            "sri",
                            match,
                        ],
                        capture=True,
                    ).strip()
                    print(f"  sri: {sri}")
                print(f"  hash: {match}")

        placeholder_pattern = re.compile(r"@[A-Za-z0-9_]+@")
        still_tagged = []
        for rel in placeholder_files:
            target = patched_dir / rel
            if placeholder_pattern.search(target.read_text(errors="ignore")):
                still_tagged.append(rel)
        for lock_path in patched_dir.rglob("yarn.lock"):
            if placeholder_pattern.search(lock_path.read_text(errors="ignore")):
                still_tagged.append(str(lock_path.relative_to(patched_dir)))
        if still_tagged:
            sys.stderr.write("error: unresolved placeholders remain after substitution:\n")
            for rel in still_tagged:
                sys.stderr.write(f"  {rel}\n")
            sys.exit(1)

        lines = ["{"]
        for attr, rel in yarn_entries:
            hash_value = yarn_hashes[attr]
            if attr == "resources":
                lines.append("  resources = {")
                lines.append("    src = ./resources-workspace;")
                lines.append("    sourceRoot = \".\";")
                lines.append(f"    sha256 = \"{hash_value}\";")
                lines.append("    yarnLock = \"yarn.lock\";")
                lines.append("    lockFile = \"yarn.lock\";")
                lines.append("    packageJSON = \"package.json\";")
                lines.append("  };\n")
            else:
                lines.append(f"  {attr} = {{")
                lines.append(f"    sourceRoot = \"{source_roots[attr]}\";")
                lines.append(f"    sha256 = \"{hash_value}\";")
                lines.append(f"    yarnLock = \"{rel}\";")
                lines.append(f"    lockFile = \"{rel}\";")
                lines.append("  };\n")
        lines.append("}")
        yarn_deps_file.write_text("\n".join(lines) + "\n")

        if debug_dump:
            dest = Path(debug_dump)
            if dest.exists():
                shutil.rmtree(dest)
            shutil.copytree(patched_dir, dest)

        resources_workspace_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(patched_dir / "resources" / "package.json", resources_workspace_dir / "package.json")
        shutil.copy2(patched_dir / "resources" / "yarn.lock", resources_workspace_dir / "yarn.lock")

    package_path = resources_workspace_dir / "package.json"
    package_data = json.loads(package_path.read_text())
    package_data.setdefault("devDependencies", {})["electron-forge-maker-appimage"] = "file:@electron_forge_maker_appimage_src@"
    package_path.write_text(json.dumps(package_data, indent=2) + "\n")

    lock_path = resources_workspace_dir / "yarn.lock"
    lock_text = lock_path.read_text()
    lock_text = lock_text.replace(
        f'"electron-forge-maker-appimage@file:{maker_path}"',
        '"electron-forge-maker-appimage@file:@electron_forge_maker_appimage_src@"',
    )
    lock_text = lock_text.replace(
        f'resolved "file:{maker_path}"',
        'resolved "file:@electron_forge_maker_appimage_src@"',
    )
    lock_path.write_text(lock_text)

    print(f"\nUpdated {git_deps_file.relative_to(repo_root)} and {yarn_deps_file.relative_to(repo_root)}")
    print("Re-run nix fmt if needed and rebuild the caches to validate the new hashes.")


if __name__ == "__main__":
    main()
