# Copyright (c) 2026 Bad3r

"""Go 1.20+ pclntab and runtime type metadata discovery for stripped ELF binaries."""

from __future__ import annotations

import re
import struct
from dataclasses import dataclass
from typing import TYPE_CHECKING

from _agy_patcher.elf import DiscoveryError

if TYPE_CHECKING:
    from _agy_patcher.elf import Elf64Image

PCLNTAB_MAGIC = b"\xf1\xff\xff\xff\x00\x00\x01\x08"
PCLNTAB_HDR_STRUCT = struct.Struct("<QQQQQQQQ")
FTAB_ENTRY_STRUCT = struct.Struct("<II")
FUNC_HDR_STRUCT = struct.Struct("<Ii")
CALL_REL32_STRUCT = struct.Struct("<i")
PTR_STRUCT = struct.Struct("<Q")

MIN_NFUNC = 100
MAX_NFUNC = 10_000_000
MAX_CALIBRATION_CODE_BYTES = 8_000_000
MAX_CALIBRATION_CALLS = 20_000
TEXT_BASE_SEARCH_LIMIT = 0x2000
TEXT_BASE_SEARCH_STEP = 0x10
MIN_CALIBRATION_HITS = 1000
CALIBRATION_DOMINANCE_FACTOR = 2
CALL_OPCODE = b"\xe8"
CALL_INSN_LEN = 5

VARINT_MAX_BYTES = 5
VARINT_DATA_MASK = 0x7F
VARINT_CONT_BIT = 0x80
VARINT_SHIFT_STEP = 7

GO_KIND_MASK = 0x1F
GO_KIND_BOOL = 1
GO_KIND_STRUCT = 25
GO_NAME_EXPORTED_FLAG = 0x01
GO_NAME_MAX_FLAG = 0x07
GO_NAME_MAX_SHORT_LEN = 127
RTYPE_SIZE_OFF = 0
RTYPE_KIND_OFF = 23
STRUCT_FIELDS_PTR_OFF = 56
STRUCT_FIELDS_LEN_OFF = 64
STRUCT_FIELDS_CAP_OFF = 72
STRUCT_FIELD_STRIDE = 24
STRUCT_FIELD_TYP_OFF = 8
STRUCT_FIELD_OFFSET_OFF = 16
MAX_STRUCT_FIELDS = 512


@dataclass(frozen=True)
class FuncRange:
    """Resolved Go function name and virtual address range [start, end)."""

    name: str
    start: int
    end: int


def read_go_name(data: bytes, offset: int) -> str | None:
    """Decode a Go `abi.Name` entry at `offset`, or return None if malformed."""
    if offset < 0 or offset + 2 > len(data):
        return None
    length = 0
    consumed = 0
    for idx in range(VARINT_MAX_BYTES):
        pos = offset + 1 + idx
        if pos >= len(data):
            return None
        byte = data[pos]
        length |= (byte & VARINT_DATA_MASK) << (VARINT_SHIFT_STEP * idx)
        consumed = idx + 1
        if (byte & VARINT_CONT_BIT) == 0:
            break
    else:
        return None
    str_start = offset + 1 + consumed
    str_end = str_start + length
    if str_end > len(data):
        return None
    try:
        return data[str_start:str_end].decode("utf-8")
    except UnicodeDecodeError:
        return None


def _find_pclntab_candidates(data: bytes) -> list[tuple[int, int, int, int]]:
    pos = 0
    candidates: list[tuple[int, int, int, int]] = []
    while True:
        base = data.find(PCLNTAB_MAGIC, pos)
        if base == -1:
            break
        pos = base + 1
        hdr_off = base + len(PCLNTAB_MAGIC)
        if hdr_off + PCLNTAB_HDR_STRUCT.size > len(data):
            continue
        nfunc, _, _, funcname_off, cu_off, filetab_off, pctab_off, pcln_off = (
            PCLNTAB_HDR_STRUCT.unpack_from(data, hdr_off)
        )
        if not (MIN_NFUNC < nfunc < MAX_NFUNC):
            continue
        if not (0 < funcname_off <= cu_off <= filetab_off <= pctab_off <= pcln_off):
            continue
        ftab_start = base + pcln_off
        ftab_end = ftab_start + (nfunc + 1) * FTAB_ENTRY_STRUCT.size
        if base + funcname_off >= len(data) or ftab_end > len(data):
            continue
        candidates.append((base, nfunc, funcname_off, pcln_off))

    if not candidates:
        msg = "no valid Go 1.20+ pclntab header found"
        raise DiscoveryError(msg)
    return candidates


def _read_ftab(data: bytes, ftab: int, nfunc: int) -> tuple[list[int], list[int]]:
    entries: list[int] = []
    func_offs: list[int] = []
    for idx in range(nfunc + 1):
        entry_off, func_off = FTAB_ENTRY_STRUCT.unpack_from(
            data, ftab + idx * FTAB_ENTRY_STRUCT.size
        )
        entries.append(entry_off)
        if idx < nfunc:
            func_offs.append(func_off)
    return entries, func_offs


