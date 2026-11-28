# Copyright (c) 2026 Bad3r

"""Dynamic build-time patch planning and atomic validation for `agy` binaries."""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING, Any

from _agy_patcher.discover import discover_targets
from _agy_patcher.elf import INT3_BYTE, PatchError
from _agy_patcher.x86 import (
    JMP_REL32_LEN,
    align16,
    jmp_rel32,
    mov_rcx_disp_byte_imm,
    mov_rip_byte_imm,
    nop_sled,
)

if TYPE_CHECKING:
    from collections.abc import Sequence

    from _agy_patcher.discover import DynamicTargets, NoTelemetryTargets
    from _agy_patcher.elf import Elf64Image

PATCH_SETS: tuple[str, ...] = (
    "notelemetry",
    "noautoupdate",
    "quietwatcher",
)


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


def plan_edits(elf: Elf64Image, patches: Sequence[str]) -> tuple[list[Edit], dict[str, Any]]:
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
