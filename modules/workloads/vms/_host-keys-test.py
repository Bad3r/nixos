# Copyright (c) 2026 Bad3r
"""Check that _host-keys.py accepts only one ED25519 key from a guest."""

import base64
import importlib.util
import json
import struct
import sys
import types

from hypothesis import given, settings
from hypothesis import strategies as st

reads: list[dict] = []


def fake_agent(_domain: object, request: str, _timeout: int, _flags: int) -> str:
    """Answer guest-file commands from the reads queued by a test."""
    command = json.loads(request)["execute"]
    if command == "guest-file-open":
        return json.dumps({"return": 1})
    if command == "guest-file-close":
        return json.dumps({"return": {}})
    if not reads:
        msg = "read past the queued replies"
        raise AssertionError(msg)
    return json.dumps({"return": reads.pop(0)})


sys.modules["libvirt"] = types.SimpleNamespace(libvirtError=Exception, virDomain=object)
sys.modules["libvirt_qemu"] = types.SimpleNamespace(qemuAgentCommand=fake_agent)
spec = importlib.util.spec_from_file_location("host_keys", sys.argv[1])
if spec is None or spec.loader is None:
    msg = f"cannot load {sys.argv[1]}"
    raise SystemExit(msg)
hk = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hk)


def expect(condition: object, what: str, /) -> None:
    """Fail the check with a message; assert statements vanish under -O."""
    if not condition:
        raise AssertionError(what)


HOSTS = ["win11", "win11.vm", "172.16.1.11"]
ASCII_COMMENT = st.text(st.characters(codec="ascii", exclude_characters="\r\n\0"), max_size=40)


def blob(raw: bytes) -> bytes:
    """Return an ED25519 key in SSH wire format."""
    return struct.pack(">I", 11) + b"ssh-ed25519" + struct.pack(">I", 32) + raw


def line(raw: bytes) -> str:
    """Return a public key line without a comment."""
    return f"ssh-ed25519 {base64.b64encode(blob(raw)).decode()}"


def rejected(data: bytes) -> bool:
    """Return whether parse_key refuses the data."""
    try:
        hk.parse_key(data)
    except hk.KeyFormatError:
        return True
    return False


@settings(max_examples=500, derandomize=True)
@given(st.binary(min_size=32, max_size=32), ASCII_COMMENT, st.sampled_from(["", "\n", "\r\n"]))
def accepts_valid(raw: bytes, comment: str, end: str) -> None:
    """A key line with any comment and line ending parses to its blob."""
    text = line(raw) + (f" {comment}" if comment else "") + end
    expect(hk.parse_key(text.encode()) == blob(raw), text)


@settings(max_examples=3000, derandomize=True)
@given(st.binary(max_size=200))
def any_bytes_parse_or_refuse(data: bytes) -> None:
    """Arbitrary bytes raise nothing but KeyFormatError."""
    rejected(data)


accepted: list[bytes] = []


@settings(max_examples=3000, derandomize=True)
@given(st.binary(min_size=32, max_size=32), st.binary(max_size=80))
def suffixed_key_gives_one_line(raw: bytes, tail: bytes) -> None:
    """A valid key followed by anything is refused or renders as exactly one declared line."""
    data = line(raw).encode() + tail
    if rejected(data):
        return
    accepted.append(data)
    expect(hk.parse_key(data) == blob(raw), repr(data))
    host, kind, key = hk.known_hosts_line(HOSTS, hk.parse_key(data)).removesuffix("\n").split(" ")
    expect(host == ",".join(HOSTS), host)
    expect(kind == "ssh-ed25519", kind)
    expect(base64.b64decode(key) == blob(raw), key)


def suffixes_reach_acceptance() -> None:
    """The suffix property exercised its accepting branch, not only refusals."""
    expect(len(accepted) > 0, "no suffixed key was accepted")


def rejects_malformed() -> None:
    """Injected lines, other key types, wrong lengths, and bad encodings are refused."""
    good = line(bytes(32))
    for data in [
        f"{good}\ngithub.com {good}",
        f"{good} x\0y",
        f"{good}\rx",
        f"{good} café",
        line(bytes(32))[:-4] + "!!!!",
        "ssh-rsa " + base64.b64encode(struct.pack(">I", 7) + b"ssh-rsa" + bytes(32)).decode(),
        "ssh-ed25519 " + base64.b64encode(blob(bytes(31))).decode(),
        "ssh-ed25519 " + base64.b64encode(blob(bytes(33))).decode(),
        "ssh-ed25519",
        "",
    ]:
        expect(rejected(data.encode("utf-8")), repr(data))


def read_loop_ends() -> None:
    """An empty read ends the loop, and an oversized file is refused."""
    reads[:] = [{"count": 1, "buf-b64": "", "eof": False}]
    expect(hk.read_guest_file(None, "key") == b"", "an empty read returned data")
    expect(not reads, "the loop read again after an empty read")
    chunk = base64.b64encode(bytes(hk.MAX_KEY_FILE)).decode()
    reads[:] = [{"count": hk.MAX_KEY_FILE, "buf-b64": chunk, "eof": False}] * 2
    try:
        hk.read_guest_file(None, "key")
    except hk.KeyFormatError:
        pass
    else:
        msg = "an oversized key file was accepted"
        raise AssertionError(msg)


for check in (
    accepts_valid,
    any_bytes_parse_or_refuse,
    suffixed_key_gives_one_line,
    suffixes_reach_acceptance,
    rejects_malformed,
    read_loop_ends,
):
    check()
    print(f"{check.__name__}: ok")
print(f"suffixed keys accepted: {len(accepted)}")