@dataclass(frozen=True)
class _CalibratedPclntab:
    """Calibrated pclntab metadata matching the binary's `.text` section."""

    base: int
    funcname_off: int
    pcln_off: int
    text_base: int
    entries: list[int]
    func_offs: list[int]


def _read_functions(data: bytes, cal: _CalibratedPclntab) -> dict[str, FuncRange]:
    ftab = cal.base + cal.pcln_off
    name_table = cal.base + cal.funcname_off
    functions: dict[str, FuncRange] = {}
    for idx, func_off in enumerate(cal.func_offs):
        if ftab + func_off + FUNC_HDR_STRUCT.size > len(data):
            msg = f"pclntab function metadata {idx} out of bounds"
            raise DiscoveryError(msg)
        _, name_rel = FUNC_HDR_STRUCT.unpack_from(data, ftab + func_off)
        name_start = name_table + name_rel
        name_end = data.find(b"\x00", name_start)
        if name_start < 0 or name_end == -1:
            msg = f"pclntab function name {idx} unterminated"
            raise DiscoveryError(msg)
        name = data[name_start:name_end].decode("utf-8", "replace")
        functions[name] = FuncRange(
            name, cal.text_base + cal.entries[idx], cal.text_base + cal.entries[idx + 1]
        )
    return functions


def _calibrate_text_base(elf: Elf64Image, entries: list[int]) -> int:
    text = elf.section(".text")
    if text.offset + text.size > len(elf.data):
        msg = ".text section extends past EOF"
        raise DiscoveryError(msg)
    sample_limit = min(text.size, MAX_CALIBRATION_CODE_BYTES)
    code = elf.data[text.offset : text.offset + sample_limit]
    call_offsets: list[int] = []
    for match in re.finditer(CALL_OPCODE, code):
        off = match.start()
        if off + CALL_INSN_LEN <= len(code):
            call_offsets.append(off)
            if len(call_offsets) >= MAX_CALIBRATION_CALLS:
                break

    if not call_offsets:
        msg = "no CALL rel32 candidates found while calibrating Go text base"
        raise DiscoveryError(msg)

    entry_set = set(entries)
    targets = [
        text.addr + off + CALL_INSN_LEN + CALL_REL32_STRUCT.unpack_from(code, off + 1)[0]
        for off in call_offsets
    ]
    scored = sorted(
        (
            (sum(1 for target in targets if (target - (text.addr + delta)) in entry_set), delta)
            for delta in range(0, TEXT_BASE_SEARCH_LIMIT, TEXT_BASE_SEARCH_STEP)
        ),
        reverse=True,
    )
    best_hits, best_delta = scored[0]
    second_hits = scored[1][0] if len(scored) > 1 else 0
    if best_hits < MIN_CALIBRATION_HITS or best_hits <= CALIBRATION_DOMINANCE_FACTOR * second_hits:
        msg = (
            f"ambiguous Go text base calibration (best={best_hits} hits, second={second_hits} hits)"
        )
        raise DiscoveryError(msg)
    return text.addr + best_delta


class GoMetadata:
    """Parsed Go pclntab function table and calibrated text base."""

    def __init__(
        self,
        text_base: int,
        go_text_end: int,
        functions: dict[str, FuncRange],
    ) -> None:
        """Store calibrated Go function metadata."""
        self.text_base = text_base
        self.go_text_end = go_text_end
        self.functions = functions

    @classmethod
    def parse(cls, elf: Elf64Image) -> GoMetadata:
        """Parse Go 1.20+ pclntab entries and calibrate the text base."""
        data = elf.data
        candidates = _find_pclntab_candidates(data)
        calibrated: list[_CalibratedPclntab] = []
        for base, nfunc, funcname_off, pcln_off in candidates:
            entries, func_offs = _read_ftab(data, base + pcln_off, nfunc)
            try:
                text_base = _calibrate_text_base(elf, entries[:-1])
            except DiscoveryError:
                continue
            calibrated.append(
                _CalibratedPclntab(
                    base=base,
                    funcname_off=funcname_off,
                    pcln_off=pcln_off,
                    text_base=text_base,
                    entries=entries,
                    func_offs=func_offs,
                )
            )

        if len(calibrated) != 1:
            msg = f"expected 1 calibrated Go pclntab matching .text, found {len(calibrated)}"
            raise DiscoveryError(msg)

        winner = calibrated[0]
        functions = _read_functions(data, winner)
        return cls(
            text_base=winner.text_base,
            go_text_end=winner.text_base + winner.entries[-1],
            functions=functions,
        )

    def func(self, name: str) -> FuncRange:
        """Look up a Go function by full pclntab name."""
        fn = self.functions.get(name)
        if fn is None:
            msg = f"Go function {name!r} not found in pclntab"
            raise DiscoveryError(msg)
        return fn


