# Copyright (c) 2026 Bad3r

"""x86-64 Capstone disassembly wrappers and fail-closed machine-code encoders."""

from __future__ import annotations

import struct
from dataclasses import dataclass
from typing import TYPE_CHECKING, Protocol, cast

from _agy_patcher.elf import DiscoveryError, PatchError

if TYPE_CHECKING:
    from collections.abc import Iterable, Sequence

    from _agy_patcher.elf import Elf64Image

ALIGN_BOUNDARY = 16
REL32_MIN = -(1 << 31)
REL32_MAX = (1 << 31) - 1
DISP8_MIN = -128
DISP8_MAX = 127
U8_MAX = 0xFF
BYTE_SIZE = 1
BINARY_OP_COUNT = 2
JMP_REL32_LEN = 5
MOV_RIP_BYTE_LEN = 7
RCX_DISP8_MODRM = 0x41
RCX_DISP32_MODRM = 0x81
MOV_RM8_IMM8_OPCODE = 0xC6
MOV_RIP_BYTE_MODRM = 0x05

# Canonical Intel/AMD multi-byte NOP encodings indexed by length (1..9).
CANONICAL_NOPS: dict[int, bytes] = {
    1: bytes.fromhex("90"),
    2: bytes.fromhex("6690"),
    3: bytes.fromhex("0f1f00"),
    4: bytes.fromhex("0f1f4000"),
    5: bytes.fromhex("0f1f440000"),
    6: bytes.fromhex("660f1f440000"),
    7: bytes.fromhex("0f1f8000000000"),
    8: bytes.fromhex("0f1f840000000000"),
    9: bytes.fromhex("660f1f840000000000"),
}
MAX_CANONICAL_NOP_LEN = 9


def align16(addr: int) -> int:
    """Round `addr` up to the next 16-byte boundary."""
    return (addr + ALIGN_BOUNDARY - 1) & ~(ALIGN_BOUNDARY - 1)


def nop_sled(length: int) -> bytes:
    """Return a canonical multi-byte x86-64 NOP sled of exactly `length` bytes."""
    if length < 0:
        msg = f"negative NOP length {length}"
        raise PatchError(msg)
    out = bytearray()
    remaining = length
    while remaining > 0:
        chunk = min(remaining, MAX_CANONICAL_NOP_LEN)
        out += CANONICAL_NOPS[chunk]
        remaining -= chunk
    return bytes(out)


def _pack_rel32(rel: int, context: str) -> bytes:
    if not (REL32_MIN <= rel <= REL32_MAX):
        msg = f"{context}: rel32 displacement {rel:#x} out of signed 32-bit range"
        raise PatchError(msg)
    return struct.pack("<i", rel)


def jmp_rel32(src: int, dst: int) -> bytes:
    """Encode a 5-byte relative `jmp dst` located at `src`."""
    return b"\xe9" + _pack_rel32(dst - (src + JMP_REL32_LEN), f"jmp {src:#x}->{dst:#x}")


def mov_rcx_disp_byte_imm(disp: int, imm: int) -> bytes:
    """Encode `mov BYTE PTR [rcx + disp], imm` using disp8 when possible."""
    if not (0 <= imm <= U8_MAX):
        msg = f"byte immediate {imm:#x} out of range"
        raise PatchError(msg)
    if DISP8_MIN <= disp <= DISP8_MAX:
        return struct.pack("<BBbB", MOV_RM8_IMM8_OPCODE, RCX_DISP8_MODRM, disp, imm)
    return struct.pack("<BBiB", MOV_RM8_IMM8_OPCODE, RCX_DISP32_MODRM, disp, imm)


def mov_rip_byte_imm(ins_addr: int, target: int, imm: int) -> bytes:
    """Encode `mov BYTE PTR [rip + rel32], imm` targeting `target`."""
    if not (0 <= imm <= U8_MAX):
        msg = f"byte immediate {imm:#x} out of range"
        raise PatchError(msg)
    rel = target - (ins_addr + MOV_RIP_BYTE_LEN)
    return (
        bytes([MOV_RM8_IMM8_OPCODE, MOV_RIP_BYTE_MODRM])
        + _pack_rel32(rel, f"mov_rip {ins_addr:#x}->{target:#x}")
        + bytes([imm])
    )


