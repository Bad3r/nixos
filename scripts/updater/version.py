"""Version fetching from various sources (GitHub, npm, custom APIs)."""

import re
from functools import cmp_to_key
from typing import cast

from .http import JsonArray, fetch_json, fetch_text
from .nix import run_command

GITHUB_TAGS_PAGE_SIZE = 100


def fetch_github_latest_release(owner: str, repo: str) -> str:
    """Fetch the latest release version from GitHub.

    Args:
        owner: Repository owner
        repo: Repository name

    Returns:
        Latest release version (without 'v' prefix)

    """
    url = f"https://api.github.com/repos/{owner}/{repo}/releases/latest"
    data = fetch_json(url)
    if not isinstance(data, dict):
        msg = f"Expected dict from GitHub API, got {type(data)}"
        raise TypeError(msg)
    tag = cast("str", data["tag_name"])

    # Strip 'v' prefix if present (also handled in parse_version for defensive comparison)
    return tag.lstrip("v")


def is_stable_numeric_version(version: str) -> bool:
    """Return whether a version is numeric and has no prerelease suffix."""
    return re.fullmatch(r"\d+(?:\.\d+)*", version) is not None


def _stable_tag_versions(data: JsonArray, prefix: str) -> list[str]:
    """Return stable numeric tag versions from one GitHub tag page."""
    versions: list[str] = []
    for item in data:
        if not isinstance(item, dict):
            msg = f"Expected tag object dict, got {type(item)}"
            raise TypeError(msg)

        name = item.get("name")
        if not isinstance(name, str):
            msg = f"Expected tag name string, got {type(name)}"
            raise TypeError(msg)
        if prefix and not name.startswith(prefix):
            continue

        version = name.removeprefix(prefix) if prefix else name
        if is_stable_numeric_version(version):
            versions.append(version)
    return versions


def fetch_github_latest_tag_version(
    owner: str,
    repo: str,
    *,
    prefix: str = "v",
    max_pages: int = 10,
) -> str:
    """Fetch the newest stable version from GitHub tags.

    Args:
        owner: Repository owner
        repo: Repository name
        prefix: Tag prefix to strip before comparing versions
        max_pages: Maximum number of GitHub tag pages to scan

    Returns:
        Latest stable version string without the configured prefix

    """
    versions: list[str] = []
    for page in range(1, max_pages + 1):
        url = (
            f"https://api.github.com/repos/{owner}/{repo}/tags?"
            f"per_page={GITHUB_TAGS_PAGE_SIZE}&page={page}"
        )
        data = fetch_json(url)
        if not isinstance(data, list):
            msg = f"Expected list from GitHub API, got {type(data)}"
            raise TypeError(msg)
        if not data:
            break

        versions.extend(_stable_tag_versions(data, prefix))

        if len(data) < GITHUB_TAGS_PAGE_SIZE:
            break

    if not versions:
        msg = f"Could not find stable tags for {owner}/{repo}"
        raise RuntimeError(msg)

    return max(versions, key=cmp_to_key(compare_versions))


def _version_group_pattern(pattern: str, version_group: str) -> str | None:
    """Extract the source pattern for a named regex group."""
    marker = f"(?P<{version_group}>"
    start = pattern.find(marker)
    if start == -1:
        return None

    index = start + len(marker)
    depth = 1
    escaped = False
    in_char_class = False
    group_chars: list[str] = []
    while index < len(pattern):
        char = pattern[index]
        if escaped:
            group_chars.append(char)
            escaped = False
        elif char == "\\":
            group_chars.append(char)
            escaped = True
        elif char == "[" and not in_char_class:
            in_char_class = True
            group_chars.append(char)
        elif char == "]" and in_char_class:
            in_char_class = False
            group_chars.append(char)
        elif char == "(" and not in_char_class:
            group_chars.append(char)
            depth += 1
        elif char == ")" and not in_char_class:
            depth -= 1
            if depth == 0:
                return "".join(group_chars)
            group_chars.append(char)
        else:
            group_chars.append(char)
        index += 1

    return None


def _pattern_explicitly_accepts_prerelease(
    pattern: str,
    version_group: str,
) -> bool:
    """Return true when the version capture visibly allows prerelease suffixes."""
    group_pattern = _version_group_pattern(pattern, version_group)
    if group_pattern is None:
        return False

    prerelease_markers = [
        "-",
        "alpha",
        "beta",
        "canary",
        "dev",
        "next",
        "pre",
        "preview",
        "rc",
    ]
    return any(marker in group_pattern.lower() for marker in prerelease_markers)


def _looks_like_prerelease(version: str) -> bool:
    """Return true when a captured version has a prerelease-looking suffix."""
    _numeric, suffix = parse_version(version)
    return bool(suffix)


