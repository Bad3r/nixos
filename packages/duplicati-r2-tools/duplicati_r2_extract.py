#!/usr/bin/env python3
"""duplicati-r2-extract: single-file extract from a Duplicati R2 archive.

Implements Cut B of the design recorded in
docs/drafts/duplicati-r2-readonly-mount-investigation.md. Resolves a path in
the per-target SQLite, fetches only the dblocks that contain the file's
content blocks, decrypts them through the AES Crypt File Format wrapper, and
writes the plaintext to a destination file, stdout, or an output directory
when in glob mode. Encrypted dblocks are cached on disk under an LRU policy;
plaintext never persists outside the operator-chosen sink.
"""

from __future__ import annotations

import argparse
import base64
import binascii
import collections
import contextlib
import errno
import fnmatch
import hashlib
import io
import json
import os
import re
import sqlite3
import stat
import struct
import sys
import time
import urllib.parse
import zipfile
from collections.abc import Iterator
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

# Self-bootstrap: import the sibling duplicati_r2_common module regardless of
# how the script was launched (direct path, $out/bin symlink, $PATH).
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))

from duplicati_r2_common import (  # noqa: E402
    DEFAULT_CONFIG,
    EXIT_DATA_ERR,
    EXIT_OPEN_ERR,
    EXIT_USAGE,
    exact_match_variants,
    fail,
    iso_utc,
    load_manifest,
    open_db,
    parse_snapshot,
    resolve_db_path,
    resolve_snapshot,
    sanitize_slug,
    set_program_name,
)

DEFAULT_ENV_FILE = "/etc/duplicati/r2.env"
DEFAULT_CACHE_BYTES = 1 * 1024 * 1024 * 1024  # 1 GiB
DEFAULT_CACHE_DIR = (
    os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")) + "/duplicati-r2-tools"
)
MAX_OPEN_VOLUMES = 16
SQLITE_BIND_SAFETY_MARGIN = 1

set_program_name("duplicati-r2-extract")


# ---------------------------------------------------------------------------
# Env-file
# ---------------------------------------------------------------------------