@dataclass(frozen=True)
class Instruction:
    """Decoded x86-64 instruction summary without leaking Capstone types."""

    address: int
    size: int
    mnemonic: str
    raw: bytes
    rip_target: int | None
    imm_target: int | None
    uses_rip: bool
    is_relative_flow: bool
    is_xmm15_rsp_store: bool
    is_test_rcx_al: bool
    is_mov_rsp_disp_zero: bool
    is_cmp_rip_zero: bool
    is_test_dl_dl: bool


class _CsMem(Protocol):
    base: int
    index: int
    segment: int
    disp: int


class _CsOp(Protocol):
    type: int
    size: int
    reg: int
    imm: int
    mem: _CsMem


class _CsInsn(Protocol):
    address: int
    size: int
    mnemonic: str
    bytes: bytearray | bytes
    operands: list[_CsOp]
    groups: list[int]


class _CsDisassembler(Protocol):
    detail: bool

    def disasm(self, code: bytes, offset: int) -> Iterable[_CsInsn]: ...


class _CsModule(Protocol):
    CS_ARCH_X86: int
    CS_MODE_64: int
    CS_GRP_JUMP: int
    CS_GRP_CALL: int
    CS_GRP_BRANCH_RELATIVE: int

    def Cs(self, arch: int, mode: int) -> _CsDisassembler: ...  # noqa: N802


class _CsX86Module(Protocol):
    X86_OP_MEM: int
    X86_OP_REG: int
    X86_OP_IMM: int
    X86_REG_INVALID: int
    X86_REG_RIP: int
    X86_REG_RSP: int
    X86_REG_XMM15: int
    X86_REG_RCX: int
    X86_REG_AL: int
    X86_REG_DL: int


def _import_capstone() -> tuple[_CsModule, _CsX86Module]:
    try:
        import capstone  # noqa: PLC0415  # pyright: ignore[reportMissingTypeStubs]
        from capstone import x86 as cs_x86  # noqa: PLC0415  # pyright: ignore[reportMissingTypeStubs]
    except ImportError as exc:
        msg = (
            "capstone is required for dynamic discovery; run with nixpkgs python3Packages.capstone"
        )
        raise DiscoveryError(msg) from exc
    return cast("tuple[_CsModule, _CsX86Module]", (capstone, cs_x86))


def _extract_targets(
    cs_insn: _CsInsn, capstone: _CsModule, cs_x86: _CsX86Module
) -> tuple[int | None, int | None, bool, bool]:
    rip_target: int | None = None
    imm_target: int | None = None
    uses_rip = False

    for op in cs_insn.operands:
        if op.type == cs_x86.X86_OP_MEM and op.mem.base == cs_x86.X86_REG_RIP:
            uses_rip = True
            rip_target = cs_insn.address + cs_insn.size + op.mem.disp
        elif op.type == cs_x86.X86_OP_IMM:
            imm_target = op.imm

    flow_groups = {
        capstone.CS_GRP_JUMP,
        capstone.CS_GRP_CALL,
        capstone.CS_GRP_BRANCH_RELATIVE,
    }
    is_rel_flow = bool(set(cs_insn.groups) & flow_groups)
    return rip_target, imm_target, uses_rip, is_rel_flow


