# Copyright (c) 2026 Bad3r

"""Patch planning and atomic validation for dynamic and pinned `agy` builds."""

from __future__ import annotations

import struct
from dataclasses import dataclass
from typing import TYPE_CHECKING, Any

from _agy_patcher.discover import discover_targets
from _agy_patcher.elf import INT3_BYTE, PatchError
from _agy_patcher.x86 import (
    JMP_REL32_LEN,
    align16,
    jmp_rel32,
    lea_rip,
    mov_rcx_disp_byte_imm,
    mov_rip_byte_imm,
    nop_sled,
)

if TYPE_CHECKING:
    from collections.abc import Sequence

    from _agy_patcher.discover import DynamicTargets, NoTelemetryTargets
    from _agy_patcher.elf import Elf64Image

DYNAMIC_PATCHES: tuple[str, ...] = (
    "notelemetry",
    "noautoupdate",
    "quietwatcher",
)

ALL: tuple[str, ...] = (
    "devmode",
    "notelemetry",
    "noautoupdate",
    "quietwatcher",
    "agygating",
    "staticprompts",
    "testjmp",
)

OPTS_DEVMODE = 0x1
OPTS_DISABLE_TELEMETRY = 0x122
MAX_DISP8 = 0x7F
QWORD = 8
DWORD = 4
WORD = 2

# sha256 of the unpatched binary -> pinned offsets for legacy/pinned-only patch sets.
BUILDS: dict[str, dict[str, Any]] = {
    "0fafb9f87a76533ec6c7fd3112fee9306d4d50ba729f9ecb1506ff20884d9cd0": {
        "version": "1.5.17",
        "ls_hook": 0xAB8C065,
        "ls_orig": "440f11bc24380d000084019090",
        "main_hook": 0xB39286F,
        "main_orig": "c68424c702000000",
        "main_opts": 0xDD7FFC0,
        "watcher_call": 0x8AD7F20,
        "watcher_orig": "e81b3a1fff",
        "update_gate": 0xB330060,
        "update_orig": "84d20f85df130000",
        "update_disabled": 0xB331447,
        "cave": (0xB413493, 0xB414000),
        "monitors": (
            (0x0D888D1D, b"enabled: true\n ", b"enabled: false\n"),
            (0x0D888D2C, b" mode: LOG\n", b" mode: LOG\n"),
            (0x0D88B09B, b"enabled: true\n ", b"enabled: false\n"),
            (0x0D88B0AA, b" mode: BLOCK\n", b"  mode: ASK \n"),
        ),
        "static_string_itab": 0xD6F3DB8,
        "template_source_itab": 0xD6F5538,
        "template_source_zero": 0x110E64A0,
        "static_prompts": (
            ("browser_safety", 0x9A9E7E0, 0xBCED000),
            ("chrome_default_profile", 0x9A9E860, 0xBCED010),
            ("work_efficiently", 0x9AA1600, 0xBCED020),
            ("non_interactive_mode", 0x9AA74E0, 0xBCED070),
        ),
        "embed_read_hook": 0x8C3A985,
        "embed_read_orig": "48897c2438488944245848895c2440",
        "test_jmp_addr": 0x9E5BC0A,
        "test_jmp_orig": "e8b15681fe",
    },
    "8c51d6ee686bf8560cef67d5e7ca5a50b97e25a5a47eb657031fed858a46e0dc": {
        "version": "1.5.18",
        "ls_hook": 0xAD385E5,
        "ls_orig": "440f11bc24100c000084019090",
        "main_hook": 0xB5409EF,
        "main_orig": "c68424c702000000",
        "main_opts": 0xDF75320,
        "watcher_call": 0x8BF41A0,
        "watcher_orig": "e8db551dff",
        "update_gate": 0xB4DE1C0,
        "update_orig": "84d20f85df130000",
        "update_disabled": 0xB4DF5A7,
        "cave": (0xB5C1613, 0xB5C2000),
        "monitors": (
            (0x0DA7E97D, b"enabled: true\n ", b"enabled: false\n"),
            (0x0DA7E98C, b" mode: LOG\n", b" mode: LOG\n"),
            (0x0DA80CFB, b"enabled: true\n ", b"enabled: false\n"),
            (0x0DA80D0A, b" mode: BLOCK\n", b"  mode: ASK \n"),
        ),
        "static_string_itab": 0xD8E4990,
        "template_source_itab": 0xD8E6130,
        "template_source_zero": 0x112F3CA0,
        "static_prompts": (
            ("browser_safety", 0x9BF0380, 0xBE9D750),
            ("chrome_default_profile", 0x9BF0400, 0xBE9D760),
            ("work_efficiently", 0x9BF31A0, 0xBE9D770),
            ("non_interactive_mode", 0x9BF9080, 0xBE9D7C0),
        ),
        "embed_read_hook": 0x8D5E825,
        "embed_read_orig": "48897c2438488944245848895c2440",
        "test_jmp_addr": 0x9FB244A,
        "test_jmp_orig": "e871c97dfe",
    },
}


