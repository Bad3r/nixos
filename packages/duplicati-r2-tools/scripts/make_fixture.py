#!/usr/bin/env python3
"""Synthesize a tiny Duplicati-format archive + matching SQLite for testing.

Used by ``extract.nix`` ``installCheckPhase`` to produce a self-consistent
fixture without depending on ``duplicati-cli``. The generator writes:

- ``<out>/duplicati-fixture-bXXXX.dblock.zip.aes`` (encrypted dblock zip)
- ``<out>/duplicati-fixture-iXXXX.dindex.zip.aes`` (encrypted dindex zip,
  for shape parity; ``duplicati-r2-extract`` does not currently consume
  dindex but having one matches what R2 actually serves)
- ``<out>/duplicati-fixture-20260101T000000Z.dlist.zip.aes`` (encrypted dlist)
- ``<out>/plaintext/{tiny.txt, medium.bin, big.bin}`` (reference plaintexts
  for byte-for-byte ``cmp`` in tests)
- ``<db>`` SQLite with Configuration/Remotevolume/Fileset/FilesetEntry/
  PathPrefix/FileLookup/File view/Blockset/BlocksetEntry/Block/BlocklistHash
  rows that round-trip through ``duplicati-r2-extract``.

Block sizes are deliberately tiny so the multi-blocklist code path is
exercised by a 200 KiB file: ``blocksize=1024`` and ``hash_size=32`` give
32 hashes per blocklist block, so a 200-block file needs 7 blocklist
blocks.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
import os
import sqlite3
import sys
import zipfile
from dataclasses import dataclass
from pathlib import Path

import pyAesCrypt

BLOCK_SIZE = 1024
DBLOCK_TARGET = 10240  # 10 KiB cap on plaintext content per dblock
HASH_NAME = "SHA256"
HASH_BYTES = 32
PREFIX = "duplicati-fixture"
SLUG = "test"
SNAPSHOT_TS = 1767225600  # 2026-01-01T00:00:00Z


@dataclass
class Block:
    block_id: int
    raw_hash: bytes  # 32-byte SHA256
    payload: bytes
    is_blocklist: bool
    volume_id: int = 0  # filled when allocated to a dblock


@dataclass
class FileSpec:
    path: str  # absolute path with leading slash
    payload: bytes
    blockset_id: int


def b64(raw: bytes) -> str:
    return base64.b64encode(raw).decode("ascii")


def base64url_name(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def manifest_dict() -> dict:
    return {
        "Version": 2,
        "Created": "20260101T000000Z",
        "Encoding": "utf8",
        "Blocksize": BLOCK_SIZE,
        "BlockHash": HASH_NAME,
        "FileHash": HASH_NAME,
        "AppVersion": "fixture-0.1",
    }


def split_blocks(payload: bytes) -> list[bytes]:
    """Split payload into blocksize chunks; the last chunk may be partial."""
    return [payload[i : i + BLOCK_SIZE] for i in range(0, len(payload), BLOCK_SIZE)]


def write_zip_in_memory(entries: list[tuple[str, bytes]]) -> bytes:
    """Build a zip archive in memory with given (name, data) entries.

    Uses ``ZIP_DEFLATED`` to mirror Duplicati's default; ``zipfile.ZipFile``
    on the read side accepts both stored and deflated entries.
    """
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for name, data in entries:
            zf.writestr(name, data)
    return buf.getvalue()


def encrypt_aes(plaintext: bytes, passphrase: str) -> bytes:
    """Wrap plaintext bytes in an AES Crypt v2 envelope."""
    out = io.BytesIO()
    pyAesCrypt.encryptStream(io.BytesIO(plaintext), out, passphrase, 64 * 1024)
    return out.getvalue()


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate a Duplicati test fixture.")
    parser.add_argument("--out", required=True, help="Output directory for .aes files")
    parser.add_argument("--db", required=True, help="Output SQLite path")
    parser.add_argument("--passphrase", required=True, help="Encryption passphrase")
    args = parser.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    plaintext_dir = out / "plaintext"
    plaintext_dir.mkdir(parents=True, exist_ok=True)

    # Deterministic plaintext payloads. Each one is a unique sha256 stream so
    # every blocksize chunk hashes to a distinct content block (avoiding
    # accidental dedup that would collapse the multi-blocklist test case).
    def stream(seed: bytes, size: int) -> bytes:
        buf = bytearray()
        counter = 0
        while len(buf) < size:
            buf.extend(hashlib.sha256(seed + counter.to_bytes(8, "big")).digest())
            counter += 1
        return bytes(buf[:size])

    # File sizes are chosen so each one drives a different code path:
    #   tiny:   50 B    -> 1 content block  (BlocksetEntry, no blocklist)
    #   medium: 4 KiB   -> 4 content blocks (BlocksetEntry, no blocklist)
    #   single: 32 KiB  -> 32 blocks; with the blocklist threshold below the
    #                      hash list (32*32 = 1024 B = BLOCK_SIZE) fits in
    #                      exactly one blocklist block, exercising the
    #                      BlocklistHash path with K=1.
    #   big:    200 KiB -> 200 blocks across 7 blocklist blocks (K>1).
    single_blocklist_size = BLOCK_SIZE * (BLOCK_SIZE // HASH_BYTES)  # 32 KiB

    payloads = {
        "/tiny.txt": stream(b"tiny", 50),
        "/medium.bin": stream(b"medium", 4096),
        "/single.bin": stream(b"single", single_blocklist_size),
        "/big.bin": stream(b"big", 204800),
    }

    files = [
        FileSpec(path="/tiny.txt", payload=payloads["/tiny.txt"], blockset_id=101),
        FileSpec(path="/medium.bin", payload=payloads["/medium.bin"], blockset_id=102),
        FileSpec(path="/single.bin", payload=payloads["/single.bin"], blockset_id=103),
        FileSpec(path="/big.bin", payload=payloads["/big.bin"], blockset_id=104),
    ]

    for spec in files:
        target = plaintext_dir / spec.path.lstrip("/")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(spec.payload)

    # Plan blocks per file.
    # block_pool: map raw_hash -> Block (deduplicated across files).
    block_pool: dict[bytes, Block] = {}
    blocks_for_file: dict[int, list[Block]] = {}  # blockset_id -> ordered content blocks
    blocklists_for_file: dict[int, list[Block]] = {}  # blockset_id -> ordered blocklist blocks

    next_block_id = 1

    def intern_block(payload: bytes, *, is_blocklist: bool = False) -> Block:
        nonlocal next_block_id
        h = hashlib.sha256(payload).digest()
        existing = block_pool.get(h)
        if existing is not None:
            return existing
        b = Block(
            block_id=next_block_id,
            raw_hash=h,
            payload=payload,
            is_blocklist=is_blocklist,
        )
        block_pool[h] = b
        next_block_id += 1
        return b

    HASHES_PER_BLOCKLIST = BLOCK_SIZE // HASH_BYTES  # 32

    for spec in files:
        chunks = split_blocks(spec.payload)
        content_blocks = [intern_block(c) for c in chunks]
        blocks_for_file[spec.blockset_id] = content_blocks
        # Decide if blocklist indirection applies.
        # Real Duplicati uses BlocksetEntry for "small" blocksets and switches
        # to BlocklistHash chains for ones whose hash list spans one or more
        # blocklist blocks. The fixture switches at >= HASHES_PER_BLOCKLIST so
        # a 32-block file lands on exactly K=1 blocklist row (exercising the
        # single-row path), and a 200-block file lands on K=7 (multi-row).
        if len(content_blocks) >= HASHES_PER_BLOCKLIST:
            # Concatenate raw hashes, split into BLOCK_SIZE chunks.
            concat = b"".join(b.raw_hash for b in content_blocks)
            list_payloads = split_blocks(concat)
            blocklist_blocks = [intern_block(p, is_blocklist=True) for p in list_payloads]
            blocklists_for_file[spec.blockset_id] = blocklist_blocks
            # Sentinel: BlocksetEntry empty -> extract.py falls back to BlocklistHash.

    # Allocate blocks to dblock volumes (greedy fill, ~DBLOCK_TARGET payload per dblock).
    dblock_volumes: list[list[Block]] = []
    current: list[Block] = []
    current_size = 0
    for b in block_pool.values():
        if current_size + len(b.payload) > DBLOCK_TARGET and current:
            dblock_volumes.append(current)
            current = []
            current_size = 0
        current.append(b)
        current_size += len(b.payload)
    if current:
        dblock_volumes.append(current)

    # Name dblock volumes (use sequential labels for predictability) and stamp Block.volume_id.
    dblock_names: list[str] = []
    for idx, vol in enumerate(dblock_volumes):
        # Match Duplicati naming convention (b<guid>) but with a sequential
        # label for fixture predictability.
        name = f"{PREFIX}-b{idx:04d}.dblock.zip.aes"
        dblock_names.append(name)
        vol_id = idx + 100  # arbitrary, distinct from block IDs
        for b in vol:
            b.volume_id = vol_id

    # Write each dblock zip + AES.
    passphrase = args.passphrase
    for idx, vol in enumerate(dblock_volumes):
        entries: list[tuple[str, bytes]] = [
            ("manifest", json.dumps(manifest_dict()).encode("utf-8")),
        ]
        for b in vol:
            entries.append((base64url_name(b.raw_hash), b.payload))
        zip_bytes = write_zip_in_memory(entries)
        aes_bytes = encrypt_aes(zip_bytes, passphrase)
        (out / dblock_names[idx]).write_bytes(aes_bytes)

    # Generate matching dindex (one per dblock; vol/<dblock-name> JSON
    # listing the blocks). extract.py does not consume dindex, but the file
    # set on disk now mirrors what R2 stores, so the same fixture is reusable
    # when Cut C lands.
    for idx, vol in enumerate(dblock_volumes):
        dblock_name = dblock_names[idx]
        # Strip the trailing .aes for the JSON pointer (Duplicati references
        # the underlying zip name).
        zip_pointer_name = (
            dblock_name[: -len(".aes")] if dblock_name.endswith(".aes") else dblock_name
        )
        index_payload = {
            "blocks": [{"hash": b64(b.raw_hash), "size": len(b.payload)} for b in vol],
            "volumehash": b64(hashlib.sha256(b"placeholder").digest()),
            "volumesize": 0,
        }
        entries = [
            ("manifest", json.dumps(manifest_dict()).encode("utf-8")),
            (f"vol/{zip_pointer_name}", json.dumps(index_payload).encode("utf-8")),
        ]
        for b in vol:
            if b.is_blocklist:
                entries.append((f"list/{base64url_name(b.raw_hash)}", b.payload))
        zip_bytes = write_zip_in_memory(entries)
        aes_bytes = encrypt_aes(zip_bytes, passphrase)
        index_name = f"{PREFIX}-i{idx:04d}.dindex.zip.aes"
        (out / index_name).write_bytes(aes_bytes)

    # Generate dlist with filelist.json describing the snapshot.
    filelist = []
    for spec in files:
        full_hash = hashlib.sha256(spec.payload).digest()
        if spec.blockset_id in blocklists_for_file:
            entry = {
                "type": "File",
                "path": spec.path,
                "hash": b64(full_hash),
                "size": len(spec.payload),
                "time": "20260101T000000Z",
                "metahash": b64(hashlib.sha256(b"meta").digest()),
                "metasize": 0,
                "blocklists": [b64(b.raw_hash) for b in blocklists_for_file[spec.blockset_id]],
            }
        elif len(blocks_for_file[spec.blockset_id]) == 1:
            entry = {
                "type": "File",
                "path": spec.path,
                "hash": b64(full_hash),
                "size": len(spec.payload),
                "time": "20260101T000000Z",
                "metahash": b64(hashlib.sha256(b"meta").digest()),
                "metasize": 0,
            }
        else:
            entry = {
                "type": "File",
                "path": spec.path,
                "hash": b64(full_hash),
                "size": len(spec.payload),
                "time": "20260101T000000Z",
                "metahash": b64(hashlib.sha256(b"meta").digest()),
                "metasize": 0,
                "blocklisthash": b64(
                    hashlib.sha256(
                        b"".join(b.raw_hash for b in blocks_for_file[spec.blockset_id])
                    ).digest()
                ),
            }
        filelist.append(entry)

    dlist_zip = write_zip_in_memory(
        [
            ("manifest", json.dumps(manifest_dict()).encode("utf-8")),
            ("filelist.json", json.dumps(filelist).encode("utf-8")),
        ]
    )
    dlist_name = f"{PREFIX}-20260101T000000Z.dlist.zip.aes"
    (out / dlist_name).write_bytes(encrypt_aes(dlist_zip, passphrase))

    # Build the SQLite that extract.py will query.
    if os.path.exists(args.db):
        os.unlink(args.db)
    conn = sqlite3.connect(args.db)
    cur = conn.cursor()
    cur.executescript(
        """
        PRAGMA user_version = 19;
        CREATE TABLE Configuration (Key TEXT PRIMARY KEY, Value TEXT);
        CREATE TABLE PathPrefix (ID INTEGER PRIMARY KEY, Prefix TEXT NOT NULL UNIQUE);
        CREATE TABLE FileLookup (
          ID INTEGER PRIMARY KEY,
          PrefixID INTEGER NOT NULL,
          Path TEXT NOT NULL,
          BlocksetID INTEGER,
          MetadataID INTEGER
        );
        CREATE VIEW File AS
          SELECT FileLookup.ID         AS ID,
                 PathPrefix.Prefix || FileLookup.Path AS Path,
                 FileLookup.BlocksetID AS BlocksetID,
                 FileLookup.MetadataID AS MetadataID
          FROM FileLookup JOIN PathPrefix ON FileLookup.PrefixID = PathPrefix.ID;
        CREATE TABLE Blockset (
          ID INTEGER PRIMARY KEY,
          Length INTEGER,
          FullHash TEXT
        );
        CREATE TABLE BlocksetEntry (
          BlocksetID INTEGER,
          "Index" INTEGER,
          BlockID INTEGER,
          PRIMARY KEY (BlocksetID, "Index")
        );
        CREATE TABLE Block (
          ID INTEGER PRIMARY KEY,
          Hash TEXT,
          Size INTEGER,
          VolumeID INTEGER
        );
        CREATE TABLE BlocklistHash (
          BlocksetID INTEGER,
          "Index" INTEGER,
          Hash TEXT,
          PRIMARY KEY (BlocksetID, "Index")
        );
        CREATE TABLE Remotevolume (
          ID INTEGER PRIMARY KEY,
          Name TEXT,
          Type TEXT,
          State TEXT
        );
        CREATE TABLE Fileset (
          ID INTEGER PRIMARY KEY,
          VolumeID INTEGER,
          Timestamp INTEGER,
          IsFullBackup INTEGER
        );
        CREATE TABLE FilesetEntry (
          FilesetID INTEGER,
          FileID INTEGER,
          Lastmodified INTEGER,
          PRIMARY KEY (FilesetID, FileID)
        );
        """
    )

    cur.executemany(
        "INSERT INTO Configuration VALUES (?, ?)",
        [
            ("blocksize", str(BLOCK_SIZE)),
            ("blockhash", HASH_NAME),
            ("filehash", HASH_NAME),
            ("Version", "19"),
        ],
    )
    cur.execute("INSERT INTO PathPrefix VALUES (1, '/')")

    file_id_seq = 1
    fileset_entries = []
    for spec in files:
        rel_name = spec.path.lstrip("/")
        cur.execute(
            "INSERT INTO FileLookup VALUES (?, 1, ?, ?, ?)",
            (file_id_seq, rel_name, spec.blockset_id, file_id_seq + 1000),
        )
        fileset_entries.append((1, file_id_seq, SNAPSHOT_TS))
        file_id_seq += 1

    for spec in files:
        full_hash = hashlib.sha256(spec.payload).digest()
        cur.execute(
            "INSERT INTO Blockset VALUES (?, ?, ?)",
            (spec.blockset_id, len(spec.payload), b64(full_hash)),
        )

    # Remotevolume rows (one per dblock, plus one for the dlist; dindex left
    # off because extract.py does not consume them).
    for idx, name in enumerate(dblock_names):
        cur.execute(
            "INSERT INTO Remotevolume VALUES (?, ?, 'Blocks', 'Verified')",
            (idx + 100, name),
        )
    cur.execute(
        "INSERT INTO Remotevolume VALUES (?, ?, 'Files', 'Verified')",
        (1, dlist_name),
    )

    # Fileset + FilesetEntry rows.
    cur.execute(
        "INSERT INTO Fileset VALUES (1, 1, ?, 1)",
        (SNAPSHOT_TS,),
    )
    cur.executemany(
        "INSERT INTO FilesetEntry VALUES (?, ?, ?)",
        fileset_entries,
    )

    # Block rows.
    for b in block_pool.values():
        cur.execute(
            "INSERT INTO Block VALUES (?, ?, ?, ?)",
            (b.block_id, b64(b.raw_hash), len(b.payload), b.volume_id),
        )

    # BlocksetEntry: only for files NOT in the multi-blocklist path.
    for spec in files:
        if spec.blockset_id in blocklists_for_file:
            continue  # extract.py walks BlocklistHash for these
        for index, b in enumerate(blocks_for_file[spec.blockset_id]):
            cur.execute(
                "INSERT INTO BlocksetEntry VALUES (?, ?, ?)",
                (spec.blockset_id, index, b.block_id),
            )

    # BlocklistHash for the multi-blocklist files.
    for blockset_id, list_blocks in blocklists_for_file.items():
        for index, b in enumerate(list_blocks):
            cur.execute(
                "INSERT INTO BlocklistHash VALUES (?, ?, ?)",
                (blockset_id, index, b64(b.raw_hash)),
            )

    conn.commit()
    conn.close()

    # Summary on stderr (so the build log captures it without polluting stdout).
    summary = {
        "files": [{"path": s.path, "size": len(s.payload)} for s in files],
        "unique_blocks": len(block_pool),
        "dblock_volumes": len(dblock_volumes),
        "dblock_names": dblock_names,
        "dlist_name": dlist_name,
    }
    print(json.dumps(summary, indent=2), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
