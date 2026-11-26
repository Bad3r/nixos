# Copyright (c) 2026 Bad3r

"""Write a byte-patched copy of the agy CLI binary.

Usage: python3 -I _patch_agy.py IN OUT [--patches SET[,SET...]]

Patch sets (default: all five):

  devmode       language_server.Options.EnvironmentConfig.DevMode (opts+0x1) = true at the entry
                of language_server.CreateLanguageServerAndServe. The Hub sets it from --dev_mode;
                agy has no such flag and never writes it.
  notelemetry   language_server.Options.DisableTelemetry (opts+0x122) = true at the same entry,
                and main's package-level Options.DisableTelemetry = true at the start of main.main.
                The language server itself writes opts+0x122 = 1 when an admin policy disables
                telemetry; main.main, main.init.func3 (standalone analytics recorder) and
                main.recordPluginSubcommandEvents read the package-level copy. TUI, print mode and
                --hub use that copy, so without this patch only "agy acp --disable_telemetry" turns
                telemetry off.
  noautoupdate  makes updater.triggerUpdateShared always take its "Auto-update disabled via
                environment variable" return. Unpatched, it skips the update only when
                AGY_CLI_DISABLE_AUTO_UPDATE is exactly "true" and the caller does not force it;
                otherwise, when the binary's directory is writable, it spawns a background process
                that downloads the newest CLI and renames it over os.Executable().
  quietwatcher  NOPs the log call at file_watcher.go:194 ("skipping empty or temp file: %s"). Its
                event loop spins on a closed channel at shutdown and logs one ERROR line per spin.
  agygating     sets enabled: false on the sir_flash_lite and severe_internal_risks_agy monitors in
                the embedded MonitorsConfig textproto, and severe_internal_risks_agy's mode from
                BLOCK to ASK. Both are LLM pre-filters on pending tool calls;
                severe_internal_risks_agy runs behind sir_flash_lite. Each edit borrows one byte of
                the next line's indentation.

Both opts stores need more room than the hooked instructions, so the hooks jump to code in int3
padding past the last Go function (findfunc reports no Go function there, so async preemption
skips it). Each hook re-executes the instructions it replaces and jumps back. A nil opts still
faults on the first access, now outside Go's symbol table, so the runtime reports a fatal signal
instead of a nil-pointer panic.

Only builds listed in BUILDS are patched; every replaced byte and the whole cave are checked
before anything is written. OUT.patch.json records the patches and both checksums.
"""

import hashlib
import json
import shutil
import struct
import sys
from pathlib import Path
from typing import NoReturn

ALL = ("devmode", "notelemetry", "noautoupdate", "quietwatcher", "agygating")

# sha256 of the unpatched binary -> addresses (file offset == vaddr in the first LOAD segment).
BUILDS = {
    "0fafb9f87a76533ec6c7fd3112fee9306d4d50ba729f9ecb1506ff20884d9cd0": {
        "version": "1.5.17",
        # CreateLanguageServerAndServe: movups [rsp+0xd38],xmm15 ; test [rcx],al ; nop ; nop
        "ls_hook": 0xAB8C065,
        "ls_orig": "440f11bc24380d000084019090",
        # main.main: mov BYTE PTR [rsp+0x2c7],0x0 (open-coded defer bits)
        "main_hook": 0xB39286F,
        "main_orig": "c68424c702000000",
        # main's package-level language_server.Options: DisableTelemetry at +0x122
        "main_opts": 0xDD7FFC0,
        # file_watcher.(*FileWatcherDefault).listenAndForwardEvents: call log.ctxlogf
        "watcher_call": 0x8AD7F20,
        "watcher_orig": "e81b3a1fff",
        # updater.triggerUpdateShared: test dl,dl ; jne <disabled-by-env return at 0xb331447>
        "update_gate": 0xB330060,
        "update_orig": "84d20f85df130000",
        "update_disabled": 0xB331447,
        # int3 run between the end of a C++ function (ret at 0xb413492) and the page boundary
        "cave": (0xB413493, 0xB414000),
        # Embedded MonitorsConfig textproto (agygating)
        "monitors": (
            # sir_flash_lite; the mode edit only checks the following line
            (0x0D888D1D, b"enabled: true\n ", b"enabled: false\n"),
            (0x0D888D2C, b" mode: LOG\n", b" mode: LOG\n"),
            # severe_internal_risks_agy
            (0x0D88B09B, b"enabled: true\n ", b"enabled: false\n"),
            (0x0D88B0AA, b" mode: BLOCK\n", b"  mode: ASK \n"),
        ),
    },
}
OPTS_DEVMODE = 0x1
OPTS_DISABLE_TELEMETRY = 0x122
NOP3 = bytes.fromhex("0f1f00")
NOP5 = bytes.fromhex("0f1f440000")
NOP8 = bytes.fromhex("0f1f840000000000")
INT3 = 0xCC
ARG_COUNT = 2

Edit = tuple[int, bytes, bytes]


def fail(message: str) -> NoReturn:
    sys.exit(message)


def jmp(src: int, dst: int) -> bytes:
    return b"\xe9" + struct.pack("<i", dst - (src + 5))


def align16(pc: int) -> int:
    return (pc + 0xF) & ~0xF