@dataclass(frozen=True)
class Edit:
    """Single length-preserving byte replacement at virtual address `vaddr`."""

    vaddr: int
    orig: bytes
    new: bytes

    def __post_init__(self) -> None:
        """Verify replacement preserves byte length."""
        if len(self.orig) != len(self.new):
            msg = f"edit at {self.vaddr:#x} changes length ({len(self.orig)} != {len(self.new)})"
            raise PatchError(msg)


class CaveAllocator:
    """16-byte-aligned allocator over a verified executable `0xCC` padding cave."""

    def __init__(self, elf: Elf64Image, cave_lo: int, cave_hi: int) -> None:
        """Verify the whole cave is executable `0xCC` padding before allocating stubs."""
        if cave_hi <= cave_lo or not elf.is_executable_vaddr(cave_lo, cave_hi - cave_lo):
            msg = f"cave {cave_lo:#x}-{cave_hi:#x} is not executable"
            raise PatchError(msg)
        raw = elf.read_vaddr(cave_lo, cave_hi - cave_lo)
        if set(raw) != {INT3_BYTE}:
            msg = f"cave {cave_lo:#x}-{cave_hi:#x} is not all int3; refusing to patch"
            raise PatchError(msg)
        self.lo = cave_lo
        self.hi = cave_hi
        self.pc = align16(cave_lo)

    def emit(self, stub: bytes) -> tuple[int, Edit]:
        """Allocate `stub` in the cave and return `(stub_vaddr, Edit)`."""
        addr = self.pc
        if addr + len(stub) > self.hi:
            msg = f"cave {self.lo:#x}-{self.hi:#x} too small for {len(stub)}-byte stub"
            raise PatchError(msg)
        self.pc = align16(addr + len(stub))
        return addr, Edit(vaddr=addr, orig=bytes([INT3_BYTE]) * len(stub), new=stub)


def _hook_jump(hook_vaddr: int, orig: bytes, stub_vaddr: int) -> bytes:
    if len(orig) < JMP_REL32_LEN:
        msg = f"hook at {hook_vaddr:#x} is shorter than {JMP_REL32_LEN} bytes"
        raise PatchError(msg)
    return jmp_rel32(hook_vaddr, stub_vaddr) + nop_sled(len(orig) - JMP_REL32_LEN)


def _build_notelemetry_edits(targets: NoTelemetryTargets, cave: CaveAllocator) -> list[Edit]:
    ls_stub_addr = cave.pc
    ls_body = bytearray(targets.ls_hook.replay)
    ls_body += mov_rcx_disp_byte_imm(targets.disable_telemetry_offset, 1)
    ls_body += jmp_rel32(
        ls_stub_addr + len(ls_body), targets.ls_hook.vaddr + len(targets.ls_hook.orig)
    )
    _, ls_cave_edit = cave.emit(bytes(ls_body))

    main_stub_addr = cave.pc
    main_body = bytearray(targets.main_hook.replay)
    main_body += mov_rip_byte_imm(
        main_stub_addr + len(main_body),
        targets.main_disable_telemetry_vaddr,
        1,
    )
    main_body += jmp_rel32(
        main_stub_addr + len(main_body),
        targets.main_hook.vaddr + len(targets.main_hook.orig),
    )
    _, main_cave_edit = cave.emit(bytes(main_body))

    return [
        ls_cave_edit,
        Edit(
            vaddr=targets.ls_hook.vaddr,
            orig=targets.ls_hook.orig,
            new=_hook_jump(targets.ls_hook.vaddr, targets.ls_hook.orig, ls_stub_addr),
        ),
        main_cave_edit,
        Edit(
            vaddr=targets.main_hook.vaddr,
            orig=targets.main_hook.orig,
            new=_hook_jump(targets.main_hook.vaddr, targets.main_hook.orig, main_stub_addr),
        ),
    ]


