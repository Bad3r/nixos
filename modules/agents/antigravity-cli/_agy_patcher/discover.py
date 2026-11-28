# Copyright (c) 2026 Bad3r

"""Fail-closed structural discovery of `agy` patch targets."""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING

from _agy_patcher.elf import DiscoveryError
from _agy_patcher.go_meta import GO_KIND_BOOL, GoMetadata, find_struct_field_offset
from _agy_patcher.x86 import JMP_REL32_LEN, Disassembler, assert_position_independent

if TYPE_CHECKING:
    from collections.abc import Sequence

    from _agy_patcher.elf import Elf64Image
    from _agy_patcher.x86 import Instruction

FN_CREATE_LS = (
    "google3/third_party/jetski/language_server/language_server.CreateLanguageServerAndServe"
)
FN_MAIN = "main.main"
FN_RECORD_PLUGIN_EVENTS = "main.recordPluginSubcommandEvents"
FN_TRIGGER_UPDATE = "google3/third_party/jetski/cli/updater/updater.triggerUpdateShared"
FN_WATCHER_LISTEN = (
    "google3/third_party/jetski/fs/file_watcher/file_watcher."
    "(*FileWatcherDefault).listenAndForwardEvents"
)
FN_CTXLOGF = "google3/base/go/log.ctxlogf"

STR_UPDATE_DISABLED = b"Auto-update disabled via environment variable"
STR_WATCHER_SKIP = b"skipping empty or temp file: %s"

LS_HEAD_WINDOW = 0x100
MAIN_HEAD_WINDOW = 0x100
RECORD_PLUGIN_HEAD_WINDOW = 0x80
UPDATE_BLOCK_WINDOW = 0x100
WATCHER_LOOKBACK = 6
JNE_REL32_LEN = 6
MIN_CAVE_BYTES = 128


@dataclass(frozen=True)
class HookSite:
    """Instruction sequence replaced by a cave jump and replayed inside the cave."""

    vaddr: int
    orig: bytes
    replay: bytes


@dataclass(frozen=True)
class NoTelemetryTargets:
    """Discovered addresses and field offsets for the `notelemetry` patch set."""

    ls_hook: HookSite
    disable_telemetry_offset: int
    main_hook: HookSite
    main_disable_telemetry_vaddr: int


@dataclass(frozen=True)
class NoAutoUpdateTargets:
    """Discovered addresses for the `noautoupdate` patch set."""

    gate_vaddr: int
    gate_orig: bytes
    disabled_vaddr: int


@dataclass(frozen=True)
class QuietWatcherTargets:
    """Discovered log call site for the `quietwatcher` patch set."""

    call_vaddr: int
    call_orig: bytes


@dataclass(frozen=True)
class DynamicTargets:
    """Aggregate of dynamically discovered targets for requested patch sets."""

    cave: tuple[int, int] | None
    notelemetry: NoTelemetryTargets | None
    noautoupdate: NoAutoUpdateTargets | None
    quietwatcher: QuietWatcherTargets | None


def exactly_one[T](items: Sequence[T], description: str) -> T:
    """Require `items` to hold a unique element, raising DiscoveryError otherwise."""
    if len(items) != 1:
        msg = f"expected 1 match for {description}, found {len(items)}"
        raise DiscoveryError(msg)
    return items[0]


def _discover_ls_hook(elf: Elf64Image, go: GoMetadata, disasm: Disassembler) -> HookSite:
    fn = go.func(FN_CREATE_LS)
    insns = disasm.disasm_range(elf, fn.start, min(fn.start + LS_HEAD_WINDOW, fn.end))
    candidates: list[HookSite] = []
    for idx in range(len(insns) - 1):
        first, second = insns[idx], insns[idx + 1]
        if not (first.is_xmm15_rsp_store and second.is_test_rcx_al):
            continue
        assert_position_independent((first, second), "CreateLanguageServerAndServe hook")
        tail_idx = idx + 2
        while tail_idx < len(insns) and insns[tail_idx].mnemonic == "nop":
            tail_idx += 1
        orig = b"".join(insn.raw for insn in insns[idx:tail_idx])
        if len(orig) < JMP_REL32_LEN:
            continue
        candidates.append(HookSite(vaddr=first.address, orig=orig, replay=first.raw + second.raw))
    return exactly_one(candidates, "CreateLanguageServerAndServe entry hook")


def _discover_main_hook(elf: Elf64Image, go: GoMetadata, disasm: Disassembler) -> HookSite:
    fn = go.func(FN_MAIN)
    insns = disasm.disasm_range(elf, fn.start, min(fn.start + MAIN_HEAD_WINDOW, fn.end))
    candidates: list[HookSite] = []
    for insn in insns:
        if insn.is_mov_rsp_disp_zero and insn.size >= JMP_REL32_LEN:
            assert_position_independent((insn,), "main.main entry hook")
            candidates.append(HookSite(vaddr=insn.address, orig=insn.raw, replay=insn.raw))
    return exactly_one(candidates, "main.main open-coded defer init hook")