def fetch_github_latest_tag(
    owner: str,
    repo: str,
    pattern: str,
    version_group: str = "version",
) -> str:
    """Fetch the highest matching stable tag version from GitHub.

    Args:
        owner: Repository owner
        repo: Repository name
        pattern: Full tag regex with a named version capture group
        version_group: Named regex group containing the comparable version

    Returns:
        Highest matching version captured from the tag

    Raises:
        ValueError: If no matching tag is found

    """
    tag_pattern = re.compile(pattern)
    allow_prerelease = _pattern_explicitly_accepts_prerelease(pattern, version_group)
    latest: str | None = None
    page = 1

    while True:
        url = (
            f"https://api.github.com/repos/{owner}/{repo}/tags?per_page=100&page={page}"
        )
        data = fetch_json(url)
        if not isinstance(data, list):
            msg = f"Expected list from GitHub tags API, got {type(data)}"
            raise TypeError(msg)
        if not data:
            break

        for tag in data:
            if not isinstance(tag, dict):
                msg = f"Expected tag dict from GitHub API, got {type(tag)}"
                raise TypeError(msg)
            name = tag.get("name")
            if not isinstance(name, str):
                msg = f"Expected tag name string, got {type(name)}"
                raise TypeError(msg)

            match = tag_pattern.fullmatch(name)
            if match is None:
                continue

            version = match.group(version_group)
            if not allow_prerelease and _looks_like_prerelease(version):
                continue
            if latest is None or compare_versions(latest, version) < 0:
                latest = version

        if len(data) < 100:
            break
        page += 1

    if latest is None:
        msg = f"Could not find a matching stable tag for {owner}/{repo}"
        raise ValueError(msg)
    return latest


def fetch_npm_version(package: str) -> str:
    """Fetch the latest version from npm registry.

    Args:
        package: npm package name

    Returns:
        Latest version

    """
    # Try using npm command first
    try:
        cmd = ["npm", "view", package, "version"]
        result = run_command(cmd)
        return result.stdout.strip()
    except (FileNotFoundError, OSError):
        # npm command not available, fallback to registry API
        url = f"https://registry.npmjs.org/{package}/latest"
        data = fetch_json(url)
        if not isinstance(data, dict):
            msg = f"Expected dict from npm registry, got {type(data)}"
            raise TypeError(msg) from None
        return cast("str", data["version"])


# Parse versions into numeric components for proper comparison
# Handle versions like "1.0.105", "0.61.0", "2025.11.06-8fe8a63", "v1.0.0"
def parse_version(v: str) -> tuple[list[int], str]:
    """Parse version into numeric parts and suffix."""
    # Strip 'v' prefix if present
    v = v.lstrip("v")

    # Split on common separators (-, +, etc) to separate numeric from suffix
    parts = v.replace("+", "-").split("-", 1)
    numeric_str = parts[0]
    suffix = parts[1] if len(parts) > 1 else ""

    # Parse numeric components
    try:
        numeric = [int(x) for x in numeric_str.split(".")]
    except ValueError:
        # Fallback to lexicographic if not numeric
        numeric = []

    return (numeric, suffix)


def _compare_strings(left: str, right: str) -> int:
    """Return the comparison value for strings."""
    return (left > right) - (left < right)


def _compare_ints(left: int, right: int) -> int:
    """Return the comparison value for integers."""
    return (left > right) - (left < right)


def _compare_suffixes(v1_suffix: str, v2_suffix: str) -> int:
    """Compare semantic version suffixes after numeric components match."""
    if v1_suffix == v2_suffix:
        return 0
    if not v1_suffix:
        return 1
    if not v2_suffix:
        return -1
    return _compare_strings(v1_suffix, v2_suffix)


def compare_versions(v1: str, v2: str) -> int:
    """Compare two semantic versions.

    Args:
        v1: First version
        v2: Second version

    Returns:
        -1 if v1 < v2, 0 if v1 == v2, 1 if v1 > v2

    """
    if v1 == v2:
        return 0

    v1_numeric, v1_suffix = parse_version(v1)
    v2_numeric, v2_suffix = parse_version(v2)

    # If parsing failed for either, fall back to lexicographic
    if not v1_numeric or not v2_numeric:
        return _compare_strings(v1, v2)

    # Compare numeric components
    for i in range(max(len(v1_numeric), len(v2_numeric))):
        n1 = v1_numeric[i] if i < len(v1_numeric) else 0
        n2 = v2_numeric[i] if i < len(v2_numeric) else 0
        result = _compare_ints(n1, n2)
        if result != 0:
            return result

    # Numeric parts are equal, compare suffix lexicographically
    # No suffix is considered "greater" than having a suffix (1.0.0 > 1.0.0-beta)
    return _compare_suffixes(v1_suffix, v2_suffix)


def should_update(current: str, latest: str) -> bool:
    """Check if an update is needed.

    Args:
        current: Current version
        latest: Latest available version

    Returns:
        True if update is needed

    """
    return compare_versions(current, latest) < 0


def fetch_version_from_text(url: str, pattern: str) -> str:
    """Fetch text from URL and extract version using regex pattern.

    Args:
        url: URL to fetch text from
        pattern: Regex pattern with a capture group for the version

    Returns:
        Extracted version string

    Raises:
        ValueError: If version cannot be extracted

    """
    text = fetch_text(url)
    match = re.search(pattern, text)
    if not match:
        msg = f"Could not extract version from {url} using pattern {pattern}"
        raise ValueError(msg)
    return match.group(1)