_DOTENV_RE = re.compile(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$")
_POSIX_ACL_XATTR = "system.posix_acl_access"
_POSIX_ACL_XATTR_VERSION = 0x0002
_ACL_USER_OBJ = 0x01
_ACL_USER = 0x02
_ACL_GROUP_OBJ = 0x04
_ACL_GROUP = 0x08
_ACL_MASK = 0x10
_ACL_OTHER = 0x20
_ACL_EXECUTE = 0x01
_ACL_WRITE = 0x02
_ACL_READ = 0x04
_ACL_UNDEFINED_ID = 0xFFFFFFFF
_ACL_XATTR_HEADER = struct.Struct("<I")
_ACL_XATTR_ENTRY = struct.Struct("<HHI")
_ACL_TAG_LABELS = {
    _ACL_USER_OBJ: "owner",
    _ACL_USER: "named user",
    _ACL_GROUP_OBJ: "group-object",
    _ACL_GROUP: "named group",
    _ACL_OTHER: "other",
}
_NO_ACL_XATTR_ERRNOS = {
    code
    for code in (
        getattr(errno, "ENODATA", None),
        getattr(errno, "ENOATTR", None),
        getattr(errno, "ENOTSUP", None),
        getattr(errno, "EOPNOTSUPP", None),
    )
    if code is not None
}


def _acl_perm_string(perm: int) -> str:
    return "".join(
        label if perm & bit else "-"
        for bit, label in (
            (_ACL_READ, "r"),
            (_ACL_WRITE, "w"),
            (_ACL_EXECUTE, "x"),
        )
    )


def _acl_entry_label(tag: int, entry_id: int) -> str:
    label = _ACL_TAG_LABELS[tag]
    if tag in {_ACL_USER, _ACL_GROUP}:
        return f"{label} {entry_id}"
    return label


def _posix_acl_insecure_access_reason(acl_data: bytes, path: str) -> str | None:
    if (
        len(acl_data) < _ACL_XATTR_HEADER.size
        or (len(acl_data) - _ACL_XATTR_HEADER.size) % _ACL_XATTR_ENTRY.size
    ):
        fail(f"env file {path} has malformed POSIX ACL data; refusing", EXIT_OPEN_ERR)

    (version,) = _ACL_XATTR_HEADER.unpack_from(acl_data)
    if version != _POSIX_ACL_XATTR_VERSION:
        fail(
            f"env file {path} has unsupported POSIX ACL version {version}; refusing",
            EXIT_OPEN_ERR,
        )

    entries: list[tuple[int, int, int]] = []
    mask_perm: int | None = None
    for offset in range(
        _ACL_XATTR_HEADER.size,
        len(acl_data),
        _ACL_XATTR_ENTRY.size,
    ):
        tag, perm, _entry_id = _ACL_XATTR_ENTRY.unpack_from(acl_data, offset)
        if tag == _ACL_MASK:
            mask_perm = perm
            continue
        elif tag not in {
            _ACL_USER_OBJ,
            _ACL_USER,
            _ACL_GROUP_OBJ,
            _ACL_GROUP,
            _ACL_OTHER,
        }:
            fail(
                f"env file {path} has unknown POSIX ACL tag {tag}; refusing",
                EXIT_OPEN_ERR,
            )
        entries.append((tag, perm, _entry_id))

    for tag, perm, entry_id in entries:
        effective = perm
        if tag in {_ACL_USER, _ACL_GROUP_OBJ, _ACL_GROUP} and mask_perm is not None:
            effective &= mask_perm
        if tag in {_ACL_GROUP_OBJ, _ACL_GROUP, _ACL_OTHER} and effective:
            return (
                f"POSIX ACL {_acl_entry_label(tag, entry_id)} entry grants "
                f"{_acl_perm_string(effective)}"
            )
        if tag == _ACL_USER and effective & (_ACL_WRITE | _ACL_EXECUTE):
            return (
                f"POSIX ACL {_acl_entry_label(tag, entry_id)} entry grants "
                f"{_acl_perm_string(effective)}"
            )
    return None


def _env_file_insecure_access_reason(fd: int, path: str, st_mode: int) -> str | None:
    try:
        acl_data = os.getxattr(fd, _POSIX_ACL_XATTR)
    except OSError as exc:
        if exc.errno in _NO_ACL_XATTR_ERRNOS:
            if st_mode & 0o077:
                return f"mode {oct(st_mode & 0o7777)} permits group or world access"
            return None
        fail(f"failed to inspect env file ACL for {path}: {exc}", EXIT_OPEN_ERR)

    return _posix_acl_insecure_access_reason(acl_data, path)


def load_env_file(path: str) -> dict[str, str]:
    """Parse a dotenv file produced by sops-nix.

    Refuses to read a file whose mode grants any group or world bits, or
    whose owner is neither root nor the invoking user. The Cut B tool is
    meant to be run by an operator listed in
    ``services.duplicati-r2.stateDirReadableBy``; that ACL grants
    ``u:<user>:r--`` on top of the underlying mode-0400 file. A base mode
    widened beyond 0400 (group/world bits set) indicates manual tampering
    and is refused loudly rather than silently sourced; the named-user grant
    travels through the ACL, not through the group class.
    """
    if not path:
        fail(f"env file not found: {path}", EXIT_OPEN_ERR)
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_CLOEXEC", 0)
    try:
        fd = os.open(path, flags)
    except FileNotFoundError:
        fail(f"env file not found: {path}", EXIT_OPEN_ERR)
    except OSError as exc:
        if exc.errno == errno.ELOOP:
            fail(
                f"env file {path} is a symbolic link; O_NOFOLLOW refuses to follow it. "
                "Pass --env-file with the resolved regular-file path.",
                EXIT_OPEN_ERR,
            )
        fail(f"failed to open env file {path}: {exc}", EXIT_OPEN_ERR)

    env: dict[str, str] = {}
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            fail(f"env file {path} is not a regular file; refusing", EXIT_OPEN_ERR)
        insecure_reason = _env_file_insecure_access_reason(fd, path, st.st_mode)
        if insecure_reason is not None:
            fail(
                f"env file {path} grants insecure access: {insecure_reason}; refusing",
                EXIT_OPEN_ERR,
            )
        if st.st_uid not in (0, os.getuid()):
            fail(
                f"env file {path} owned by uid={st.st_uid}, expected 0 or {os.getuid()}; refusing",
                EXIT_OPEN_ERR,
            )
        with os.fdopen(fd, "r", encoding="utf-8") as fh:
            fd = -1
            for raw in fh:
                line = raw.rstrip("\r\n")
                stripped_line = line.strip()
                if not stripped_line or stripped_line.startswith("#"):
                    continue
                m = _DOTENV_RE.match(line)
                if not m:
                    continue
                key, raw_value = m.group(1), m.group(2)
                stripped_value = raw_value.strip()
                if (stripped_value.startswith('"') and stripped_value.endswith('"')) or (
                    stripped_value.startswith("'") and stripped_value.endswith("'")
                ):
                    value = stripped_value[1:-1]
                else:
                    value = stripped_value
                env[key] = value
    finally:
        if fd != -1:
            os.close(fd)
    return env


# ---------------------------------------------------------------------------
# Source transports
# ---------------------------------------------------------------------------


class Source:
    """Abstract object source. Implementations return raw encrypted bytes."""

    def fetch(self, volume_name: str) -> bytes:  # pragma: no cover - interface
        raise NotImplementedError


def validate_volume_name(volume_name: str) -> None:
    if not volume_name or volume_name in {".", ".."} or "/" in volume_name or "\\" in volume_name:
        fail(
            f"refusing volume name with path components: {volume_name!r}",
            EXIT_DATA_ERR,
        )


class FileSource(Source):
    """Reads encrypted volumes from a local mirror directory.

    Used by tests and for forensic work against a bucket rsync'd to local
    disk. Layout matches R2: ``<root>/<volume_name>``. The optional
    ``prefix`` is appended once.
    """

    def __init__(self, root: str, prefix: str = ""):
        base = Path(root)
        if prefix:
            base = base / prefix.strip("/")
        if not base.is_dir():
            fail(f"--source file:// root not a directory: {base}", EXIT_OPEN_ERR)
        self.base = base

    def fetch(self, volume_name: str) -> bytes:
        validate_volume_name(volume_name)
        target = self.base / volume_name
        try:
            return target.read_bytes()
        except FileNotFoundError:
            fail(f"missing volume in file source: {target}", EXIT_OPEN_ERR)
        except OSError as exc:
            fail(f"failed to read {target}: {exc}", EXIT_OPEN_ERR)


class S3Source(Source):
    """Fetches encrypted volumes from an S3-compatible endpoint (R2)."""

    def __init__(
        self,
        endpoint_url: str,
        region: str,
        bucket: str,
        prefix: str,
        access_key: str,
        secret_key: str,
    ):
        try:
            import boto3  # type: ignore
            from botocore.config import Config  # type: ignore
        except ImportError as exc:
            fail(f"boto3 not installed; cannot use S3 source ({exc})", EXIT_OPEN_ERR)
        self._bucket = bucket
        self._prefix = prefix.rstrip("/")
        # R2 region label is "auto" by convention; the endpoint URL identifies
        # the actual datacenter.
        self._client = boto3.client(
            "s3",
            endpoint_url=endpoint_url,
            region_name=region or "auto",
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key,
            config=Config(
                signature_version="s3v4",
                retries={"max_attempts": 5, "mode": "adaptive"},
            ),
        )

    def fetch(self, volume_name: str) -> bytes:
        from botocore.exceptions import ClientError  # type: ignore

        validate_volume_name(volume_name)
        key = f"{self._prefix}/{volume_name}" if self._prefix else volume_name
        try:
            resp = self._client.get_object(Bucket=self._bucket, Key=key)
            return resp["Body"].read()
        except ClientError as exc:  # pragma: no cover - network path
            code = exc.response.get("Error", {}).get("Code", "")
            if code in {"NoSuchKey", "404", "NotFound"}:
                fail(
                    f"missing volume on R2: s3://{self._bucket}/{key}",
                    EXIT_OPEN_ERR,
                )
            fail(
                f"R2 GET failed for s3://{self._bucket}/{key}: {exc}",
                EXIT_OPEN_ERR,
            )
        except Exception as exc:  # pragma: no cover - network path
            fail(
                f"R2 GET failed for s3://{self._bucket}/{key}: {exc}",
                EXIT_OPEN_ERR,
            )


@dataclass
class BucketLayout:
    """Resolved R2 destination matching the backup script's logic.

    Mirrors ``modules/services/duplicati-r2.nix`` so an extract issued
    against the same target hits the same `<host>/<destSubpath>/` prefix
    the backup wrote to. Hostname and per-target destSubpath both honour
    manifest overrides; without those, hostname falls back to
    ``hostname --short`` and destSubpath falls back to the slug.
    """

    hostname: str
    subpath: str
    bucket: str
    endpoint_url: str | None
    region: str

    @property
    def key_prefix(self) -> str:
        # The backup script URL-encodes destSubpath into the s3:// URI; the
        # Duplicati S3 backend URL-decodes the path before issuing object keys.
        # boto3 takes the key as-is, so pass the raw key prefix.
        return f"{self.hostname}/{self.subpath}"


def _short_hostname() -> str:
    """``hostname --short`` equivalent: nodename truncated at first dot."""
    return os.uname().nodename.split(".", 1)[0]


def _resolve_endpoint_url(env: dict[str, str]) -> str | None:
    """Match the backup script's R2_S3_ENDPOINT_URL fallback chain.

    Priority: ``R2_S3_ENDPOINT_URL`` (full URL with scheme) -> bare
    ``R2_S3_ENDPOINT`` hostname (prepend ``https://``) -> derive
    ``https://<R2_ACCOUNT_ID>.r2.cloudflarestorage.com``. Returns None only
    when none of the three are set, in which case the caller surfaces a
    missing-credential error.
    """
    url = env.get("R2_S3_ENDPOINT_URL")
    if url:
        return url
    host = env.get("R2_S3_ENDPOINT")
    if host:
        host = re.sub(r"^https?://", "", host.strip(), flags=re.IGNORECASE).rstrip("/")
        return f"https://{host}"
    account = env.get("R2_ACCOUNT_ID")
    if account:
        return f"https://{account}.r2.cloudflarestorage.com"
    return None


def resolve_bucket_layout(
    args: argparse.Namespace,
    env: dict[str, str],
    manifest: dict | None,
) -> BucketLayout:
    """Compute the (hostname, destSubpath, bucket, endpoint, region) tuple.

    Manifest fields (`hostname`, `targets.<slug>.destSubpath`, `bucket`)
    take precedence over env-file values; env values take precedence over
    derived defaults. ``DUPLICATI_R2_HOST`` is an explicit operator-set
    override that wins over everything (documented escape hatch for
    operator workflows that don't have manifest read access).
    """
    slug = args.slug

    # destSubpath: per-target manifest override -> slug.
    subpath = slug
    if isinstance(manifest, dict):
        targets = manifest.get("targets")
        if isinstance(targets, dict):
            target = targets.get(slug)
            if isinstance(target, dict):
                if isinstance(target.get("destSubpath"), str) and target["destSubpath"]:
                    subpath = target["destSubpath"]

    # hostname: explicit env override -> manifest -> hostname --short.
    hostname = os.environ.get("DUPLICATI_R2_HOST") or ""
    if not hostname and isinstance(manifest, dict):
        manifest_host = manifest.get("hostname")
        if isinstance(manifest_host, str) and manifest_host:
            hostname = manifest_host
    if not hostname:
        hostname = _short_hostname()

    # bucket: manifest -> env file -> documented default.
    bucket = ""
    if isinstance(manifest, dict):
        manifest_bucket = manifest.get("bucket")
        if isinstance(manifest_bucket, str) and manifest_bucket:
            bucket = manifest_bucket
    if not bucket:
        bucket = env.get("R2_BUCKET", "") or "duplicati-nixos-backups"

    return BucketLayout(
        hostname=hostname,
        subpath=subpath,
        bucket=bucket,
        endpoint_url=_resolve_endpoint_url(env),
        region=env.get("R2_REGION") or "auto",
    )


def build_source(
    source_arg: str | None,
    env: dict[str, str],
    layout: BucketLayout,
) -> Source:
    arg = source_arg or "s3://default"
    parsed = urllib.parse.urlparse(arg)
    if parsed.scheme == "file":
        if parsed.netloc:
            fail(
                f"--source file:// requires an absolute path (got {arg!r}; did you mean 'file:///{parsed.netloc}{parsed.path}'?)",
                EXIT_USAGE,
            )
        if not os.path.isabs(parsed.path):
            fail(
                f"--source file:// requires an absolute path (got {arg!r})",
                EXIT_USAGE,
            )
        return FileSource(parsed.path)
    if parsed.scheme in ("s3", ""):
        access = env.get("AWS_ACCESS_KEY_ID")
        secret = env.get("AWS_SECRET_ACCESS_KEY")
        missing = [
            name
            for name, val in (
                (
                    "R2_S3_ENDPOINT_URL or R2_S3_ENDPOINT or R2_ACCOUNT_ID",
                    layout.endpoint_url,
                ),
                ("AWS_ACCESS_KEY_ID", access),
                ("AWS_SECRET_ACCESS_KEY", secret),
                ("bucket (manifest .bucket or R2_BUCKET)", layout.bucket),
            )
            if not val
        ]
        if missing:
            fail(
                f"cannot construct R2 client; missing: {', '.join(missing)}",
                EXIT_OPEN_ERR,
            )
        # Narrowed by the missing-field check above.
        assert layout.endpoint_url is not None
        assert access is not None
        assert secret is not None
        return S3Source(
            layout.endpoint_url,
            layout.region,
            layout.bucket,
            layout.key_prefix,
            access,
            secret,
        )
    fail(f"unsupported --source scheme: {parsed.scheme!r}", EXIT_USAGE)


# ---------------------------------------------------------------------------
# Encrypted-dblock cache
# ---------------------------------------------------------------------------


class EncryptedCache:
    """LRU cache of encrypted dblocks on disk.

    Keys are volume names; values are absolute paths to the cached encrypted
    bytes. The cache enforces a byte cap (`cap_bytes`); insertion evicts the
    least-recently-used entries until the new entry fits. ``cap_bytes == 0``
    disables caching: ``get`` always re-fetches and never persists.
    """

    def __init__(self, root: str, cap_bytes: int):
        self.root = Path(root)
        self.cap_bytes = cap_bytes
        self.bytes_fetched = 0
        self.fetches = 0
        self._order: collections.OrderedDict[str, int] = collections.OrderedDict()
        self._used_bytes = 0
        if cap_bytes > 0:
            self._ensure_root()
            self._scan_existing()

    def _ensure_root(self) -> None:
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        # mkdir(mode=...) only applies on creation; an existing cache root with
        # looser bits stays loose. Re-chmod every activation and after external
        # deletion/recreation so the documented 0700 invariant holds.
        try:
            os.chmod(self.root, 0o700)
        except PermissionError:
            # Cache root owned by someone else: surface the broken invariant,
            # do not silently use a world-readable cache.
            fail(
                f"cache root {self.root} not chmod-able to 0700 by uid={os.getuid()}",
                EXIT_OPEN_ERR,
            )

    def _scan_existing(self) -> None:
        entries: list[tuple[float, str, int]] = []
        for entry in self.root.iterdir():
            try:
                if entry.name.endswith(".partial"):
                    try:
                        entry.unlink()
                    except FileNotFoundError:
                        pass
                    except OSError as exc:
                        fail(
                            f"failed to remove stale cache partial {entry}: {exc}",
                            EXIT_OPEN_ERR,
                        )
                    continue
                if not entry.is_file():
                    continue
                st = entry.stat()
            except FileNotFoundError:
                continue
            except OSError as exc:
                fail(f"failed to inspect cache entry {entry}: {exc}", EXIT_OPEN_ERR)
            entries.append((st.st_mtime, entry.name, st.st_size))
        for _mtime, name, size in sorted(entries):
            self._remember(name, size)
        self._evict_until_room(0)

    def _remember(self, volume_name: str, size: int) -> None:
        previous = self._order.get(volume_name)
        if previous is not None:
            self._used_bytes -= previous
        self._order[volume_name] = size
        self._used_bytes += size

    def _forget(self, volume_name: str) -> bool:
        size = self._order.pop(volume_name, None)
        if size is None:
            return False
        self._used_bytes -= size
        return True

    def _evict_until_room(self, incoming_size: int) -> None:
        while self._used_bytes + incoming_size > self.cap_bytes and self._order:
            name, n = self._order.popitem(last=False)
            try:
                (self.root / name).unlink()
            except FileNotFoundError:
                pass
            except OSError as exc:
                fail(
                    f"failed to evict cached volume {self.root / name}: {exc}",
                    EXIT_OPEN_ERR,
                )
            self._used_bytes -= n

    def evict(self, volume_name: str) -> bool:
        validate_volume_name(volume_name)
        known = self._forget(volume_name)
        removed = False
        try:
            (self.root / volume_name).unlink()
            removed = True
        except FileNotFoundError:
            pass
        except OSError as exc:
            fail(
                f"failed to evict cached volume {self.root / volume_name}: {exc}",
                EXIT_OPEN_ERR,
            )
        return known or removed

    def get(self, volume_name: str, fetcher: Callable[[str], bytes]) -> bytes:
        data, _cache_hit = self.get_with_status(volume_name, fetcher)
        return data

    def get_with_status(
        self,
        volume_name: str,
        fetcher: Callable[[str], bytes],
    ) -> tuple[bytes, bool]:
        validate_volume_name(volume_name)
        if self.cap_bytes <= 0:
            data = fetcher(volume_name)
            self.bytes_fetched += len(data)
            self.fetches += 1
            return data, False
        if volume_name in self._order:
            # Touch: move to end (most recently used).
            self._order.move_to_end(volume_name)
            try:
                return (self.root / volume_name).read_bytes(), True
            except FileNotFoundError:
                self._forget(volume_name)
            except OSError as exc:
                fail(
                    f"failed to read cached volume {self.root / volume_name}: {exc}",
                    EXIT_OPEN_ERR,
                )
        data = fetcher(volume_name)
        self.bytes_fetched += len(data)
        self.fetches += 1
        # Evict LRU until the new entry fits.
        size = len(data)
        if size > self.cap_bytes:
            # Single object exceeds cache cap; bypass cache for it.
            return data, False
        self._evict_until_room(size)
        self._ensure_root()
        target = self.root / volume_name
        tmp = target.with_suffix(target.suffix + ".partial")
        try:
            tmp.unlink()
        except FileNotFoundError:
            pass
        except OSError as exc:
            fail(f"failed to remove stale cache partial {tmp}: {exc}", EXIT_OPEN_ERR)
        # Atomic create at mode 0600. O_EXCL and O_NOFOLLOW refuse planted
        # partials and final-component symlinks instead of truncating through
        # them.
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
        try:
            fd = os.open(str(tmp), flags, 0o600)
        except FileExistsError:
            fail(f"cache partial already exists: {tmp}", EXIT_OPEN_ERR)
        except OSError as exc:
            fail(f"failed to create cache partial {tmp}: {exc}", EXIT_OPEN_ERR)
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        os.replace(tmp, target)
        self._remember(volume_name, size)
        return data, False


# ---------------------------------------------------------------------------
# AES decrypter
# ---------------------------------------------------------------------------


class AesDecryptError(Exception):
    pass


class AesDecrypter:
    def __init__(self, passphrase: str):
        if not passphrase:
            fail("empty passphrase", EXIT_USAGE)
        self.passphrase = passphrase
        try:
            import pyAesCrypt  # type: ignore
        except ImportError as exc:
            fail(f"pyAesCrypt not installed: {exc}", EXIT_OPEN_ERR)
        self._mod = pyAesCrypt

    def decrypt(self, encrypted: bytes, volume_name: str) -> bytes:
        plain = io.BytesIO()
        try:
            self._mod.decryptStream(io.BytesIO(encrypted), plain, self.passphrase, 64 * 1024)
        except ValueError as exc:
            # pyAesCrypt raises ValueError for HMAC mismatch, wrong password,
            # or any "corrupted" failure mode; all of those are data errors,
            # not user errors. Surface the message verbatim alongside the
            # offending volume name (loud-failure contract per docs).
            raise AesDecryptError(f"AES decrypt failed for {volume_name}: {exc}") from exc
        return plain.getvalue()


# ---------------------------------------------------------------------------
# Zip volume reader
# ---------------------------------------------------------------------------


_HASH_BYTES_BY_NAME = {
    "SHA256": 32,
    "SHA1": 20,
    "MD5": 16,
    "SHA512": 64,
}


def base64url_name(hash_bytes: bytes) -> str:
    return base64.urlsafe_b64encode(hash_bytes).rstrip(b"=").decode("ascii")


def decode_db_hash(value: str | None, field: str) -> bytes:
    if not value:
        fail(f"{field} is empty; DB likely corrupt", EXIT_DATA_ERR)
    try:
        return base64.b64decode(value + "=" * (-len(value) % 4), validate=True)
    except binascii.Error as exc:
        fail(
            f"{field} {value!r} is not valid base64 ({exc}); DB likely corrupt",
            EXIT_DATA_ERR,
        )


class OpenedVolume:
    """In-memory zip view of a decrypted dblock/dindex/dlist."""

    def __init__(
        self,
        name: str,
        decrypted: bytes,
        expected_blocksize: int | None,
        expected_block_hash: str,
        expected_file_hash: str,
    ):
        self.name = name
        self._buf = io.BytesIO(decrypted)
        try:
            self._zip = zipfile.ZipFile(self._buf)
        except zipfile.BadZipFile as exc:
            fail(f"{name}: not a zip after decrypt: {exc}", EXIT_DATA_ERR)
        try:
            with self._zip.open("manifest") as fh:
                self.manifest = json.loads(fh.read().decode("utf-8"))
        except KeyError:
            fail(f"{name}: missing manifest entry inside zip", EXIT_DATA_ERR)
        except json.JSONDecodeError as exc:
            fail(f"{name}: manifest is not valid JSON: {exc}", EXIT_DATA_ERR)
        self._validate_manifest(
            expected_blocksize,
            expected_block_hash,
            expected_file_hash,
        )

    def _validate_manifest(
        self,
        expected_blocksize: int | None,
        expected_block_hash: str,
        expected_file_hash: str,
    ) -> None:
        if not isinstance(self.manifest, dict):
            fail(f"{self.name}: manifest is not a JSON object", EXIT_DATA_ERR)
        if expected_blocksize is not None:
            try:
                actual_blocksize = int(self.manifest.get("Blocksize"))
            except (TypeError, ValueError):
                fail(
                    f"{self.name}: manifest Blocksize {self.manifest.get('Blocksize')!r} is invalid",
                    EXIT_DATA_ERR,
                )
            if actual_blocksize != expected_blocksize:
                fail(
                    f"{self.name}: manifest Blocksize {actual_blocksize} does not match DB blocksize {expected_blocksize}",
                    EXIT_DATA_ERR,
                )
        for key, expected in (
            ("BlockHash", expected_block_hash),
            ("FileHash", expected_file_hash),
        ):
            actual = self.manifest.get(key)
            if not isinstance(actual, str) or actual.upper() != expected.upper():
                fail(
                    f"{self.name}: manifest {key} {actual!r} does not match DB {key} {expected!r}",
                    EXIT_DATA_ERR,
                )

    def block_bytes(self, block_hash: bytes) -> bytes:
        entry = base64url_name(block_hash)
        try:
            with self._zip.open(entry) as fh:
                return fh.read()
        except KeyError:
            fail(
                f"{self.name}: missing block entry {entry} (hash {block_hash.hex()})",
                EXIT_DATA_ERR,
            )

    def close(self) -> None:
        # zipfile.ZipFile.close raises only on already-broken state; nothing
        # downstream cares once we are tearing down.
        try:
            self._zip.close()
        except (zipfile.BadZipFile, OSError):
            pass


# ---------------------------------------------------------------------------
# Block planning + extraction
# ---------------------------------------------------------------------------


@dataclass
class FileEntry:
    file_id: int
    path: str
    blockset_id: int
    full_size: int | None
    full_hash: str | None


@dataclass
class BlockRef:
    """One content block to fetch + concatenate, in stream order."""

    volume_name: str
    block_hash: bytes
    block_size: int


@dataclass
class ExtractStats:
    plaintext_size: int = 0
    dblocks_touched: set[str] = field(default_factory=set)


class BlockResolver:
    """Translates ``(snapshot_id, path)`` to an ordered iterable of BlockRef.

    Three code paths:

    - small file: ``BlocksetEntry`` is populated and a single SQL join yields
      every content block in order. This is the canonical query in §3.2 of
      the design draft.
    - very large file (``BlocksetEntry`` is empty for the blockset):
      ``BlocklistHash`` enumerates K blocklist blocks; each blocklist block
      is itself a content block that holds the concatenation of
      ``hash_size``-byte content-block hashes. Walk the blocklist blocks in
      Index order, fetch each, decode it, then look up each content block
      via ``Block.Hash``.
    """

    def __init__(
        self,
        conn: sqlite3.Connection,
        block_hash_algo: str,
        fetch_block: Callable[[str, bytes], bytes],
    ):
        self.conn = conn
        size = _HASH_BYTES_BY_NAME.get(block_hash_algo.upper())
        if not size:
            fail(
                f"unsupported BlockHash algorithm: {block_hash_algo!r}",
                EXIT_DATA_ERR,
            )
        self.hash_size: int = size
        self._fetch_block = fetch_block

    def _block_lookup_hash_batch_size(self) -> int:
        variable_limit = self.conn.getlimit(sqlite3.SQLITE_LIMIT_VARIABLE_NUMBER)
        # Each content-block hash is looked up in padded and unpadded base64
        # forms, so split by raw hashes and keep both encodings under SQLite's
        # per-statement bind-variable cap.
        return max(1, (variable_limit - SQLITE_BIND_SAFETY_MARGIN) // 2)

    def lookup_file(self, snapshot_id: int, path: str) -> FileEntry:
        qpath, qpath_alt = exact_match_variants(path)
        row = self.conn.execute(
            """
            SELECT
              f.ID         AS file_id,
              f.Path       AS path,
              f.BlocksetID AS blockset_id,
              bs.Length    AS size,
              bs.FullHash  AS full_hash
            FROM File f
              JOIN FilesetEntry fse ON fse.FileID = f.ID
              LEFT JOIN Blockset bs ON bs.ID = f.BlocksetID
            WHERE fse.FilesetID = ?
              AND f.Path IN (?, ?)
            """,
            (snapshot_id, qpath, qpath_alt),
        ).fetchone()
        if row is None:
            fail(
                f"path '{path}' not in snapshot {snapshot_id}",
                EXIT_OPEN_ERR,
            )
        if row["blockset_id"] is None or row["blockset_id"] < 0:
            fail(
                f"path '{path}' resolves to a non-file entry (BlocksetID={row['blockset_id']!r}); use ls/stat instead",
                EXIT_USAGE,
            )
        return FileEntry(
            file_id=row["file_id"],
            path=row["path"],
            blockset_id=row["blockset_id"],
            full_size=row["size"],
            full_hash=row["full_hash"],
        )

    def block_refs(self, blockset_id: int, expected_size: int | None = None) -> list[BlockRef]:
        """Resolve a blockset's content blocks in stream order.

        ``expected_size`` is the file's plaintext length from
        ``Blockset.Length``; passing ``0`` short-circuits the lookup for
        zero-byte files (which legitimately have neither ``BlocksetEntry``
        nor ``BlocklistHash`` rows).
        """
        if expected_size == 0:
            return []

        # Path 1: BlocksetEntry covers the whole blockset.
        rows = self.conn.execute(
            """
            SELECT b.Hash AS hash, b.Size AS size, rv.Name AS volume
            FROM BlocksetEntry be
              JOIN Block b         ON b.ID = be.BlockID
              JOIN Remotevolume rv ON rv.ID = b.VolumeID
            WHERE be.BlocksetID = ?
            ORDER BY be."Index"
            """,
            (blockset_id,),
        ).fetchall()
        if rows:
            return [
                BlockRef(
                    volume_name=r["volume"],
                    block_hash=decode_db_hash(r["hash"], "Block.Hash"),
                    block_size=r["size"],
                )
                for r in rows
            ]

        # Path 2: BlocklistHash chain.
        list_rows = self.conn.execute(
            """
            SELECT bh.Hash AS list_hash, rv.Name AS list_volume
            FROM BlocklistHash bh
              JOIN Block b         ON b.Hash = bh.Hash
              JOIN Remotevolume rv ON rv.ID = b.VolumeID
            WHERE bh.BlocksetID = ?
            ORDER BY bh."Index"
            """,
            (blockset_id,),
        ).fetchall()
        if not list_rows:
            fail(
                f"blockset {blockset_id} has no BlocksetEntry and no BlocklistHash rows",
                EXIT_DATA_ERR,
            )
        # Look up each content block by hash.
        content_block_hashes: list[bytes] = []
        for lr in list_rows:
            list_hash_bytes = decode_db_hash(lr["list_hash"], "BlocklistHash.Hash")
            blob = self._fetch_block(lr["list_volume"], list_hash_bytes)
            if len(blob) % self.hash_size != 0:
                fail(
                    f"blocklist block {lr['list_hash']} length {len(blob)} not a multiple of hash size {self.hash_size}",
                    EXIT_DATA_ERR,
                )
            for i in range(0, len(blob), self.hash_size):
                content_block_hashes.append(blob[i : i + self.hash_size])

        if not content_block_hashes:
            fail(
                f"blockset {blockset_id} BlocklistHash rows produced no content hashes",
                EXIT_DATA_ERR,
            )
        unique_hashes = list(dict.fromkeys(content_block_hashes))
        block_rows: list[sqlite3.Row] = []
        batch_size = self._block_lookup_hash_batch_size()
        for offset in range(0, len(unique_hashes), batch_size):
            hash_batch = unique_hashes[offset : offset + batch_size]
            b64_set = {
                encoded
                for h in hash_batch
                for encoded in (
                    base64.b64encode(h).decode("ascii"),
                    base64.b64encode(h).decode("ascii").rstrip("="),
                )
            }
            placeholders = ",".join("?" for _ in b64_set)
            block_rows.extend(
                self.conn.execute(
                    f"""
                    SELECT b.ID AS block_id, b.Hash AS hash, b.Size AS size,
                           rv.Name AS volume, rv.ID AS rv_id
                    FROM Block b
                      JOIN Remotevolume rv ON rv.ID = b.VolumeID
                    WHERE b.Hash IN ({placeholders})
                    ORDER BY rv.ID, b.ID
                    """,
                    tuple(sorted(b64_set)),
                ).fetchall()
            )
        block_index: dict[bytes, tuple[str, int]] = {}
        for row in block_rows:
            raw_hash = decode_db_hash(row["hash"], "Block.Hash")
            block_index.setdefault(raw_hash, (row["volume"], row["size"]))

        refs: list[BlockRef] = []
        for h in content_block_hashes:
            hit = block_index.get(h)
            if hit is None:
                fail(
                    f"blocklist references hash {h.hex()} not present in Block table",
                    EXIT_DATA_ERR,
                )
            volume, size = hit
            refs.append(BlockRef(volume_name=volume, block_hash=h, block_size=size))
        return refs


class Extractor:
    """Drives the per-file fetch + decrypt + zip-extract pipeline."""

    def __init__(
        self,
        conn: sqlite3.Connection,
        source: Source,
        cache: EncryptedCache,
        decrypter: AesDecrypter,
        blocksize: int | None,
        block_hash_algo: str,
        file_hash_algo: str,
    ):
        self.conn = conn
        self.source = source
        self.cache = cache
        self.decrypter = decrypter
        self.blocksize = blocksize
        self.block_hash_algo = block_hash_algo.upper()
        self.file_hash_algo = file_hash_algo.upper()
        self._open_volumes: collections.OrderedDict[str, OpenedVolume] = collections.OrderedDict()
        self.resolver = BlockResolver(conn, block_hash_algo, self._fetch_block_bytes)

    def _open_volume(self, volume_name: str) -> OpenedVolume:
        cached = self._open_volumes.get(volume_name)
        if cached is not None:
            self._open_volumes.move_to_end(volume_name)
            return cached
        encrypted, cache_hit = self.cache.get_with_status(volume_name, self.source.fetch)
        try:
            decrypted = self.decrypter.decrypt(encrypted, volume_name)
        except AesDecryptError as exc:
            if not cache_hit or not self.cache.evict(volume_name):
                fail(str(exc), EXIT_DATA_ERR)
            encrypted, _cache_hit = self.cache.get_with_status(
                volume_name,
                self.source.fetch,
            )
            try:
                decrypted = self.decrypter.decrypt(encrypted, volume_name)
            except AesDecryptError as retry_exc:
                fail(str(retry_exc), EXIT_DATA_ERR)
        vol = OpenedVolume(
            volume_name,
            decrypted,
            self.blocksize,
            self.block_hash_algo,
            self.file_hash_algo,
        )
        self._open_volumes[volume_name] = vol
        while len(self._open_volumes) > MAX_OPEN_VOLUMES:
            _name, evicted = self._open_volumes.popitem(last=False)
            evicted.close()
        return vol

    def _fetch_block_bytes(self, volume_name: str, block_hash: bytes) -> bytes:
        vol = self._open_volume(volume_name)
        block = vol.block_bytes(block_hash)
        self._verify_block_hash(volume_name, block_hash, block)
        return block

    def _verify_block_hash(self, volume_name: str, block_hash: bytes, block: bytes) -> None:
        try:
            digest = hashlib.new(self.block_hash_algo)
        except ValueError as exc:
            fail(
                f"unsupported BlockHash algorithm: {self.block_hash_algo!r} ({exc})",
                EXIT_DATA_ERR,
            )
        digest.update(block)
        if digest.digest() != block_hash:
            fail(
                f"block hash mismatch for {base64url_name(block_hash)} from {volume_name}: computed {digest.hexdigest()}, expected {block_hash.hex()}",
                EXIT_DATA_ERR,
            )

    def extract_file(
        self,
        snapshot_id: int,
        abs_path: str,
        sink_writer: Callable[[bytes], object],
        stats: ExtractStats,
    ) -> None:
        entry = self.resolver.lookup_file(snapshot_id, abs_path)
        refs = self.resolver.block_refs(entry.blockset_id, entry.full_size)
        if not refs:
            # Zero-byte file: opener still needs to create the destination,
            # but there is nothing to fetch, decrypt, hash, or write.
            return
        digest = hashlib.new(self.file_hash_algo) if self.file_hash_algo else None
        bytes_written = 0
        for ref in refs:
            block = self._fetch_block_bytes(ref.volume_name, ref.block_hash)
            if len(block) != ref.block_size:
                fail(
                    f"block {base64url_name(ref.block_hash)} from {ref.volume_name} has size {len(block)}, expected {ref.block_size}",
                    EXIT_DATA_ERR,
                )
            stats.dblocks_touched.add(ref.volume_name)
            sink_writer(block)
            if digest is not None:
                digest.update(block)
            bytes_written += len(block)
        if entry.full_size is not None and bytes_written != entry.full_size:
            fail(
                f"size mismatch for {abs_path}: wrote {bytes_written}, Blockset.Length={entry.full_size}",
                EXIT_DATA_ERR,
            )
        if digest is not None and entry.full_hash:
            try:
                expected = base64.b64decode(entry.full_hash + "=" * (-len(entry.full_hash) % 4))
            except binascii.Error as exc:
                fail(
                    f"Blockset.FullHash for {abs_path} is not valid base64 ({exc}); DB likely corrupt",
                    EXIT_DATA_ERR,
                )
            if digest.digest() != expected:
                fail(
                    f"FullHash mismatch for {abs_path}: computed {digest.hexdigest()}, expected {expected.hex()}",
                    EXIT_DATA_ERR,
                )
        stats.plaintext_size += bytes_written

    def close(self) -> None:
        for vol in self._open_volumes.values():
            vol.close()
        self._open_volumes.clear()


# ---------------------------------------------------------------------------
# Output sinks
# ---------------------------------------------------------------------------


def _chmod_private_dir(path: Path) -> None:
    try:
        os.chmod(path, 0o700)
    except PermissionError:
        fail(
            f"directory {path} not chmod-able to 0700 by uid={os.getuid()}",
            EXIT_OPEN_ERR,
        )


def _ensure_private_dir(path: Path) -> None:
    missing: list[Path] = []
    cursor = path
    while not cursor.exists():
        missing.append(cursor)
        parent = cursor.parent
        if parent == cursor:
            break
        cursor = parent

    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    if not path.is_dir():
        fail(f"output parent {path} is not a directory", EXIT_USAGE)

    for directory in missing:
        if directory.is_dir():
            _chmod_private_dir(directory)


@contextlib.contextmanager
def _atomic_writer(dest: Path):
    """Yield a writer for ``dest``; commit-on-success, unlink-on-failure.

    Stages bytes through a sibling ``<dest>.partial`` file (mode 0600) and
    atomically renames into place only after the body completes without
    raising. If the body raises (including ``SystemExit`` from ``fail()``),
    the partial file is closed and unlinked so a glob-mode operator does
    not have to clean up after a mid-batch failure.
    """
    _ensure_private_dir(dest.parent)
    tmp = dest.with_suffix(dest.suffix + ".partial")
    try:
        tmp.unlink()
    except FileNotFoundError:
        pass
    except OSError as exc:
        fail(f"failed to remove stale output partial {tmp}: {exc}", EXIT_OPEN_ERR)
    # Atomic creation at mode 0600. O_EXCL and O_NOFOLLOW refuse planted
    # partials and final-component symlinks instead of truncating through them.
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    try:
        fd = os.open(str(tmp), flags, 0o600)
    except FileExistsError:
        fail(f"temporary output path already exists: {tmp}", EXIT_OPEN_ERR)
    except OSError as exc:
        fail(f"failed to create temporary output path {tmp}: {exc}", EXIT_OPEN_ERR)
    fh = os.fdopen(fd, "wb")
    committed = False
    try:
        yield fh.write
        fh.flush()
        os.fsync(fh.fileno())
        fh.close()
        os.replace(tmp, dest)
        committed = True
    finally:
        if not committed:
            try:
                fh.close()
            except OSError:
                pass
            try:
                os.unlink(tmp)
            except FileNotFoundError:
                pass


@contextlib.contextmanager
def _stdout_writer():
    out = sys.stdout.buffer
    try:
        yield out.write
    finally:
        out.flush()


def _validate_output_dir_target(output_dir: Path, src_path: str) -> Path:
    rel = src_path.lstrip("/").rstrip("/")
    if not rel:
        fail(
            f"refusing to write empty relative path under {output_dir}",
            EXIT_USAGE,
        )
    if any(part == ".." for part in rel.split("/")):
        fail(
            f"path {src_path!r} contains '..' segments; refusing in --output-dir mode",
            EXIT_USAGE,
        )
    out_dir_resolved = output_dir.resolve()
    target = (output_dir / rel).resolve()
    try:
        target.relative_to(out_dir_resolved)
    except ValueError:
        fail(
            f"output target {target} escapes --output-dir {out_dir_resolved}",
            EXIT_USAGE,
        )
    return target


# ---------------------------------------------------------------------------
# Manifest cross-check
# ---------------------------------------------------------------------------


def configuration_value(conn: sqlite3.Connection, key: str) -> str | None:
    row = conn.execute("SELECT Value FROM Configuration WHERE Key = ?", (key,)).fetchone()
    return row["Value"] if row is not None else None


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _bytes_value(value: str) -> int:
    """Parse a byte size like ``1G``, ``250MB``, ``0`` to an int."""
    s = value.strip().upper()
    if not s:
        raise argparse.ArgumentTypeError("empty size")
    suffix_map = {
        "K": 1024,
        "KB": 1024,
        "KIB": 1024,
        "M": 1024**2,
        "MB": 1024**2,
        "MIB": 1024**2,
        "G": 1024**3,
        "GB": 1024**3,
        "GIB": 1024**3,
        "T": 1024**4,
        "TB": 1024**4,
        "TIB": 1024**4,
    }
    for suf in sorted(suffix_map.keys(), key=len, reverse=True):
        if s.endswith(suf):
            num = s[: -len(suf)].strip()
            try:
                return int(float(num) * suffix_map[suf])
            except ValueError as exc:
                raise argparse.ArgumentTypeError(f"invalid size {value!r}: {exc}")
    try:
        return int(s)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"invalid size {value!r}: {exc}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="duplicati-r2-extract",
        description=(
            "Extract a single file (or a glob) from a Duplicati R2 archive: "
            "fetches only the dblocks the file needs, decrypts in process "
            "memory, never persists plaintext outside the chosen output."
        ),
    )
    parser.add_argument("slug", help="Target slug (manifest .targets.<slug>).")
    parser.add_argument(
        "path",
        nargs="?",
        help="Absolute path to extract (omitted when --include is used).",
    )
    parser.add_argument(
        "--snapshot",
        help="Fileset.ID or ISO-8601 timestamp (default: latest).",
    )
    parser.add_argument(
        "--output",
        "-o",
        help="Destination file path, or '-' for stdout. Required for single-file mode.",
    )
    parser.add_argument(
        "--include",
        help=(
            "Path glob filter. Patterns with '/' match full paths with "
            "segment-aware globbing; a missing leading '/' is added. Patterns "
            "without '/' match the basename at any depth. Enables multi-file "
            "mode and requires --output-dir."
        ),
    )
    parser.add_argument(
        "--output-dir",
        help="Destination directory for --include mode. Mirrors snapshot tree.",
    )
    parser.add_argument(
        "--source",
        default=None,
        help=(
            "Object source URL. Default: R2 via env-file credentials. "
            "Use 'file:///abs/path' for an offline mirror."
        ),
    )
    parser.add_argument(
        "--env-file",
        default=DEFAULT_ENV_FILE,
        help=f"Dotenv file with R2 credentials and DUPLICATI_PASSPHRASE (default: {DEFAULT_ENV_FILE}).",
    )
    parser.add_argument(
        "--passphrase-env",
        help=(
            "Read passphrase from named environment variable instead of "
            "DUPLICATI_PASSPHRASE in the env file. Skips env-file when "
            "--source file:// is also set."
        ),
    )
    parser.add_argument(
        "--cache-dir",
        default=DEFAULT_CACHE_DIR,
        help=f"Encrypted-dblock cache root (default: {DEFAULT_CACHE_DIR}).",
    )
    parser.add_argument(
        "--cache-size",
        type=_bytes_value,
        default=DEFAULT_CACHE_BYTES,
        help="Encrypted cache size cap in bytes (suffixes K/M/G accepted, 0 disables).",
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
        help=(
            "Emit a JSON summary on stderr after extract (path, size, "
            "snapshot, dblocks fetched, bytes fetched). Plaintext still goes "
            "to the chosen sink."
        ),
    )
    return parser


def _need_credentials(args: argparse.Namespace) -> bool:
    """Whether the run needs R2 credentials.

    A ``file://`` source skips R2 entirely, and ``--passphrase-env`` covers
    the decryption side, so the env-file is unnecessary when both are set.
    """
    parsed = urllib.parse.urlparse(args.source or "")
    is_file_source = parsed.scheme == "file"
    if is_file_source and args.passphrase_env:
        return False
    return True


def _resolve_passphrase(args: argparse.Namespace, env: dict[str, str]) -> str:
    if args.passphrase_env:
        val = os.environ.get(args.passphrase_env)
        if not val:
            fail(
                f"--passphrase-env {args.passphrase_env} not set in environment",
                EXIT_USAGE,
            )
        return val
    val = env.get("DUPLICATI_PASSPHRASE")
    if not val:
        fail(
            "DUPLICATI_PASSPHRASE missing from env file; pass --passphrase-env to override",
            EXIT_USAGE,
        )
    return val


def _load_manifest_for_layout(args: argparse.Namespace) -> dict | None:
    """Read the manifest the way ``resolve_db_path`` does, but ignore-on-error.

    Used only for hostname / destSubpath / bucket resolution; if the
    manifest is unreadable, defaults still produce a working layout.
    ``--db`` overrides the SQLite path only; it does not override the bucket
    layout, so the manifest is still consulted here.
    """
    config_path = (
        getattr(args, "config", None) or os.environ.get("DUPLICATI_R2_CONFIG") or DEFAULT_CONFIG
    )
    if not os.path.exists(config_path) or not os.access(config_path, os.R_OK):
        return None
    return load_manifest(config_path)


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    # Mode validation.
    if args.include is not None:
        if args.path is not None:
            fail("pass either <path> or --include, not both", EXIT_USAGE)
        if not args.output_dir:
            fail("--include requires --output-dir", EXIT_USAGE)
        if args.output:
            fail(
                "--output is not valid with --include; use --output-dir instead",
                EXIT_USAGE,
            )
    else:
        if not args.path:
            fail("missing positional <path> (or use --include)", EXIT_USAGE)
        if not args.output:
            fail("missing --output (use '-' for stdout)", EXIT_USAGE)
        if args.output_dir:
            fail("--output-dir is only valid with --include", EXIT_USAGE)

    # Database open (Cut A semantics).
    conn = open_db(resolve_db_path(args))
    snapshot = resolve_snapshot(conn, parse_snapshot(args.snapshot))
    if snapshot is None:
        fail("no snapshots present in database")

    # Block hash + file hash from local DB Configuration.
    block_hash_algo = configuration_value(conn, "blockhash") or "SHA256"
    file_hash_algo = configuration_value(conn, "filehash") or "SHA256"
    blocksize_str = configuration_value(conn, "blocksize")
    try:
        blocksize = int(blocksize_str) if blocksize_str else None
    except ValueError:
        blocksize = None

    # Credentials and source.
    env: dict[str, str] = {}
    if _need_credentials(args):
        env = load_env_file(args.env_file)
    passphrase = _resolve_passphrase(args, env)
    manifest = _load_manifest_for_layout(args)
    layout = resolve_bucket_layout(args, env, manifest)
    source = build_source(args.source, env, layout)

    # Cache + decrypter. Cache is namespaced by short hostname (matches the
    # bucket prefix's hostname element) and the sanitized slug so concurrent
    # extracts against different targets don't collide.
    slug_dir = sanitize_slug(args.slug)
    cache_root = Path(args.cache_dir) / layout.hostname / slug_dir
    cache = EncryptedCache(str(cache_root), args.cache_size)
    decrypter = AesDecrypter(passphrase)

    extractor = Extractor(
        conn=conn,
        source=source,
        cache=cache,
        decrypter=decrypter,
        blocksize=blocksize,
        block_hash_algo=block_hash_algo,
        file_hash_algo=file_hash_algo,
    )

    started = time.monotonic()
    stats = ExtractStats()

    try:
        if args.include:
            output_dir = Path(args.output_dir)
            _ensure_private_dir(output_dir)
            include_pattern = _normalize_include_pattern(args.include)
            matched = False
            for src_path in _glob_paths(conn, snapshot["ID"], include_pattern):
                matched = True
                target = _validate_output_dir_target(output_dir, src_path)
                with _atomic_writer(target) as writer:
                    extractor.extract_file(snapshot["ID"], src_path, writer, stats)
            if not matched:
                suffix = ""
                if include_pattern != args.include:
                    suffix = f" (normalized to {include_pattern!r})"
                fail(
                    f"no paths in snapshot {snapshot['ID']} match {args.include!r}{suffix}",
                    EXIT_OPEN_ERR,
                )
        else:
            assert args.path is not None  # validated by mode-validation block above
            assert args.output is not None
            if args.output == "-":
                with _stdout_writer() as writer:
                    extractor.extract_file(snapshot["ID"], args.path, writer, stats)
            else:
                with _atomic_writer(Path(args.output)) as writer:
                    extractor.extract_file(snapshot["ID"], args.path, writer, stats)
    finally:
        extractor.close()

    elapsed = time.monotonic() - started
    if args.json:
        summary = {
            "slug": args.slug,
            "snapshot_id": snapshot["ID"],
            "snapshot_timestamp": iso_utc(snapshot["Timestamp"]),
            "plaintext_bytes": stats.plaintext_size,
            "bytes_fetched": cache.bytes_fetched,
            "dblocks_fetched": cache.fetches,
            "dblocks_touched": len(stats.dblocks_touched),
            "blocksize": blocksize,
            "block_hash": block_hash_algo,
            "file_hash": file_hash_algo,
            "elapsed_seconds": round(elapsed, 3),
        }
        print(json.dumps(summary, indent=2), file=sys.stderr)
    return 0


def _segment_globmatch(path: str, pattern: str) -> bool:
    path_parts = tuple(path.split("/"))
    pattern_parts = tuple(pattern.split("/"))
    memo: dict[tuple[int, int], bool] = {}

    def match(pattern_index: int, path_index: int) -> bool:
        state = (pattern_index, path_index)
        cached = memo.get(state)
        if cached is not None:
            return cached
        if pattern_index == len(pattern_parts):
            result = path_index == len(path_parts)
        elif pattern_parts[pattern_index] == "**":
            if pattern_index == len(pattern_parts) - 1:
                result = path_index <= len(path_parts)
            else:
                result = any(
                    match(pattern_index + 1, next_path_index)
                    for next_path_index in range(path_index, len(path_parts) + 1)
                )
        elif path_index == len(path_parts):
            result = False
        else:
            result = fnmatch.fnmatchcase(
                path_parts[path_index],
                pattern_parts[pattern_index],
            ) and match(pattern_index + 1, path_index + 1)
        memo[state] = result
        return result

    return match(0, 0)


def _glob_paths(
    conn: sqlite3.Connection,
    snapshot_id: int,
    pattern: str,
) -> Iterator[str]:
    """Yield File.Path entries matching ``pattern``.

    ``pattern`` is expected to be pre-normalized by
    ``_normalize_include_pattern``. A pattern containing a ``/`` is interpreted
    as a segment-aware full-path glob (``/data/*.bin`` matches direct children;
    ``/data/**/*.bin`` matches descendants). A pattern with no ``/`` is matched
    against the file's basename (``*.bin`` matches every ``.bin`` file at any
    depth). This mirrors how operators typically reach for `find -name` without
    escaping every prefix.
    """
    is_basename_pattern = "/" not in pattern
    cursor = conn.execute(
        """
        SELECT f.Path AS path, f.BlocksetID AS blockset_id
        FROM File f
          JOIN FilesetEntry fse ON fse.FileID = f.ID
        WHERE fse.FilesetID = ?
        ORDER BY f.Path
        """,
        (snapshot_id,),
    )
    for row in cursor:
        if row["blockset_id"] is None or row["blockset_id"] < 0:
            continue  # skip dirs/symlinks
        if is_basename_pattern:
            matches_pattern = fnmatch.fnmatchcase(
                os.path.basename(row["path"].rstrip("/")),
                pattern,
            )
        else:
            matches_pattern = _segment_globmatch(row["path"], pattern)
        if matches_pattern:
            yield row["path"]


def _normalize_include_pattern(pattern: str) -> str:
    if "/" in pattern and not pattern.startswith("/"):
        return "/" + pattern
    return pattern


if __name__ == "__main__":
    sys.exit(main())