def _discover_main_disable_telemetry(elf: Elf64Image, go: GoMetadata, disasm: Disassembler) -> int:
    fn = go.func(FN_RECORD_PLUGIN_EVENTS)
    insns = disasm.disasm_range(elf, fn.start, min(fn.start + RECORD_PLUGIN_HEAD_WINDOW, fn.end))
    targets: list[int] = [
        insn.rip_target for insn in insns if insn.is_cmp_rip_zero and insn.rip_target is not None
    ]
    target = exactly_one(targets, "main.recordPluginSubcommandEvents DisableTelemetry cmp")
    if not elf.is_writable_vaddr(target, 1):
        msg = f"discovered main Options.DisableTelemetry {target:#x} is not writable"
        raise DiscoveryError(msg)
    return target


def discover_notelemetry(
    elf: Elf64Image, go: GoMetadata, disasm: Disassembler
) -> NoTelemetryTargets:
    """Locate all hook sites and telemetry flags for `notelemetry`."""
    ls_hook = _discover_ls_hook(elf, go, disasm)
    disable_offset = find_struct_field_offset(
        elf=elf,
        first_field_name="EnvironmentConfig",
        target_field_name="DisableTelemetry",
        expected_kind=GO_KIND_BOOL,
        expected_size=1,
    )
    main_hook = _discover_main_hook(elf, go, disasm)
    main_dt_va = _discover_main_disable_telemetry(elf, go, disasm)
    return NoTelemetryTargets(
        ls_hook=ls_hook,
        disable_telemetry_offset=disable_offset,
        main_hook=main_hook,
        main_disable_telemetry_vaddr=main_dt_va,
    )


def discover_noautoupdate(
    elf: Elf64Image, go: GoMetadata, disasm: Disassembler
) -> NoAutoUpdateTargets:
    """Locate the auto-update gate branch and disabled-by-env block in `triggerUpdateShared`."""
    fn = go.func(FN_TRIGGER_UPDATE)
    insns = disasm.disasm_range(elf, fn.start, fn.end)
    disabled_str_va = elf.find_unique_bytes(STR_UPDATE_DISABLED)

    candidates: list[NoAutoUpdateTargets] = []
    for idx in range(len(insns) - 1):
        test_insn, jne_insn = insns[idx], insns[idx + 1]
        if not (
            test_insn.is_test_dl_dl
            and jne_insn.mnemonic == "jne"
            and jne_insn.size == JNE_REL32_LEN
            and jne_insn.imm_target is not None
        ):
            continue
        target = jne_insn.imm_target
        if not (fn.start <= target < fn.end):
            continue
        block: list[Instruction] = [
            insn for insn in insns if target <= insn.address < target + UPDATE_BLOCK_WINDOW
        ]
        if any(insn.rip_target == disabled_str_va for insn in block):
            orig = test_insn.raw + jne_insn.raw
            if len(orig) < JMP_REL32_LEN:
                continue
            candidates.append(
                NoAutoUpdateTargets(
                    gate_vaddr=test_insn.address,
                    gate_orig=orig,
                    disabled_vaddr=target,
                )
            )
    return exactly_one(candidates, "updater.triggerUpdateShared disabled-by-env gate")


def discover_quietwatcher(
    elf: Elf64Image, go: GoMetadata, disasm: Disassembler
) -> QuietWatcherTargets:
    """Locate the `file_watcher` shutdown log call in `listenAndForwardEvents`."""
    watcher_fn = go.func(FN_WATCHER_LISTEN)
    ctxlogf_fn = go.func(FN_CTXLOGF)
    insns = disasm.disasm_range(elf, watcher_fn.start, watcher_fn.end)
    msg_va = elf.find_unique_bytes(STR_WATCHER_SKIP)

    candidates: list[QuietWatcherTargets] = []
    for idx, insn in enumerate(insns):
        if (
            insn.mnemonic == "call"
            and insn.size == JMP_REL32_LEN
            and insn.imm_target == ctxlogf_fn.start
        ):
            window = insns[max(0, idx - WATCHER_LOOKBACK) : idx]
            if any(prev.rip_target == msg_va for prev in window):
                candidates.append(QuietWatcherTargets(call_vaddr=insn.address, call_orig=insn.raw))
    return exactly_one(candidates, "FileWatcherDefault.listenAndForwardEvents log call")


def discover_targets(elf: Elf64Image, patches: Sequence[str]) -> DynamicTargets:
    """Discover only the binary locations required by `patches`."""
    go = GoMetadata.parse(elf)
    disasm = Disassembler()
    patch_set = set(patches)

    cave: tuple[int, int] | None = None
    notelemetry: NoTelemetryTargets | None = None
    if "notelemetry" in patch_set:
        notelemetry = discover_notelemetry(elf, go, disasm)
        cave = elf.find_exec_int3_cave(go.go_text_end, MIN_CAVE_BYTES)

    noautoupdate = discover_noautoupdate(elf, go, disasm) if "noautoupdate" in patch_set else None
    quietwatcher = discover_quietwatcher(elf, go, disasm) if "quietwatcher" in patch_set else None
    return DynamicTargets(
        cave=cave,
        notelemetry=notelemetry,
        noautoupdate=noautoupdate,
        quietwatcher=quietwatcher,
    )