def _candidate_field_name_vaddrs(elf: Elf64Image, field_name: str) -> set[int]:
    encoded = field_name.encode("utf-8")
    if not encoded or len(encoded) > GO_NAME_MAX_SHORT_LEN:
        msg = f"unsupported Go field name length for {field_name!r}"
        raise DiscoveryError(msg)

    suffix = bytes([len(encoded)]) + encoded
    vaddrs: set[int] = set()
    pos = 0
    while True:
        idx = elf.data.find(suffix, pos)
        if idx == -1:
            break
        pos = idx + 1
        if idx == 0:
            continue
        flag = elf.data[idx - 1]
        if (flag & GO_NAME_EXPORTED_FLAG) == 0 or flag > GO_NAME_MAX_FLAG:
            continue
        vaddr = elf.try_offset_to_vaddr(idx - 1, 1 + len(suffix))
        if vaddr is not None:
            vaddrs.add(vaddr)
    return vaddrs


@dataclass(frozen=True)
class _StructQuery:
    """Expected enclosing struct signature and target field type."""

    first_field_name: str
    expected_kind: int
    expected_size: int


@dataclass(frozen=True)
class _StructCandidate:
    """Candidate `abi.StructType` and target `StructField` virtual addresses."""

    fields_base_va: int
    target_field_va: int
    struct_type_va: int


def _read_struct_first_field(
    elf: Elf64Image, rel_map: dict[int, int], candidate: _StructCandidate
) -> str | None:
    try:
        st_off = elf.vaddr_to_offset(candidate.struct_type_va, STRUCT_FIELDS_CAP_OFF + 8)
    except DiscoveryError:
        return None
    if (elf.data[st_off + RTYPE_KIND_OFF] & GO_KIND_MASK) != GO_KIND_STRUCT:
        return None
    flen = PTR_STRUCT.unpack_from(elf.data, st_off + STRUCT_FIELDS_LEN_OFF)[0]
    fcap = PTR_STRUCT.unpack_from(elf.data, st_off + STRUCT_FIELDS_CAP_OFF)[0]
    if flen != fcap or not (1 <= flen <= MAX_STRUCT_FIELDS):
        return None
    first_name_va = rel_map.get(candidate.fields_base_va)
    if first_name_va is None:
        return None
    try:
        first_name_off = elf.vaddr_to_offset(first_name_va, 2)
    except DiscoveryError:
        return None
    return read_go_name(elf.data, first_name_off)


def _struct_field_offset_if_match(
    elf: Elf64Image,
    rel_map: dict[int, int],
    candidate: _StructCandidate,
    query: _StructQuery,
) -> int | None:
    first_name = _read_struct_first_field(elf, rel_map, candidate)
    if first_name != query.first_field_name:
        return None
    typ_va = rel_map.get(candidate.target_field_va + STRUCT_FIELD_TYP_OFF)
    if typ_va is None:
        return None
    try:
        typ_off = elf.vaddr_to_offset(typ_va, RTYPE_KIND_OFF + 1)
        field_off_pos = elf.vaddr_to_offset(candidate.target_field_va + STRUCT_FIELD_OFFSET_OFF, 8)
    except DiscoveryError:
        return None
    typ_size = PTR_STRUCT.unpack_from(elf.data, typ_off + RTYPE_SIZE_OFF)[0]
    typ_kind = elf.data[typ_off + RTYPE_KIND_OFF] & GO_KIND_MASK
    if typ_size != query.expected_size or typ_kind != query.expected_kind:
        return None
    return PTR_STRUCT.unpack_from(elf.data, field_off_pos)[0]


def find_struct_field_offset(
    elf: Elf64Image,
    first_field_name: str,
    target_field_name: str,
    expected_kind: int,
    expected_size: int,
) -> int:
    """Recover a Go struct field byte offset from `abi.StructType` RTTI metadata."""
    name_vaddrs = _candidate_field_name_vaddrs(elf, target_field_name)
    if not name_vaddrs:
        msg = f"no exported Go abi.Name entries found for {target_field_name!r}"
        raise DiscoveryError(msg)

    rel_map = elf.relative_relocations()
    field_vaddrs = [r_off for r_off, r_add in rel_map.items() if r_add in name_vaddrs]
    max_span = STRUCT_FIELD_STRIDE * MAX_STRUCT_FIELDS
    query = _StructQuery(first_field_name, expected_kind, expected_size)

    offsets: set[int] = set()
    for r_off, r_add in rel_map.items():
        for fa in field_vaddrs:
            delta = fa - r_add
            if 0 <= delta < max_span and delta % STRUCT_FIELD_STRIDE == 0:
                candidate = _StructCandidate(
                    fields_base_va=r_add,
                    target_field_va=fa,
                    struct_type_va=r_off - STRUCT_FIELDS_PTR_OFF,
                )
                offset = _struct_field_offset_if_match(elf, rel_map, candidate, query)
                if offset is not None:
                    offsets.add(offset)

    if len(offsets) != 1:
        msg = (
            f"expected 1 struct field offset for {first_field_name}.{target_field_name}, "
            f"found {sorted(offsets)}"
        )
        raise DiscoveryError(msg)
    return next(iter(offsets))