def _dynamic_discovery_manifest(targets: DynamicTargets) -> dict[str, Any]:
    info: dict[str, Any] = {}
    if targets.cave is not None:
        info["cave"] = [hex(targets.cave[0]), hex(targets.cave[1])]
    if targets.notelemetry is not None:
        nt = targets.notelemetry
        info["notelemetry"] = {
            "ls_hook": hex(nt.ls_hook.vaddr),
            "disable_telemetry_offset": hex(nt.disable_telemetry_offset),
            "main_hook": hex(nt.main_hook.vaddr),
            "main_disable_telemetry": hex(nt.main_disable_telemetry_vaddr),
        }
    if targets.noautoupdate is not None:
        na = targets.noautoupdate
        info["noautoupdate"] = {
            "update_gate": hex(na.gate_vaddr),
            "update_disabled": hex(na.disabled_vaddr),
        }
    if targets.quietwatcher is not None:
        info["quietwatcher"] = {"watcher_call": hex(targets.quietwatcher.call_vaddr)}
    return info


def plan_dynamic(elf: Elf64Image, patches: Sequence[str]) -> tuple[list[Edit], dict[str, Any]]:
    """Plan edits using dynamic `pclntab` and x86-64 disassembly discovery."""
    targets = discover_targets(elf, patches)
    edits: list[Edit] = []

    if targets.notelemetry is not None:
        if targets.cave is None:
            msg = "internal error: missing cave for notelemetry"
            raise PatchError(msg)
        cave = CaveAllocator(elf, targets.cave[0], targets.cave[1])
        edits.extend(_build_notelemetry_edits(targets.notelemetry, cave))

    if targets.noautoupdate is not None:
        na = targets.noautoupdate
        edits.append(
            Edit(
                vaddr=na.gate_vaddr,
                orig=na.gate_orig,
                new=_hook_jump(na.gate_vaddr, na.gate_orig, na.disabled_vaddr),
            )
        )

    if targets.quietwatcher is not None:
        qw = targets.quietwatcher
        edits.append(
            Edit(
                vaddr=qw.call_vaddr,
                orig=qw.call_orig,
                new=nop_sled(len(qw.call_orig)),
            )
        )

    return edits, _dynamic_discovery_manifest(targets)


def _cmp_r11_str(body: bytearray, text: bytes, fixups: list[int]) -> None:
    if not text or len(text) > MAX_DISP8:
        msg = f"unsupported static prompt name length {len(text)} for {text!r}"
        raise PatchError(msg)
    off = 0
    while len(text) - off >= QWORD:
        body += b"\x49\xba" + text[off : off + QWORD]
        body += b"\x4d\x39\x13" if off == 0 else b"\x4d\x39\x53" + bytes([off])
        body += b"\x0f\x85\x00\x00\x00\x00"
        fixups.append(len(body) - 4)
        off += QWORD
    if len(text) - off >= DWORD:
        body += (b"\x41\x81\x3b" if off == 0 else b"\x41\x81\x7b" + bytes([off])) + text[
            off : off + DWORD
        ]
        body += b"\x0f\x85\x00\x00\x00\x00"
        fixups.append(len(body) - 4)
        off += DWORD
    if len(text) - off >= WORD:
        body += (b"\x66\x41\x81\x3b" if off == 0 else b"\x66\x41\x81\x7b" + bytes([off])) + text[
            off : off + WORD
        ]
        body += b"\x0f\x85\x00\x00\x00\x00"
        fixups.append(len(body) - 4)
        off += WORD
    if len(text) - off == 1:
        body += (b"\x41\x80\x3b" if off == 0 else b"\x41\x80\x7b" + bytes([off])) + text[
            off : off + 1
        ]
        body += b"\x0f\x85\x00\x00\x00\x00"
        fixups.append(len(body) - 4)


def _patch_rel32(body: bytearray, fixups: list[int], target: int) -> None:
    for off in fixups:
        body[off : off + 4] = struct.pack("<i", target - (off + 4))


