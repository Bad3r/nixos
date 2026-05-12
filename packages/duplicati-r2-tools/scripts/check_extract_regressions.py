#!/usr/bin/env python3
"""Regression checks for duplicati-r2-extract installCheckPhase."""

from __future__ import annotations

import argparse
import base64
import collections
import hashlib
import json
import os
import stat
from collections.abc import Callable
from pathlib import Path

import duplicati_r2_extract as extract_mod
from duplicati_r2_extract import (
    EXIT_DATA_ERR,
    EXIT_OPEN_ERR,
    EXIT_USAGE,
    BucketLayout,
    BlockRef,
    EncryptedCache,
    ExtractStats,
    Extractor,
    FileEntry,
    FileSource,
    _atomic_writer,
    _ensure_private_dir,
    _load_manifest_for_layout,
    build_source,
    load_env_file,
    resolve_bucket_layout,
)


def expect_exit(code: int, fn: Callable[..., object], *args: object) -> None:
    try:
        fn(*args)
    except SystemExit as exc:
        assert exc.code == code
    else:
        raise AssertionError(f"expected SystemExit({code})")


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
    expect_exit(EXIT_DATA_ERR, FileSource(str(source_root)).fetch, "../secret.aes")


def check_file_source_requires_absolute_path(work: Path) -> None:
    layout = BucketLayout("host", "slug", "bucket", None, "auto")
    expect_exit(EXIT_USAGE, build_source, "file://relative/path", {}, layout)
    expect_exit(EXIT_USAGE, build_source, "file:relative/path", {}, layout)


def check_bucket_layout_uses_raw_subpath() -> None:
    layout = BucketLayout("host", "weekly snapshots", "bucket", None, "auto")
    assert layout.key_prefix == "host/weekly snapshots"


def check_db_override_still_loads_layout_manifest(work: Path) -> None:
    config = work / "layout-manifest.json"
    config.write_text(
        json.dumps(
            {
                "hostname": "manifest-host",
                "bucket": "manifest-bucket",
                "targets": {"test": {"destSubpath": "weekly snapshots"}},
            }
        ),
        encoding="utf-8",
    )
    args = argparse.Namespace(
        slug="test", db=str(work / "copy.sqlite"), config=str(config)
    )

    manifest = _load_manifest_for_layout(args)
    layout = resolve_bucket_layout(args, {}, manifest)

    assert layout.hostname == "manifest-host"
    assert layout.subpath == "weekly snapshots"
    assert layout.bucket == "manifest-bucket"


def check_env_owner_mismatch_fails(work: Path) -> None:
    env_file = work / "foreign.env"
    env_file.write_text("DUPLICATI_PASSPHRASE=test\n", encoding="utf-8")
    env_file.chmod(0o400)
    real_stat = extract_mod.os.stat

    class ForeignStat:
        def __init__(self, wrapped: os.stat_result):
            self._wrapped = wrapped
            self.st_mode = wrapped.st_mode
            self.st_uid = os.getuid() + 1

        def __getattr__(self, name: str) -> object:
            return getattr(self._wrapped, name)

    extract_mod.os.stat = lambda path: ForeignStat(real_stat(path))
    try:
        expect_exit(EXIT_OPEN_ERR, load_env_file, str(env_file))
    finally:
        extract_mod.os.stat = real_stat


def check_private_output_dirs(work: Path) -> None:
    private_target = work / "private-out" / "nested" / "file.txt"
    with _atomic_writer(private_target) as write:
        write(b"x")

    for directory in (work / "private-out", work / "private-out" / "nested"):
        assert stat.S_IMODE(directory.stat().st_mode) == 0o700
    assert stat.S_IMODE(private_target.stat().st_mode) == 0o600

    existing = work / "existing-output-root"
    existing.mkdir()
    existing.chmod(0o750)
    _ensure_private_dir(existing)
    assert stat.S_IMODE(existing.stat().st_mode) == 0o750


def check_sink_partial_cleanup_not_following_symlink(work: Path) -> None:
    output = work / "sink-symlink" / "file.txt"
    output.parent.mkdir()
    victim = work / "sink-victim"
    victim.write_text("unchanged", encoding="utf-8")
    partial = output.with_suffix(output.suffix + ".partial")
    os.symlink(victim, partial)

    with _atomic_writer(output) as write:
        write(b"recovered")
    assert victim.read_text(encoding="utf-8") == "unchanged"
    assert output.read_bytes() == b"recovered"
    assert not partial.exists()


def check_cache_partial_symlink_not_followed(work: Path) -> None:
    cache_root = work / "symlink-cache"
    cache_root.mkdir()
    victim = work / "cache-victim"
    victim.write_text("unchanged", encoding="utf-8")
    os.symlink(victim, cache_root / "vol1.aes.partial")

    cache = EncryptedCache(str(cache_root), 1024)
    assert cache.get("vol1.aes", lambda _name: b"encrypted") == b"encrypted"
    assert victim.read_text(encoding="utf-8") == "unchanged"
    assert (cache_root / "vol1.aes").read_bytes() == b"encrypted"


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
    check_file_source_requires_absolute_path(args.work)
    check_bucket_layout_uses_raw_subpath()
    check_db_override_still_loads_layout_manifest(args.work)
    check_env_owner_mismatch_fails(args.work)
    check_private_output_dirs(args.work)
    check_sink_partial_cleanup_not_following_symlink(args.work)
    check_cache_partial_symlink_not_followed(args.work)
    check_block_hash_before_sink()
    check_open_volume_lru()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