def _classify_patterns(
    cs_insn: _CsInsn, cs_x86: _CsX86Module
) -> tuple[bool, bool, bool, bool, bool]:
    ops = cs_insn.operands
    mnem = cs_insn.mnemonic
    two_ops = len(ops) == BINARY_OP_COUNT

    is_xmm15_rsp_store = (
        mnem == "movups"
        and two_ops
        and ops[0].type == cs_x86.X86_OP_MEM
        and ops[0].mem.base == cs_x86.X86_REG_RSP
        and ops[0].mem.index == cs_x86.X86_REG_INVALID
        and ops[0].mem.segment == cs_x86.X86_REG_INVALID
        and ops[1].type == cs_x86.X86_OP_REG
        and ops[1].reg == cs_x86.X86_REG_XMM15
    )
    is_test_rcx_al = (
        mnem == "test"
        and two_ops
        and ops[0].type == cs_x86.X86_OP_MEM
        and ops[0].size == BYTE_SIZE
        and ops[0].mem.base == cs_x86.X86_REG_RCX
        and ops[0].mem.index == cs_x86.X86_REG_INVALID
        and ops[0].mem.disp == 0
        and ops[1].type == cs_x86.X86_OP_REG
        and ops[1].reg == cs_x86.X86_REG_AL
    )
    is_mov_rsp_disp_zero = (
        mnem == "mov"
        and two_ops
        and ops[0].type == cs_x86.X86_OP_MEM
        and ops[0].size == BYTE_SIZE
        and ops[0].mem.base == cs_x86.X86_REG_RSP
        and ops[0].mem.index == cs_x86.X86_REG_INVALID
        and ops[1].type == cs_x86.X86_OP_IMM
        and ops[1].imm == 0
    )
    is_cmp_rip_zero = (
        mnem == "cmp"
        and two_ops
        and ops[0].type == cs_x86.X86_OP_MEM
        and ops[0].size == BYTE_SIZE
        and ops[0].mem.base == cs_x86.X86_REG_RIP
        and ops[0].mem.index == cs_x86.X86_REG_INVALID
        and ops[1].type == cs_x86.X86_OP_IMM
        and ops[1].imm == 0
    )
    is_test_dl_dl = (
        mnem == "test"
        and two_ops
        and ops[0].type == cs_x86.X86_OP_REG
        and ops[0].reg == cs_x86.X86_REG_DL
        and ops[1].type == cs_x86.X86_OP_REG
        and ops[1].reg == cs_x86.X86_REG_DL
    )
    return (
        is_xmm15_rsp_store,
        is_test_rcx_al,
        is_mov_rsp_disp_zero,
        is_cmp_rip_zero,
        is_test_dl_dl,
    )


class Disassembler:
    """Lazy-initialized Capstone x86-64 disassembler."""

    def __init__(self) -> None:
        """Configure Capstone x86-64 decoder with operand detail enabled."""
        capstone, cs_x86 = _import_capstone()
        self._capstone = capstone
        self._cs_x86 = cs_x86
        self._cs = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
        self._cs.detail = True

    def disasm_range(self, elf: Elf64Image, start: int, end: int) -> list[Instruction]:
        """Disassemble `[start, end)` from `elf` into structured `Instruction` records."""
        if end <= start:
            msg = f"invalid disassembly range {start:#x}..{end:#x}"
            raise DiscoveryError(msg)
        code = elf.read_vaddr(start, end - start)
        return self.disasm_bytes(code, start)

    def disasm_bytes(self, code: bytes, base_addr: int) -> list[Instruction]:
        """Disassemble raw `code` assuming virtual base address `base_addr`."""
        out: list[Instruction] = []
        for insn in self._cs.disasm(code, base_addr):
            rip_target, imm_target, uses_rip, is_rel_flow = _extract_targets(
                insn, self._capstone, self._cs_x86
            )
            (
                is_xmm15_rsp_store,
                is_test_rcx_al,
                is_mov_rsp_disp_zero,
                is_cmp_rip_zero,
                is_test_dl_dl,
            ) = _classify_patterns(insn, self._cs_x86)
            out.append(
                Instruction(
                    address=insn.address,
                    size=insn.size,
                    mnemonic=insn.mnemonic,
                    raw=bytes(insn.bytes),
                    rip_target=rip_target,
                    imm_target=imm_target,
                    uses_rip=uses_rip,
                    is_relative_flow=is_rel_flow,
                    is_xmm15_rsp_store=is_xmm15_rsp_store,
                    is_test_rcx_al=is_test_rcx_al,
                    is_mov_rsp_disp_zero=is_mov_rsp_disp_zero,
                    is_cmp_rip_zero=is_cmp_rip_zero,
                    is_test_dl_dl=is_test_dl_dl,
                )
            )
        return out


def assert_position_independent(insns: Sequence[Instruction], label: str) -> None:
    """Fail if any replayed instruction depends on RIP-relative addressing or flow."""
    for insn in insns:
        if insn.uses_rip or insn.is_relative_flow:
            msg = (
                f"{label}: instruction at {insn.address:#x} ({insn.mnemonic}) is not "
                "position-independent and cannot be relocated to a cave"
            )
            raise DiscoveryError(msg)
