#!/usr/bin/env python3
"""duplicati-r2-list: read-only path and snapshot queries over Duplicati's local SQLite.

Implements Cut A of the design recorded in
docs/drafts/duplicati-r2-readonly-mount-investigation.md. Opens the per-target
SQLite database at <stateDir>/duplicati-r2-<slug>.sqlite with mode=ro and
answers questions about snapshots, paths, sizes, modification times, and
version history. No R2 fetches, no AES decryption.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import sqlite3
import sys
import urllib.parse
from datetime import datetime, timezone
from typing import NoReturn

DEFAULT_CONFIG = "/run/duplicati-r2/config.json"
DEFAULT_STATE_DIR = "/var/lib/duplicati-r2"
SCHEMA_SLUG_RE = re.compile(r"[^A-Za-z0-9_\-]")
SUPPORTED_SCHEMA_VERSIONS = {"19"}

EXIT_USAGE = 64
EXIT_DATA_ERR = 65
EXIT_OPEN_ERR = 66


def warn(msg: str) -> None:
    print(f"duplicati-r2-list: {msg}", file=sys.stderr)


def fail(msg: str, code: int = EXIT_OPEN_ERR) -> NoReturn:
    warn(msg)
    sys.exit(code)


def sanitize_slug(slug: str) -> str:
    return SCHEMA_SLUG_RE.sub("-", slug)


def parse_snapshot(value: str | None) -> tuple[str, int | str] | None:
    """Translate --snapshot into a typed selector.

    Returns None for "latest" or unset. Otherwise yields ("id", int) for a
    bare integer or ("at_or_before", iso_str) for a timestamp.
    """
    if value is None or value == "latest":
        return None
    if value.isdigit():
        return ("id", int(value))
    return ("at_or_before", value)


def iso_utc(epoch: int | None) -> str:
    if epoch is None:
        return "-"
    return datetime.fromtimestamp(epoch, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def human_size(n: int | None) -> str:
    if n is None:
        return "-"
    units = ["B", "K", "M", "G", "T", "P"]
    value = float(n)
    idx = 0
    while value >= 1024 and idx < len(units) - 1:
        value /= 1024.0
        idx += 1
    if idx == 0:
        return f"{int(value)}{units[idx]}"
    return f"{value:.1f}{units[idx]}"


def load_manifest(config_path: str) -> dict | None:
    try:
        with open(config_path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except FileNotFoundError:
        warn(f"manifest {config_path} not found; using default stateDir")
        return None
    except PermissionError:
        warn(
            f"manifest {config_path} not readable by uid={os.getuid()}; using default stateDir"
        )
        return None
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"failed to read {config_path}: {exc}")
    if not isinstance(data, dict):
        fail(f"manifest {config_path} is not a JSON object")
    return data


def resolve_db_path(args: argparse.Namespace) -> str:
    if args.db:
        return args.db

    slug = args.slug
    config_path = args.config or os.environ.get("DUPLICATI_R2_CONFIG") or DEFAULT_CONFIG
    manifest = load_manifest(config_path)

    state_dir = DEFAULT_STATE_DIR
    target_state_dir: str | None = None
    if manifest is not None:
        if isinstance(manifest.get("stateDir"), str):
            state_dir = manifest["stateDir"]
        targets = manifest.get("targets")
        if not isinstance(targets, dict) or slug not in targets:
            fail(f"unknown target '{slug}' in {config_path}")
        target = targets[slug]
        if isinstance(target, dict):
            if target.get("enable") is False:
                fail(f"target '{slug}' is disabled in {config_path}")
            if isinstance(target.get("stateDir"), str):
                target_state_dir = target["stateDir"]

    if target_state_dir is None and manifest is None:
        target_state_dir = os.path.join(state_dir, slug)

    effective_state_dir = target_state_dir or state_dir
    db_slug = sanitize_slug(slug)
    return os.path.join(effective_state_dir, f"duplicati-r2-{db_slug}.sqlite")


def open_db(db_path: str) -> sqlite3.Connection:
    if not os.path.exists(db_path):
        fail(f"database not found: {db_path}")
    quoted = urllib.parse.quote(os.path.abspath(db_path))
    uri = f"file:{quoted}?mode=ro"
    try:
        conn = sqlite3.connect(uri, uri=True, isolation_level=None)
    except sqlite3.Error as exc:
        fail(f"sqlite open failed for {db_path}: {exc}")
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA query_only = ON")
    version_row = conn.execute(
        "SELECT Value FROM Configuration WHERE Key = 'Version'"
    ).fetchone()
    if version_row is None:
        fail(f"{db_path} missing Configuration.Version row", EXIT_DATA_ERR)
    if str(version_row["Value"]) not in SUPPORTED_SCHEMA_VERSIONS:
        fail(
            f"{db_path} schema version {version_row['Value']!r} is not in supported set {sorted(SUPPORTED_SCHEMA_VERSIONS)}",
            EXIT_DATA_ERR,
        )
    return conn


def resolve_snapshot(
    conn: sqlite3.Connection, selector: tuple[str, int | str] | None
) -> sqlite3.Row | None:
    if selector is None:
        return conn.execute(
            "SELECT ID, Timestamp, IsFullBackup FROM Fileset ORDER BY Timestamp DESC LIMIT 1"
        ).fetchone()
    kind, value = selector
    if kind == "id":
        row = conn.execute(
            "SELECT ID, Timestamp, IsFullBackup FROM Fileset WHERE ID = ?",
            (value,),
        ).fetchone()
        if row is None:
            fail(f"snapshot id {value} not found", EXIT_USAGE)
        return row
    try:
        ts = int(datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp())
    except ValueError:
        fail(
            f"--snapshot {value!r} is neither an integer ID nor an ISO-8601 timestamp",
            EXIT_USAGE,
        )
    row = conn.execute(
        "SELECT ID, Timestamp, IsFullBackup FROM Fileset WHERE Timestamp <= ? ORDER BY Timestamp DESC LIMIT 1",
        (ts,),
    ).fetchone()
    if row is None:
        fail(f"no snapshot at or before {value!r}")
    return row


def emit_rows(
    rows: list[dict],
    columns: list[tuple[str, str]],
    as_json: bool,
    stream: bool = False,
) -> None:
    if as_json:
        if stream:
            for row in rows:
                print(json.dumps(row, separators=(",", ":")))
        else:
            print(json.dumps(rows, indent=2))
        return
    if not rows:
        return
    widths = {key: len(label) for key, label in columns}
    for row in rows:
        for key, _ in columns:
            widths[key] = max(widths[key], len(str(row.get(key, ""))))
    header = "  ".join(label.ljust(widths[key]) for key, label in columns)
    print(header)
    print("  ".join("-" * widths[key] for key, _ in columns))
    for row in rows:
        print("  ".join(str(row.get(key, "")).ljust(widths[key]) for key, _ in columns))


def cmd_versions(args: argparse.Namespace) -> int:
    conn = open_db(resolve_db_path(args))
    rows = [
        {
            "id": r["ID"],
            "timestamp": iso_utc(r["Timestamp"]),
            "is_full_backup": bool(r["IsFullBackup"]),
        }
        for r in conn.execute(
            "SELECT ID, Timestamp, IsFullBackup FROM Fileset ORDER BY Timestamp DESC"
        )
    ]
    emit_rows(
        rows,
        [("id", "ID"), ("timestamp", "TIMESTAMP"), ("is_full_backup", "FULL")],
        args.json,
        stream=True,
    )
    return 0


def cmd_ls(args: argparse.Namespace) -> int:
    conn = open_db(resolve_db_path(args))
    snapshot = resolve_snapshot(conn, parse_snapshot(args.snapshot))
    if snapshot is None:
        fail("no snapshots present in database")
    parent = args.path
    if not parent.endswith("/"):
        parent += "/"
    files = conn.execute(
        """
        SELECT
          SUBSTR(f.Path, ?) AS name,
          bs.Length         AS size,
          fse.Lastmodified  AS mtime
        FROM File f
          JOIN FilesetEntry fse ON fse.FileID = f.ID
          JOIN Blockset bs      ON bs.ID = f.BlocksetID
        WHERE fse.FilesetID = ?
          AND f.Path GLOB ?
          AND INSTR(SUBSTR(f.Path, ?), '/') = 0
        ORDER BY name
        """,
        (len(parent) + 1, snapshot["ID"], parent + "*", len(parent) + 1),
    ).fetchall()
    dirs = conn.execute(
        """
        SELECT DISTINCT
          SUBSTR(
            f.Path,
            ?,
            INSTR(SUBSTR(f.Path, ?), '/')
          ) AS name
        FROM File f
          JOIN FilesetEntry fse ON fse.FileID = f.ID
        WHERE fse.FilesetID = ?
          AND f.Path GLOB ?
          AND INSTR(SUBSTR(f.Path, ?), '/') > 0
        ORDER BY name
        """,
        (
            len(parent) + 1,
            len(parent) + 1,
            snapshot["ID"],
            parent + "*",
            len(parent) + 1,
        ),
    ).fetchall()
    rows: list[dict] = []
    for d in dirs:
        rows.append(
            {
                "name": d["name"],
                "type": "dir",
                "size": None,
                "mtime": None,
            }
        )
    for f in files:
        rows.append(
            {
                "name": f["name"],
                "type": "file",
                "size": f["size"],
                "mtime": f["mtime"],
            }
        )
    if args.json:
        emit_rows(rows, [], True, stream=True)
        return 0
    table_rows = [
        {
            "type": r["type"],
            "size": human_size(r["size"]),
            "mtime": iso_utc(r["mtime"]),
            "name": r["name"],
        }
        for r in rows
    ]
    emit_rows(
        table_rows,
        [("type", "TYPE"), ("size", "SIZE"), ("mtime", "MTIME"), ("name", "NAME")],
        False,
    )
    return 0


def cmd_stat(args: argparse.Namespace) -> int:
    conn = open_db(resolve_db_path(args))
    snapshot = resolve_snapshot(conn, parse_snapshot(args.snapshot))
    if snapshot is None:
        fail("no snapshots present in database")
    row = conn.execute(
        """
        SELECT
          f.Path           AS path,
          bs.Length        AS size,
          bs.FullHash      AS hash,
          fse.Lastmodified AS mtime
        FROM File f
          JOIN FilesetEntry fse ON fse.FileID = f.ID
          JOIN Blockset bs      ON bs.ID = f.BlocksetID
        WHERE fse.FilesetID = ?
          AND f.Path = ?
        """,
        (snapshot["ID"], args.path),
    ).fetchone()
    if row is None:
        fail(f"path '{args.path}' not in snapshot {snapshot['ID']}", EXIT_OPEN_ERR)
    record = {
        "path": row["path"],
        "snapshot_id": snapshot["ID"],
        "snapshot_timestamp": iso_utc(snapshot["Timestamp"]),
        "size": row["size"],
        "hash": row["hash"],
        "mtime": iso_utc(row["mtime"]),
    }
    if args.json:
        print(json.dumps(record, indent=2))
    else:
        for key in (
            "path",
            "snapshot_id",
            "snapshot_timestamp",
            "size",
            "hash",
            "mtime",
        ):
            print(f"{key}: {record[key]}")
    return 0


def cmd_history(args: argparse.Namespace) -> int:
    conn = open_db(resolve_db_path(args))
    rows = [
        {
            "snapshot_id": r["ID"],
            "timestamp": iso_utc(r["Timestamp"]),
            "is_full_backup": bool(r["IsFullBackup"]),
            "size": r["size"],
            "mtime": iso_utc(r["mtime"]),
        }
        for r in conn.execute(
            """
            SELECT
              fs.ID,
              fs.Timestamp,
              fs.IsFullBackup,
              bs.Length        AS size,
              fse.Lastmodified AS mtime
            FROM Fileset fs
              JOIN FilesetEntry fse ON fse.FilesetID = fs.ID
              JOIN File f           ON f.ID = fse.FileID
              JOIN Blockset bs      ON bs.ID = f.BlocksetID
            WHERE f.Path = ?
            ORDER BY fs.Timestamp DESC
            """,
            (args.path,),
        )
    ]
    if not rows:
        fail(f"path '{args.path}' not present in any snapshot")
    if args.json:
        emit_rows(rows, [], True, stream=True)
        return 0
    table_rows = [
        {
            "snapshot_id": r["snapshot_id"],
            "timestamp": r["timestamp"],
            "full": r["is_full_backup"],
            "size": human_size(r["size"]),
            "mtime": r["mtime"],
        }
        for r in rows
    ]
    emit_rows(
        table_rows,
        [
            ("snapshot_id", "ID"),
            ("timestamp", "TIMESTAMP"),
            ("full", "FULL"),
            ("size", "SIZE"),
            ("mtime", "MTIME"),
        ],
        False,
    )
    return 0


def cmd_grep(args: argparse.Namespace) -> int:
    conn = open_db(resolve_db_path(args))
    snapshot = resolve_snapshot(conn, parse_snapshot(args.snapshot))
    if snapshot is None:
        fail("no snapshots present in database")

    rows: list[dict] = []
    if args.regex:
        try:
            pattern = re.compile(args.pattern)
        except re.error as exc:
            fail(f"invalid regex {args.pattern!r}: {exc}", EXIT_USAGE)
        cursor = conn.execute(
            """
            SELECT f.Path AS path, bs.Length AS size, fse.Lastmodified AS mtime
            FROM File f
              JOIN FilesetEntry fse ON fse.FileID = f.ID
              JOIN Blockset bs      ON bs.ID = f.BlocksetID
            WHERE fse.FilesetID = ?
            ORDER BY f.Path
            """,
            (snapshot["ID"],),
        )
        for row in cursor:
            if pattern.search(row["path"]) is None:
                continue
            rows.append(
                {"path": row["path"], "size": row["size"], "mtime": row["mtime"]}
            )
    else:
        try:
            fnmatch.translate(args.pattern)
        except re.error as exc:
            fail(f"invalid glob {args.pattern!r}: {exc}", EXIT_USAGE)
        cursor = conn.execute(
            """
            SELECT f.Path AS path, bs.Length AS size, fse.Lastmodified AS mtime
            FROM File f
              JOIN FilesetEntry fse ON fse.FileID = f.ID
              JOIN Blockset bs      ON bs.ID = f.BlocksetID
            WHERE fse.FilesetID = ?
              AND f.Path GLOB ?
            ORDER BY f.Path
            """,
            (snapshot["ID"], args.pattern),
        )
        for row in cursor:
            rows.append(
                {"path": row["path"], "size": row["size"], "mtime": row["mtime"]}
            )

    if args.json:
        emit_rows(
            [
                {"path": r["path"], "size": r["size"], "mtime": iso_utc(r["mtime"])}
                for r in rows
            ],
            [],
            True,
            stream=True,
        )
        return 0
    table_rows = [
        {
            "size": human_size(r["size"]),
            "mtime": iso_utc(r["mtime"]),
            "path": r["path"],
        }
        for r in rows
    ]
    emit_rows(
        table_rows,
        [("size", "SIZE"), ("mtime", "MTIME"), ("path", "PATH")],
        False,
    )
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="duplicati-r2-list",
        description="Read-only path and snapshot queries over Duplicati's local SQLite.",
    )
    parser.add_argument(
        "--db",
        help="Override SQLite path (skips manifest resolution).",
    )
    parser.add_argument(
        "--config",
        help=f"Manifest path (default: $DUPLICATI_R2_CONFIG or {DEFAULT_CONFIG}).",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit machine output (NDJSON for streams, one object for stat).",
    )

    sub = parser.add_subparsers(dest="command", required=True)

    versions = sub.add_parser("versions", help="List snapshots (newest first).")
    versions.add_argument("slug", help="Target slug (manifest .targets.<slug>).")
    versions.set_defaults(func=cmd_versions)

    ls = sub.add_parser("ls", help="List directory children at a snapshot.")
    ls.add_argument("slug")
    ls.add_argument("path", help="Directory path (with or without trailing slash).")
    ls.add_argument(
        "--snapshot", help="Fileset.ID or ISO-8601 timestamp (default: latest)."
    )
    ls.set_defaults(func=cmd_ls)

    stat = sub.add_parser("stat", help="Print metadata for a single file.")
    stat.add_argument("slug")
    stat.add_argument("path")
    stat.add_argument(
        "--snapshot", help="Fileset.ID or ISO-8601 timestamp (default: latest)."
    )
    stat.set_defaults(func=cmd_stat)

    history = sub.add_parser("history", help="List every snapshot containing a path.")
    history.add_argument("slug")
    history.add_argument("path")
    history.set_defaults(func=cmd_history)

    grep = sub.add_parser(
        "grep", help="Path-glob (or regex) over file paths at a snapshot."
    )
    grep.add_argument("slug")
    grep.add_argument(
        "pattern", help="Glob like '*.txt' (default) or regex with --regex."
    )
    grep.add_argument(
        "--regex", action="store_true", help="Interpret pattern as a Python regex."
    )
    grep.add_argument(
        "--snapshot", help="Fileset.ID or ISO-8601 timestamp (default: latest)."
    )
    grep.set_defaults(func=cmd_grep)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
