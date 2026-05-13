#!/usr/bin/env python3
"""Regression checks for duplicati-r2-extract installCheckPhase."""

from __future__ import annotations

import argparse
import base64
import collections
import contextlib
import errno
import hashlib
import io
import json
import os
import sqlite3
import stat
import struct
import zipfile
from collections.abc import Callable
from pathlib import Path

import duplicati_r2_extract as extract_mod
from duplicati_r2_extract import (
    EXIT_DATA_ERR,
    EXIT_OPEN_ERR,
    EXIT_USAGE,
    BucketLayout,
    BlockRef,
    BlockResolver,
    EncryptedCache,
    ExtractStats,
    Extractor,
    FileEntry,
    FileSource,
    OpenedVolume,
    _atomic_writer,
    _ensure_private_dir,
    _glob_paths,
    _load_manifest_for_layout,
    _resolve_endpoint_url,
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


def expect_exit_stderr_contains(
    code: int, needle: str, fn: Callable[..., object], *args: object
) -> None:
    stderr = io.StringIO()
    with contextlib.redirect_stderr(stderr):
        expect_exit(code, fn, *args)
    assert needle in stderr.getvalue()


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

    cache = EncryptedCache(str(cap_root), 100)

    assert not old.exists()
    assert new.exists()
    assert cache._used_bytes == 60


def check_cache_partial_removal_failure_message(work: Path) -> None:
    cache_root = work / "partial-remove-fail-cache"
    cache_root.mkdir()
    partial = cache_root / "vol1.aes.partial"
    partial.write_bytes(b"stale")
    real_unlink = Path.unlink

    def fail_unlink(self: Path, *args: object, **kwargs: object) -> None:
        if os.fspath(self) == os.fspath(partial):
            raise PermissionError("synthetic stale partial removal failure")
        real_unlink(self, *args, **kwargs)

    Path.unlink = fail_unlink
    try:
        expect_exit_stderr_contains(
            EXIT_OPEN_ERR,
            "failed to remove stale cache partial",
            EncryptedCache,
            str(cache_root),
            1024,
        )
    finally:
        Path.unlink = real_unlink


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
    real_fstat = extract_mod.os.fstat

    class ForeignStat:
        def __init__(self, wrapped: os.stat_result):
            self._wrapped = wrapped
            self.st_mode = wrapped.st_mode
            self.st_uid = os.getuid() + 1

        def __getattr__(self, name: str) -> object:
            return getattr(self._wrapped, name)

    extract_mod.os.fstat = lambda fd: ForeignStat(real_fstat(fd))
    try:
        expect_exit(EXIT_OPEN_ERR, load_env_file, str(env_file))
    finally:
        extract_mod.os.fstat = real_fstat


def check_env_symlink_rejected(work: Path) -> None:
    env_file = work / "real.env"
    env_file.write_text("DUPLICATI_PASSPHRASE=test\n", encoding="utf-8")
    env_file.chmod(0o400)
    env_link = work / "link.env"
    os.symlink(env_file, env_link)

    expect_exit(EXIT_OPEN_ERR, load_env_file, str(env_link))


def _acl_data(entries: list[tuple[int, int, int]]) -> bytes:
    return struct.pack("<I", extract_mod._POSIX_ACL_XATTR_VERSION) + b"".join(
        struct.pack("<HHI", tag, perm, entry_id) for tag, perm, entry_id in entries
    )


def check_env_mode_group_grant_rejected(work: Path) -> None:
    env_file = work / "mode-group.env"
    env_file.write_text("DUPLICATI_PASSPHRASE=test\n", encoding="utf-8")
    env_file.chmod(0o440)
    no_acl_errno = getattr(errno, "ENODATA", None)
    if no_acl_errno is None:
        no_acl_errno = next(iter(extract_mod._NO_ACL_XATTR_ERRNOS))
    real_getxattr = extract_mod.os.getxattr

    def missing_acl(_fd: int, _name: str) -> bytes:
        raise OSError(no_acl_errno, "synthetic missing ACL")

    extract_mod.os.getxattr = missing_acl
    try:
        expect_exit_stderr_contains(
            EXIT_OPEN_ERR,
            "mode 0o440 permits group or world access",
            load_env_file,
            str(env_file),
        )
    finally:
        extract_mod.os.getxattr = real_getxattr


def check_env_acl_mask_allows_named_user_read(work: Path) -> None:
    env_file = work / "acl-readable.env"
    env_file.write_text("DUPLICATI_PASSPHRASE=test\n", encoding="utf-8")
    env_file.chmod(0o440)
    acl = _acl_data(
        [
            (
                extract_mod._ACL_USER_OBJ,
                extract_mod._ACL_READ,
                extract_mod._ACL_UNDEFINED_ID,
            ),
            (extract_mod._ACL_USER, extract_mod._ACL_READ, os.getuid()),
            (extract_mod._ACL_GROUP_OBJ, 0, extract_mod._ACL_UNDEFINED_ID),
            (
                extract_mod._ACL_MASK,
                extract_mod._ACL_READ,
                extract_mod._ACL_UNDEFINED_ID,
            ),
            (extract_mod._ACL_OTHER, 0, extract_mod._ACL_UNDEFINED_ID),
        ]
    )
    real_getxattr = extract_mod.os.getxattr
    extract_mod.os.getxattr = lambda _fd, _name: acl
    try:
        assert load_env_file(str(env_file))["DUPLICATI_PASSPHRASE"] == "test"
    finally:
        extract_mod.os.getxattr = real_getxattr


def check_env_acl_group_grant_rejected(work: Path) -> None:
    env_file = work / "acl-group.env"
    env_file.write_text("DUPLICATI_PASSPHRASE=test\n", encoding="utf-8")
    env_file.chmod(0o440)
    acl = _acl_data(
        [
            (
                extract_mod._ACL_USER_OBJ,
                extract_mod._ACL_READ,
                extract_mod._ACL_UNDEFINED_ID,
            ),
            (
                extract_mod._ACL_GROUP_OBJ,
                extract_mod._ACL_READ,
                extract_mod._ACL_UNDEFINED_ID,
            ),
            (
                extract_mod._ACL_MASK,
                extract_mod._ACL_READ,
                extract_mod._ACL_UNDEFINED_ID,
            ),
            (extract_mod._ACL_OTHER, 0, extract_mod._ACL_UNDEFINED_ID),
        ]
    )
    real_getxattr = extract_mod.os.getxattr
    extract_mod.os.getxattr = lambda _fd, _name: acl
    try:
        expect_exit_stderr_contains(
            EXIT_OPEN_ERR,
            "POSIX ACL group-object entry grants r--",
            load_env_file,
            str(env_file),
        )
    finally:
        extract_mod.os.getxattr = real_getxattr


def check_env_unquoted_values_strip_padding(work: Path) -> None:
    env_file = work / "whitespace.env"
    env_file.write_text(
        (
            "DUPLICATI_PASSPHRASE=secret   \n"
            "R2_S3_ENDPOINT_URL=https://abc.r2.example.com   \n"
            'DOUBLE_QUOTED=" spaced "\n'
            "SINGLE_QUOTED=' padded '\n"
        ),
        encoding="utf-8",
    )
    env_file.chmod(0o400)

    env = load_env_file(str(env_file))

    assert env["DUPLICATI_PASSPHRASE"] == "secret"
    assert env["R2_S3_ENDPOINT_URL"] == "https://abc.r2.example.com"
    assert env["DOUBLE_QUOTED"] == " spaced "
    assert env["SINGLE_QUOTED"] == " padded "


def check_endpoint_host_strips_pasted_scheme() -> None:
    assert (
        _resolve_endpoint_url({"R2_S3_ENDPOINT": "https://abc.r2.example.com/"})
        == "https://abc.r2.example.com"
    )
    assert (
        _resolve_endpoint_url({"R2_S3_ENDPOINT": "HTTPS://abc.r2.example.com/"})
        == "https://abc.r2.example.com"
    )


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
    assert not (cache_root / "vol1.aes.partial").exists()
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


def check_volume_manifest_validation() -> None:
    def zip_bytes(manifest: dict[str, object]) -> bytes:
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w") as zf:
            zf.writestr("manifest", json.dumps(manifest).encode("utf-8"))
        return buf.getvalue()

    valid_manifest = {
        "Blocksize": 1024,
        "BlockHash": "SHA256",
        "FileHash": "SHA256",
    }
    OpenedVolume(
        "valid.dblock.zip.aes",
        zip_bytes(valid_manifest),
        1024,
        "SHA256",
        "SHA256",
    ).close()

    mismatch_manifest = dict(valid_manifest)
    mismatch_manifest["Blocksize"] = 2048
    expect_exit(
        EXIT_DATA_ERR,
        OpenedVolume,
        "mismatch.dblock.zip.aes",
        zip_bytes(mismatch_manifest),
        1024,
        "SHA256",
        "SHA256",
    )


def check_blocklist_lookup_batches_sql_vars() -> None:
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    conn.setlimit(sqlite3.SQLITE_LIMIT_VARIABLE_NUMBER, 999)
    conn.executescript(
        """
        CREATE TABLE Remotevolume (
          ID INTEGER PRIMARY KEY,
          Name TEXT
        );
        CREATE TABLE Block (
          ID INTEGER PRIMARY KEY,
          Hash TEXT,
          Size INTEGER,
          VolumeID INTEGER
        );
        CREATE TABLE BlocksetEntry (
          BlocksetID INTEGER,
          BlockID INTEGER,
          "Index" INTEGER
        );
        CREATE TABLE BlocklistHash (
          BlocksetID INTEGER,
          "Index" INTEGER,
          Hash TEXT
        );
        """
    )
    conn.executemany(
        "INSERT INTO Remotevolume VALUES (?, ?)",
        [
            (1, "list-vol.aes"),
            (2, "content-vol.aes"),
        ],
    )

    def b64(hash_bytes: bytes) -> str:
        return base64.b64encode(hash_bytes).decode("ascii").rstrip("=")

    content_hashes = [
        hashlib.sha256(f"content-{index}".encode("ascii")).digest()
        for index in range(600)
    ]
    blocklist_hash = hashlib.sha256(b"blocklist").digest()
    blocklist_blob = b"".join(content_hashes)
    conn.execute(
        "INSERT INTO Block VALUES (?, ?, ?, ?)",
        (1, b64(blocklist_hash), len(blocklist_blob), 1),
    )
    conn.executemany(
        "INSERT INTO Block VALUES (?, ?, ?, ?)",
        [
            (index + 2, b64(hash_bytes), 1024, 2)
            for index, hash_bytes in enumerate(content_hashes)
        ],
    )
    conn.execute(
        "INSERT INTO BlocklistHash VALUES (?, ?, ?)",
        (777, 0, b64(blocklist_hash)),
    )

    def fetch_block(volume: str, block_hash: bytes) -> bytes:
        assert volume == "list-vol.aes"
        assert block_hash == blocklist_hash
        return blocklist_blob

    resolver = BlockResolver(conn, "SHA256", fetch_block)
    refs = resolver.block_refs(777, len(content_hashes) * 1024)

    assert [ref.block_hash for ref in refs] == content_hashes
    assert {ref.volume_name for ref in refs} == {"content-vol.aes"}
    assert {ref.block_size for ref in refs} == {1024}


def check_blocksetentry_invalid_hash_exit_code() -> None:
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    conn.executescript(
        """
        CREATE TABLE Remotevolume (
          ID INTEGER PRIMARY KEY,
          Name TEXT
        );
        CREATE TABLE Block (
          ID INTEGER PRIMARY KEY,
          Hash TEXT,
          Size INTEGER,
          VolumeID INTEGER
        );
        CREATE TABLE BlocksetEntry (
          BlocksetID INTEGER,
          BlockID INTEGER,
          "Index" INTEGER
        );
        INSERT INTO Remotevolume VALUES (1, 'content-vol.aes');
        INSERT INTO Block VALUES (1, 'not valid base64!', 1024, 1);
        INSERT INTO BlocksetEntry VALUES (777, 1, 0);
        """
    )

    resolver = BlockResolver(conn, "SHA256", lambda _volume, _hash: b"")
    expect_exit(EXIT_DATA_ERR, resolver.block_refs, 777, 1024)


def check_include_pattern_normalization() -> None:
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    conn.executescript(
        """
        CREATE TABLE File (
          ID INTEGER PRIMARY KEY,
          Path TEXT,
          BlocksetID INTEGER
        );
        CREATE TABLE FilesetEntry (
          FilesetID INTEGER,
          FileID INTEGER
        );
        INSERT INTO File VALUES
          (1, '/bankdata/sub/file.torrent', 101),
          (2, '/bankdata/file.torrent', 102),
          (3, '/bankdata/other.bin', 103),
          (4, '/bankdata/sub/', -100),
          (5, '/bankdata/sub/deep/file.torrent', 104);
        INSERT INTO FilesetEntry VALUES
          (7, 1),
          (7, 2),
          (7, 3),
          (7, 4),
          (7, 5);
        """
    )

    def collect(pattern: str) -> list[str]:
        pattern = extract_mod._normalize_include_pattern(pattern)
        matches = _glob_paths(conn, 7, pattern)
        assert iter(matches) is matches
        return list(matches)

    assert collect("*.torrent") == [
        "/bankdata/file.torrent",
        "/bankdata/sub/deep/file.torrent",
        "/bankdata/sub/file.torrent",
    ]
    assert collect("/bankdata/*.torrent") == ["/bankdata/file.torrent"]
    assert collect("bankdata/*.torrent") == ["/bankdata/file.torrent"]
    assert collect("/bankdata/**/*.torrent") == [
        "/bankdata/file.torrent",
        "/bankdata/sub/deep/file.torrent",
        "/bankdata/sub/file.torrent",
    ]
    assert extract_mod._segment_globmatch("/bankdata", "/bankdata/**")
    assert extract_mod._segment_globmatch("/foo", "/**/foo")


def check_include_rejects_output_flag() -> None:
    expect_exit(
        EXIT_USAGE,
        extract_mod.main,
        [
            "test",
            "--include",
            "*.bin",
            "--output",
            "/tmp/out.bin",
            "--output-dir",
            "/tmp/out",
        ],
    )


def check_open_volume_lru() -> None:
    class DummyCache:
        def get_with_status(self, name: str, _fetcher: object) -> tuple[bytes, bool]:
            return b"encrypted-" + name.encode("ascii"), False

    class DummySource:
        def fetch(self, name: str) -> bytes:
            return b"encrypted-" + name.encode("ascii")

    class DummyDecrypter:
        def decrypt(self, encrypted: bytes, _name: str) -> bytes:
            return encrypted

    class DummyOpenedVolume:
        created: list[DummyOpenedVolume] = []

        def __init__(
            self,
            name: str,
            _decrypted: bytes,
            _expected_blocksize: int | None,
            _expected_block_hash: str,
            _expected_file_hash: str,
        ):
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
        extractor.blocksize = 1024
        extractor.block_hash_algo = "SHA256"
        extractor.file_hash_algo = "SHA256"
        extractor._open_volumes = collections.OrderedDict()
        for index in range(extract_mod.MAX_OPEN_VOLUMES + 1):
            extractor._open_volume(f"vol{index}.aes")
        assert len(extractor._open_volumes) == extract_mod.MAX_OPEN_VOLUMES
        assert DummyOpenedVolume.created[0].closed
    finally:
        extract_mod.OpenedVolume = original_opened_volume


def check_open_volume_evicts_corrupt_cache_hit(work: Path) -> None:
    cache_root = work / "corrupt-hit-cache"
    cache_root.mkdir()
    (cache_root / "vol1.aes").write_bytes(b"bad")
    cache = EncryptedCache(str(cache_root), 1024)
    fetches: list[str] = []

    class DummySource:
        def fetch(self, name: str) -> bytes:
            fetches.append(name)
            return b"good"

    class DummyDecrypter:
        def decrypt(self, encrypted: bytes, name: str) -> bytes:
            if encrypted == b"bad":
                raise extract_mod.AesDecryptError(f"bad cache hit for {name}")
            return encrypted

    class DummyOpenedVolume:
        def __init__(
            self,
            name: str,
            decrypted: bytes,
            _expected_blocksize: int | None,
            _expected_block_hash: str,
            _expected_file_hash: str,
        ):
            self.name = name
            self.decrypted = decrypted
            self.closed = False

        def close(self) -> None:
            self.closed = True

    original_opened_volume = extract_mod.OpenedVolume
    extract_mod.OpenedVolume = DummyOpenedVolume
    try:
        extractor = object.__new__(Extractor)
        extractor.cache = cache
        extractor.source = DummySource()
        extractor.decrypter = DummyDecrypter()
        extractor.blocksize = 1024
        extractor.block_hash_algo = "SHA256"
        extractor.file_hash_algo = "SHA256"
        extractor._open_volumes = collections.OrderedDict()

        opened = extractor._open_volume("vol1.aes")

        assert opened.decrypted == b"good"
        assert fetches == ["vol1.aes"]
        assert (cache_root / "vol1.aes").read_bytes() == b"good"
        assert cache._used_bytes == 4
    finally:
        extract_mod.OpenedVolume = original_opened_volume


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--work", required=True, type=Path)
    args = parser.parse_args(argv)

    check_cache_recovery(args.work)
    check_cache_cap_on_startup(args.work)
    check_cache_partial_removal_failure_message(args.work)
    check_volume_name_rejection(args.work)
    check_file_source_requires_absolute_path(args.work)
    check_bucket_layout_uses_raw_subpath()
    check_db_override_still_loads_layout_manifest(args.work)
    check_env_owner_mismatch_fails(args.work)
    check_env_symlink_rejected(args.work)
    check_env_mode_group_grant_rejected(args.work)
    check_env_acl_mask_allows_named_user_read(args.work)
    check_env_acl_group_grant_rejected(args.work)
    check_env_unquoted_values_strip_padding(args.work)
    check_endpoint_host_strips_pasted_scheme()
    check_private_output_dirs(args.work)
    check_sink_partial_cleanup_not_following_symlink(args.work)
    check_cache_partial_symlink_not_followed(args.work)
    check_block_hash_before_sink()
    check_volume_manifest_validation()
    check_blocklist_lookup_batches_sql_vars()
    check_blocksetentry_invalid_hash_exit_code()
    check_include_pattern_normalization()
    check_include_rejects_output_flag()
    check_open_volume_lru()
    check_open_volume_evicts_corrupt_cache_hit(args.work)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
