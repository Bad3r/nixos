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
import json
import os
import re
import sys

# Make the sibling duplicati_r2_common module importable regardless of how the
# script was launched (direct invocation, a $out/bin symlink, $PATH discovery).
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))

from duplicati_r2_common import (
    DEFAULT_CONFIG,
    EXIT_USAGE,
    SYMLINK_BLOCKSET_ID,
    emit_rows,
    exact_match_variants,
    fail,
    human_size,
    iso_utc,
    open_db,
    parse_snapshot,
    resolve_db_path,
    resolve_snapshot,
    set_program_name,
)

set_program_name("duplicati-r2-list")


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
    parent, _ = exact_match_variants(args.path)
    if not parent.endswith("/"):
        parent += "/"
    files = conn.execute(
        """
        SELECT
          SUBSTR(f.Path, ?) AS name,
          bs.Length         AS size,
          fse.Lastmodified  AS mtime,
          f.BlocksetID      AS blockset_id
        FROM File f
          JOIN FilesetEntry fse ON fse.FileID = f.ID
          LEFT JOIN Blockset bs ON bs.ID = f.BlocksetID
        WHERE fse.FilesetID = ?
          AND SUBSTR(f.Path, 1, ?) = ?
          AND f.Path != ?
          AND INSTR(SUBSTR(f.Path, ?), '/') = 0
        ORDER BY name
        """,
        (
            len(parent) + 1,
            snapshot["ID"],
            len(parent),
            parent,
            parent,
            len(parent) + 1,
        ),
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
          AND SUBSTR(f.Path, 1, ?) = ?
          AND INSTR(SUBSTR(f.Path, ?), '/') > 0
        ORDER BY name
        """,
        (
            len(parent) + 1,
            len(parent) + 1,
            snapshot["ID"],
            len(parent),
            parent,
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
                "type": "symlink"
                if f["blockset_id"] == SYMLINK_BLOCKSET_ID
                else "file",
                "size": f["size"],
                "mtime": f["mtime"],
            }
        )
    if args.json:
        emit_rows(
            [
                {
                    "name": r["name"],
                    "type": r["type"],
                    "size": r["size"],
                    "mtime": iso_utc(r["mtime"]) if r["mtime"] is not None else None,
                }
                for r in rows
            ],
            [],
            True,
            stream=True,
        )
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
    qpath, qpath_alt = exact_match_variants(args.path)
    row = conn.execute(
        """
        SELECT
          f.Path           AS path,
          bs.Length        AS size,
          bs.FullHash      AS hash,
          fse.Lastmodified AS mtime
        FROM File f
          JOIN FilesetEntry fse ON fse.FileID = f.ID
          LEFT JOIN Blockset bs ON bs.ID = f.BlocksetID
        WHERE fse.FilesetID = ?
          AND f.Path IN (?, ?)
        """,
        (snapshot["ID"], qpath, qpath_alt),
    ).fetchone()
    if row is None:
        fail(f"path '{args.path}' not in snapshot {snapshot['ID']}")
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
        human = {
            **record,
            "size": human_size(record["size"]),
            "hash": record["hash"] if record["hash"] is not None else "-",
        }
        for key in (
            "path",
            "snapshot_id",
            "snapshot_timestamp",
            "size",
            "hash",
            "mtime",
        ):
            print(f"{key}: {human[key]}")
    return 0


def cmd_history(args: argparse.Namespace) -> int:
    conn = open_db(resolve_db_path(args))
    qpath, qpath_alt = exact_match_variants(args.path)
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
              LEFT JOIN Blockset bs ON bs.ID = f.BlocksetID
            WHERE f.Path IN (?, ?)
            ORDER BY fs.Timestamp DESC
            """,
            (qpath, qpath_alt),
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
              LEFT JOIN Blockset bs ON bs.ID = f.BlocksetID
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
        cursor = conn.execute(
            """
            SELECT f.Path AS path, bs.Length AS size, fse.Lastmodified AS mtime
            FROM File f
              JOIN FilesetEntry fse ON fse.FileID = f.ID
              LEFT JOIN Blockset bs ON bs.ID = f.BlocksetID
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