def _pinned_static_prompts(build: dict[str, Any], cave: CaveAllocator) -> list[Edit]:
    edits: list[Edit] = []
    entries = build["static_prompts"]
    for _name, content_addr, static_addr in entries:
        content_orig = (
            lea_rip(b"\x48\x8d\x05", content_addr, build["static_string_itab"])
            + lea_rip(b"\x48\x8d\x1d", content_addr + 7, static_addr)
            + b"\xc3"
        )
        content_new = (
            lea_rip(b"\x48\x8d\x05", content_addr, build["template_source_itab"])
            + lea_rip(b"\x48\x8d\x1d", content_addr + 7, build["template_source_zero"])
            + b"\xc3"
        )
        edits.append(Edit(content_addr, content_orig, content_new))

    pc = cave.pc
    hook = build["embed_read_hook"]
    orig = bytes.fromhex(build["embed_read_orig"])
    body = bytearray()
    done_fixups: list[int] = []
    load_fixups: list[int] = []

    body += b"\x48\x85\xff\x0f\x84\x00\x00\x00\x00"
    done_fixups.append(len(body) - 4)
    subdir = b"system_prompts"
    body += b"\x48\x83\x7c\x24\x30" + bytes([len(subdir)])
    body += b"\x0f\x85\x00\x00\x00\x00"
    done_fixups.append(len(body) - 4)
    body += b"\x4c\x8b\x5c\x24\x48"
    _cmp_r11_str(body, subdir, done_fixups)

    body += b"\x4c\x8b\x9c\x24\x48\x01\x00\x00"
    for name, _content_addr, static_addr in entries:
        name_b = name.encode("ascii")
        next_fixups: list[int] = []
        body += b"\x48\x83\xbc\x24\x50\x01\x00\x00" + bytes([len(name_b)])
        body += b"\x0f\x85\x00\x00\x00\x00"
        next_fixups.append(len(body) - 4)
        _cmp_r11_str(body, name_b, next_fixups)
        body += lea_rip(b"\x4c\x8d\x1d", pc + len(body), static_addr)
        body += b"\xe9\x00\x00\x00\x00"
        load_fixups.append(len(body) - 4)
        _patch_rel32(body, next_fixups, len(body))

    body += b"\xe9\x00\x00\x00\x00"
    done_fixups.append(len(body) - 4)
    _patch_rel32(body, load_fixups, len(body))
    body += b"\x49\x8b\x03\x49\x8b\x5b\x08\x31\xff\x31\xf6"
    _patch_rel32(body, done_fixups, len(body))
    body += orig
    body += jmp_rel32(pc + len(body), hook + len(orig))

    _, cave_edit = cave.emit(bytes(body))
    edits.append(cave_edit)
    edits.append(Edit(hook, orig, _hook_jump(hook, orig, pc)))
    return edits


def _pinned_ls_entry(
    build: dict[str, Any], cave: CaveAllocator, patches: Sequence[str]
) -> list[Edit]:
    hook, orig = build["ls_hook"], bytes.fromhex(build["ls_orig"])
    pc = cave.pc
    body = bytearray(orig[:11])
    if "devmode" in patches:
        body += mov_rcx_disp_byte_imm(OPTS_DEVMODE, 1)
    if "notelemetry" in patches:
        body += mov_rcx_disp_byte_imm(OPTS_DISABLE_TELEMETRY, 1)
    body += jmp_rel32(pc + len(body), hook + len(orig))
    _, cave_edit = cave.emit(bytes(body))
    return [cave_edit, Edit(hook, orig, _hook_jump(hook, orig, pc))]


def _pinned_main_entry(build: dict[str, Any], cave: CaveAllocator) -> list[Edit]:
    hook, orig = build["main_hook"], bytes.fromhex(build["main_orig"])
    pc = cave.pc
    body = bytearray(orig)
    body += mov_rip_byte_imm(pc + len(body), build["main_opts"] + OPTS_DISABLE_TELEMETRY, 1)
    body += jmp_rel32(pc + len(body), hook + len(orig))
    _, cave_edit = cave.emit(bytes(body))
    return [cave_edit, Edit(hook, orig, _hook_jump(hook, orig, pc))]