def ls_entry(build: dict, pc: int, patches: list[str]) -> tuple[list[Edit], int]:
    """Set DevMode and/or DisableTelemetry in *opts on entry to CreateLanguageServerAndServe."""
    hook, orig = build["ls_hook"], bytes.fromhex(build["ls_orig"])
    body = orig[:9] + orig[9:11]  # movups [rsp+0xd38],xmm15 ; test [rcx],al (nil check)
    if "devmode" in patches:
        body += b"\xc6\x41" + bytes([OPTS_DEVMODE, 1])  # mov BYTE PTR [rcx+0x1],0x1
    if "notelemetry" in patches:
        # mov BYTE PTR [rcx+0x122],0x1
        body += b"\xc6\x81" + struct.pack("<i", OPTS_DISABLE_TELEMETRY) + b"\x01"
    body += jmp(pc + len(body), hook + len(orig))
    edits = [(pc, bytes([INT3]) * len(body), body), (hook, orig, jmp(hook, pc) + NOP8)]
    return edits, align16(pc + len(body))


def main_entry(build: dict, pc: int) -> tuple[list[Edit], int]:
    """Set main's package-level Options.DisableTelemetry at the start of main.main."""
    hook, orig = build["main_hook"], bytes.fromhex(build["main_orig"])
    target = build["main_opts"] + OPTS_DISABLE_TELEMETRY
    body = bytearray(orig)  # mov BYTE PTR [rsp+0x2c7],0x0
    ins = pc + len(body)
    body += b"\xc6\x05" + struct.pack("<i", target - (ins + 7)) + b"\x01"  # mov BYTE PTR [rip+X],1
    body += jmp(pc + len(body), hook + len(orig))
    edits = [(pc, bytes([INT3]) * len(body), bytes(body)), (hook, orig, jmp(hook, pc) + NOP3)]
    return edits, align16(pc + len(body))


def plan(data: bytearray, build: dict, patches: list[str]) -> list[Edit]:
    cave_lo, cave_hi = build["cave"]
    if set(data[cave_lo:cave_hi]) != {INT3}:
        fail(f"cave {cave_lo:#x}-{cave_hi:#x} is not all int3; refusing to patch")
    edits: list[Edit] = []
    pc = align16(cave_lo)
    if "devmode" in patches or "notelemetry" in patches:
        more, pc = ls_entry(build, pc, patches)
        edits += more
    if "notelemetry" in patches:
        more, pc = main_entry(build, pc)
        edits += more
    if "noautoupdate" in patches:
        hook = build["update_gate"]
        edits.append(
            (hook, bytes.fromhex(build["update_orig"]), jmp(hook, build["update_disabled"]) + NOP3)
        )
    if "quietwatcher" in patches:
        edits.append((build["watcher_call"], bytes.fromhex(build["watcher_orig"]), NOP5))
    if "agygating" in patches:
        monitors = build.get("monitors")
        if not monitors:
            fail(f"patch set 'agygating' is not supported on agy {build['version']}")
        edits.extend(monitors)
    if pc > cave_hi:
        fail("cave too small")
    return edits


def apply(data: bytearray, edits: list[Edit]) -> None:
    for off, orig, new in edits:
        cur = bytes(data[off : off + len(orig)])
        if cur != orig:
            fail(f"bytes at {off:#x} are {cur.hex()}, expected {orig.hex()}; refusing to patch")
        if len(orig) != len(new):
            fail(f"edit at {off:#x} changes length")
    for off, _orig, new in edits:
        data[off : off + len(new)] = new


def parse_args(argv: list[str]) -> tuple[Path, Path, list[str]]:
    args = list(argv)
    patches = list(ALL)
    if "--patches" in args:
        k = args.index("--patches")
        if k + 1 >= len(args):
            fail("--patches requires a value: SET[,SET...]")
        patches = [p for p in args[k + 1].split(",") if p]
        del args[k : k + 2]
    bad = [p for p in patches if p not in ALL]
    if bad:
        fail(f"unknown patch set(s): {','.join(bad)} (known: {','.join(ALL)})")
    if not patches or len(args) != ARG_COUNT:
        fail(__doc__ or "usage: _patch_agy.py IN OUT [--patches SET[,SET...]]")
    return Path(args[0]), Path(args[1]), [p for p in ALL if p in patches]


def main(argv: list[str]) -> None:
    src, dst, patches = parse_args(argv)
    data = bytearray(src.read_bytes())
    sha = hashlib.sha256(data).hexdigest()
    if sha not in BUILDS:
        fail(
            f"{src}: unknown agy build (sha256 {sha}). Add a BUILDS entry for it: each address is "
            "named next to its field, and every site is checked before anything is written."
        )
    build = BUILDS[sha]
    edits = plan(data, build, patches)
    apply(data, edits)
    tmp = dst.with_name(dst.name + ".tmp")
    tmp.write_bytes(data)
    shutil.copymode(src, tmp)
    tmp.replace(dst)
    manifest = {
        "input": str(src.resolve()),
        "input_sha256": sha,
        "version": build["version"],
        "patches": patches,
        "edits": [{"offset": hex(o), "orig": a.hex(), "new": n.hex()} for o, a, n in edits],
        "output": str(dst.resolve()),
        "output_sha256": hashlib.sha256(data).hexdigest(),
    }
    with dst.with_name(dst.name + ".patch.json").open("w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main(sys.argv[1:])
