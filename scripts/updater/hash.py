"""Hash calculation utilities for Nix packages."""

import base64
import re
import shutil
import tempfile
import urllib.parse
import urllib.request
from collections.abc import Mapping
from pathlib import Path

from .nix import nix_hash_file, nix_prefetch_url, nix_store_prefetch_file

# Dummy hash used to trigger Nix build errors to extract correct hash
DUMMY_SHA256_HASH = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="


def _require_http_url(url: str, context: str) -> None:
    """Reject URL schemes that Nix fetchers should not hash as artifacts."""
    scheme = urllib.parse.urlparse(url).scheme.lower()
    if scheme not in {"http", "https"}:
        msg = f"Refusing to download from non-HTTP(S) {context} URL: {url}"
        raise ValueError(msg)


def calculate_downloaded_url_hash(
    url: str,
    *,
    headers: Mapping[str, str],
) -> str:
    """Download a URL with headers and hash the resulting file.

    Args:
        url: URL to download
        headers: HTTP headers to send with the request

    Returns:
        Hash in SRI format

    """
    _require_http_url(url, "source")

    request = urllib.request.Request(url)  # noqa: S310
    for name, value in headers.items():
        request.add_header(name, value)

    with (
        urllib.request.urlopen(request, timeout=60) as response,  # noqa: S310
        tempfile.NamedTemporaryFile() as tmp,
    ):
        _require_http_url(response.geturl(), "redirect")
        shutil.copyfileobj(response, tmp)
        tmp.flush()
        return nix_hash_file(Path(tmp.name))


def calculate_url_hash(
    url: str,
    *,
    unpack: bool = False,
    headers: Mapping[str, str] | None = None,
) -> str:
    """Calculate hash for a URL.

    Args:
        url: URL to calculate hash for
        unpack: Whether to unpack the archive (use True for fetchzip packages)
        headers: Optional HTTP headers for servers that reject bare prefetches

    Returns:
        Hash in SRI format (sha256-...)

    """
    if headers is not None:
        if unpack:
            msg = "Header-aware unpacked URL hashes are not supported"
            raise ValueError(msg)
        return calculate_downloaded_url_hash(url, headers=headers)

    if unpack:
        # Use nix-prefetch-url --unpack for fetchzip packages
        return nix_prefetch_url(url, unpack=True)
    # Use nix store prefetch-file for regular fetchurl packages
    return nix_store_prefetch_file(url)


def extract_hash_from_build_error(error_output: str) -> str | None:
    """Extract the correct hash from a Nix build error message.

    Args:
        error_output: Error output from nix build command

    Returns:
        Extracted hash in SRI format, or None if not found

    """
    # Patterns match variations: "got: sha256-...", "got sha256-...", "actual: sha256-..."
    patterns = [
        r"got:\s+(sha256-[A-Za-z0-9+/=]+)",
        r"got\s+(sha256-[A-Za-z0-9+/=]+)",
        r"actual:\s+(sha256-[A-Za-z0-9+/=]+)",
    ]

    for pattern in patterns:
        match = re.search(pattern, error_output)
        if match:
            return match.group(1)

    return None


def hex_to_sri(hex_hash: str, algo: str = "sha256") -> str:
    """Convert a hex hash of the specified algorithm to SRI format."""
    hash_bytes = bytes.fromhex(hex_hash)
    b64_hash = base64.b64encode(hash_bytes).decode("ascii")
    return f"{algo}-{b64_hash}"