def _pinned_static_edits(build: dict[str, Any], patches: Sequence[str]) -> list[Edit]:
    edits: list[Edit] = []
    if "noautoupdate" in patches:
        hook = build["update_gate"]
        orig = bytes.fromhex(build["update_orig"])
        edits.append(Edit(hook, orig, _hook_jump(hook, orig, build["update_disabled"])))
    if "quietwatcher" in patches:
        orig = bytes.fromhex(build["watcher_orig"])
        edits.append(Edit(build["watcher_call"], orig, nop_sled(len(orig))))
    if "agygating" in patches:
        monitors = build.get("monitors")
        if not monitors:
            msg = f"patch set 'agygating' is not supported on agy {build['version']}"
            raise PatchError(msg)
        edits.extend(Edit(off, orig, new) for off, orig, new in monitors)
    if "testjmp" in patches:
        addr = build.get("test_jmp_addr")
        orig_hex = build.get("test_jmp_orig")
        if addr is None or not orig_hex:
            msg = f"patch set 'testjmp' is not supported on agy {build['version']}"
            raise PatchError(msg)
        orig = bytes.fromhex(orig_hex)
        edits.append(Edit(addr, orig, b"\x31\xc0" + nop_sled(len(orig) - 2)))
    return edits


def plan_pinned(elf: Elf64Image, build: dict[str, Any], patches: Sequence[str]) -> list[Edit]:
    """Plan edits using a sha256-pinned `BUILDS` table entry."""
    cave_lo, cave_hi = build["cave"]
    cave = CaveAllocator(elf, cave_lo, cave_hi)
    edits: list[Edit] = []
    if "devmode" in patches or "notelemetry" in patches:
        edits.extend(_pinned_ls_entry(build, cave, patches))
    if "notelemetry" in patches:
        edits.extend(_pinned_main_entry(build, cave))
    edits.extend(_pinned_static_edits(build, patches))
    if "staticprompts" in patches:
        if not build.get("static_prompts"):
            msg = f"patch set 'staticprompts' is not supported on agy {build['version']}"
            raise PatchError(msg)
        edits.extend(_pinned_static_prompts(build, cave))
    return edits


def plan_edits(
    elf: Elf64Image,
    sha256: str,
    patches: Sequence[str],
    version_hint: str | None = None,
) -> tuple[list[Edit], str, str, dict[str, Any] | None]:
    """Select dynamic discovery or pinned planning according to `patches`."""
    pinned_only = [p for p in patches if p not in DYNAMIC_PATCHES]
    if not pinned_only:
        edits, discovered = plan_dynamic(elf, patches)
        version = version_hint or (BUILDS[sha256]["version"] if sha256 in BUILDS else "unknown")
        return edits, "dynamic", version, discovered

    if sha256 not in BUILDS:
        pinned_list = ",".join(pinned_only)
        dyn_list = ",".join(DYNAMIC_PATCHES)
        msg = (
            f"unknown agy build (sha256 {sha256}) for pinned patch set(s) [{pinned_list}]; "
            f"add a BUILDS entry or restrict --patches to dynamic sets ({dyn_list})"
        )
        raise PatchError(msg)
    build = BUILDS[sha256]
    return plan_pinned(elf, build, patches), "pinned", str(build["version"]), None


def apply_edits(elf: Elf64Image, data: bytearray, edits: Sequence[Edit]) -> list[tuple[Edit, int]]:
    """Validate every edit against `data` without partial mutation, then apply all edits."""
    resolved: list[tuple[Edit, int]] = []
    occupied: list[tuple[int, int]] = []

    for edit in edits:
        off = elf.vaddr_to_offset(edit.vaddr, len(edit.orig))
        end = off + len(edit.orig)
        for prev_start, prev_end in occupied:
            if off < prev_end and prev_start < end:
                msg = f"overlapping edits at file offset {off:#x}..{end:#x}"
                raise PatchError(msg)
        occupied.append((off, end))

        cur = bytes(data[off:end])
        if cur != edit.orig:
            msg = (
                f"bytes at {edit.vaddr:#x} (off {off:#x}) are {cur.hex()}, "
                f"expected {edit.orig.hex()}; refusing to patch"
            )
            raise PatchError(msg)
        resolved.append((edit, off))

    for edit, off in resolved:
        data[off : off + len(edit.new)] = edit.new
    return resolved
