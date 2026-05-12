#!/usr/bin/env python3
"""Regression checks for duplicati-r2-extract installCheckPhase."""

from __future__ import annotations

import argparse
import base64
import collections
import hashlib
import os
import stat
from pathlib import Path

import duplicati_r2_extract as extract_mod
from duplicati_r2_extract import (
    EXIT_DATA_ERR,
    BlockRef,
    EncryptedCache,
    ExtractStats,
    Extractor,
    FileEntry,
    FileSource,
    _atomic_writer,
)


def check_cache_recovery(work: Path) -> None:
    cache_root = work / "unit-cache"
    seen_fetches: list[str] = []

    def fetch_payload(name: str) -> bytes:
        seen_fetches.append(name)
        return b"payload-" + name.encode("ascii")

    cache = EncryptedCache(str(cache_root), 1024)
    assert cache.get("vol1.aes", fetch_payload) == b"payload-vol1.aes"
    (cache_root / "vol1.aes").unlink()
    assert cache.get("vol1.aes", fetch_payload) == b"payload-vol1.aes"
    assert seen_fetches == ["vol1.aes", "vol1.aes"]


def check_cache_cap_on_startup(work: Path) -> None:
    cap_root = work / "cap-cache"
    cap_root.mkdir()
    old = cap_root / "old.aes"
    new = cap_root / "new.aes"
    old.write_bytes(b"a" * 80)
    new.write_bytes(b"b" * 60)
    os.utime(old, (1, 1))
    os.utime(new, (2, 2))

    EncryptedCache(str(cap_root), 100)

    assert not old.exists()
    assert new.exists()


def check_volume_name_rejection(work: Path) -> None:
    source_root = work / "source-root"
    source_root.mkdir()
    try:
        FileSource(str(source_root)).fetch("../secret.aes")
    except SystemExit as exc:
        assert exc.code == EXIT_DATA_ERR
    else:
        raise AssertionError("path-shaped volume name should fail")


def check_private_output_dirs(work: Path) -> None:
    private_target = work / "private-out" / "nested" / "file.txt"
    with _atomic_writer(private_target) as write:
        write(b"x")

    for directory in (work / "private-out", work / "private-out" / "nested"):
        assert stat.S_IMODE(directory.stat().st_mode) == 0o700
    assert stat.S_IMODE(private_target.stat().st_mode) == 0o600


def check_block_hash_before_sink() -> None:
    expected_hash = hashlib.sha256(b"good").digest()

    class FakeResolver:
        def lookup_file(self, _snapshot_id: int, _path: str) -> FileEntry:
            return FileEntry(
                file_id=1,
                path="/bad.bin",
                blockset_id=1,
                full_size=3,
                full_hash=base64.b64encode(hashlib.sha256(b"bad").digest()).decode(
                    "ascii"
                ),
            )

        def block_refs(
            self, _blockset_id: int, _expected_size: int | None
        ) -> list[BlockRef]:
            return [BlockRef("vol1.aes", expected_hash, 3)]

    extractor = object.__new__(Extractor)
    extractor.block_hash_algo = "SHA256"
    extractor.file_hash_algo = "SHA256"
    extractor.resolver = FakeResolver()

    def fetch_bad_block(volume: str, block_hash: bytes) -> bytes:
        block = b"bad"
        extractor._verify_block_hash(volume, block_hash, block)
        return block

    extractor._fetch_block_bytes = fetch_bad_block
    written: list[bytes] = []
    try:
        extractor.extract_file(1, "/bad.bin", written.append, ExtractStats())
    except SystemExit as exc:
        assert exc.code == EXIT_DATA_ERR
    else:
        raise AssertionError("block hash mismatch should fail")
    assert written == []


def check_open_volume_lru() -> None:
    class DummyCache:
        def get(self, name: str, _fetcher: object) -> bytes:
            return b"encrypted-" + name.encode("ascii")

    class DummySource:
        def fetch(self, name: str) -> bytes:
            return b"encrypted-" + name.encode("ascii")

    class DummyDecrypter:
        def decrypt(self, encrypted: bytes, _name: str) -> bytes:
            return encrypted

    class DummyOpenedVolume:
        created: list[DummyOpenedVolume] = []

        def __init__(self, name: str, _decrypted: bytes):
            self.name = name
            self.closed = False
            self.created.append(self)

        def close(self) -> None:
            self.closed = True

    original_opened_volume = extract_mod.OpenedVolume
    extract_mod.OpenedVolume = DummyOpenedVolume
    try:
        extractor = object.__new__(Extractor)
        extractor.cache = DummyCache()
        extractor.source = DummySource()
        extractor.decrypter = DummyDecrypter()
        extractor._open_volumes = collections.OrderedDict()
        for index in range(extract_mod.MAX_OPEN_VOLUMES + 1):
            extractor._open_volume(f"vol{index}.aes")
        assert len(extractor._open_volumes) == extract_mod.MAX_OPEN_VOLUMES
        assert DummyOpenedVolume.created[0].closed
    finally:
        extract_mod.OpenedVolume = original_opened_volume


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--work", required=True, type=Path)
    args = parser.parse_args(argv)

    check_cache_recovery(args.work)
    check_cache_cap_on_startup(args.work)
    check_volume_name_rejection(args.work)
    check_private_output_dirs(args.work)
    check_block_hash_before_sink()
    check_open_volume_lru()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
