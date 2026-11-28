# Copyright (c) 2026 Bad3r

"""Read-only ELF64 little-endian x86-64 image parser and virtual address mapper."""

from __future__ import annotations

import re
import struct
from dataclasses import dataclass

ELF_MAGIC = b"\x7fELF"
ELF_HEADER_MIN_SIZE = 64
ELF_IDENT_CLASS_OFF = 4
ELF_IDENT_DATA_OFF = 5
ELF_MACHINE_OFF = 0x12
ELF_PHOFF_OFF = 0x20
ELF_PHENTSIZE_OFF = 0x36
ELF_PHNUM_OFF = 0x38
ELF_SHOFF_OFF = 0x28
ELF_SHENTSIZE_OFF = 0x3A
ELF_SHNUM_OFF = 0x3C
ELF_SHSTRNDX_OFF = 0x3E

ELFCLASS64 = 2
ELFDATA2LSB = 1
EM_X86_64 = 62
PT_LOAD = 1
PF_X = 1
PF_W = 2
R_X86_64_RELATIVE = 8
RELOC_INFO_TYPE_MASK = 0xFFFFFFFF
INT3_BYTE = 0xCC
PAGE_ALIGN = 16

PHDR_STRUCT = struct.Struct("<IIQQQQQQ")
SHDR_STRUCT = struct.Struct("<IIQQQQIIQQ")
RELOC_STRUCT = struct.Struct("<QQq")


class PatchError(RuntimeError):
    """Base error raised when validating, discovering, or applying binary patches."""


class DiscoveryError(PatchError):
    """Error raised when ELF, Go metadata, or instruction discovery fails."""


@dataclass(frozen=True)
class Segment:
    """An ELF64 PT_LOAD segment."""

    vaddr: int
    offset: int
    filesz: int
    memsz: int
    flags: int

    def contains_file_vaddr(self, vaddr: int, size: int) -> bool:
        """Return whether [vaddr, vaddr + size) lies inside the file-backed range."""
        return size >= 0 and self.vaddr <= vaddr and vaddr + size <= self.vaddr + self.filesz

    def contains_mem_vaddr(self, vaddr: int, size: int) -> bool:
        """Return whether [vaddr, vaddr + size) lies inside the memory-mapped range."""
        return size >= 0 and self.vaddr <= vaddr and vaddr + size <= self.vaddr + self.memsz

    def contains_file_offset(self, offset: int, size: int) -> bool:
        """Return whether [offset, offset + size) lies inside this segment on disk."""
        return size >= 0 and self.offset <= offset and offset + size <= self.offset + self.filesz


@dataclass(frozen=True)
class Section:
    """An ELF64 section header summary."""

    name: str
    addr: int
    offset: int
    size: int
    flags: int


def _parse_loads(data: bytes) -> tuple[Segment, ...]:
    phoff = struct.unpack_from("<Q", data, ELF_PHOFF_OFF)[0]
    phentsize = struct.unpack_from("<H", data, ELF_PHENTSIZE_OFF)[0]
    phnum = struct.unpack_from("<H", data, ELF_PHNUM_OFF)[0]
    if phentsize < PHDR_STRUCT.size or phoff + phentsize * phnum > len(data):
        msg = "invalid ELF program header table"
        raise DiscoveryError(msg)

    loads: list[Segment] = []
    for idx in range(phnum):
        p_type, p_flags, p_off, p_vaddr, _, p_filesz, p_memsz, _ = PHDR_STRUCT.unpack_from(
            data, phoff + idx * phentsize
        )
        if p_type != PT_LOAD:
            continue
        if p_off + p_filesz > len(data):
            msg = f"PT_LOAD segment {idx} extends past EOF"
            raise DiscoveryError(msg)
        loads.append(Segment(p_vaddr, p_off, p_filesz, p_memsz, p_flags))
    if not loads:
        msg = "ELF image contains no PT_LOAD segments"
        raise DiscoveryError(msg)
    return tuple(loads)


def _parse_sections(data: bytes) -> dict[str, Section]:
    shoff = struct.unpack_from("<Q", data, ELF_SHOFF_OFF)[0]
    shentsize = struct.unpack_from("<H", data, ELF_SHENTSIZE_OFF)[0]
    shnum = struct.unpack_from("<H", data, ELF_SHNUM_OFF)[0]
    shstrndx = struct.unpack_from("<H", data, ELF_SHSTRNDX_OFF)[0]
    if shnum == 0:
        return {}
    if shentsize < SHDR_STRUCT.size or shoff + shentsize * shnum > len(data) or shstrndx >= shnum:
        msg = "invalid ELF section header table"
        raise DiscoveryError(msg)

    _, _, _, _, shstr_off, shstr_size, *_ = SHDR_STRUCT.unpack_from(
        data, shoff + shstrndx * shentsize
    )
    if shstr_off + shstr_size > len(data):
        msg = "invalid ELF section string table"
        raise DiscoveryError(msg)
    shstr = data[shstr_off : shstr_off + shstr_size]

    sections: dict[str, Section] = {}
    for idx in range(shnum):
        sh_name, _, sh_flags, sh_addr, sh_off, sh_size, *_ = SHDR_STRUCT.unpack_from(
            data, shoff + idx * shentsize
        )
        if sh_name >= len(shstr):
            msg = f"section {idx} name offset out of range"
            raise DiscoveryError(msg)
        end = shstr.find(b"\x00", sh_name)
        name_bytes = shstr[sh_name:] if end == -1 else shstr[sh_name:end]
        name = name_bytes.decode("utf-8", "replace")
        sections[name] = Section(name, sh_addr, sh_off, sh_size, sh_flags)
    return sections


class Elf64Image:
    """Validated ELF64 x86-64 image providing safe virtual/file translations."""

    def __init__(self, data: bytes | bytearray) -> None:
        """Validate ELF64 little-endian x86-64 headers and parse load tables."""
        raw = bytes(data)
        if len(raw) < ELF_HEADER_MIN_SIZE or raw[:4] != ELF_MAGIC:
            msg = "input is not an ELF binary"
            raise DiscoveryError(msg)
        if raw[ELF_IDENT_CLASS_OFF] != ELFCLASS64 or raw[ELF_IDENT_DATA_OFF] != ELFDATA2LSB:
            msg = "input is not a 64-bit little-endian ELF binary"
            raise DiscoveryError(msg)
        machine = struct.unpack_from("<H", raw, ELF_MACHINE_OFF)[0]
        if machine != EM_X86_64:
            msg = f"unsupported ELF machine {machine:#x}; expected x86-64"
            raise DiscoveryError(msg)

        self.data = raw
        self.loads = _parse_loads(raw)
        self.sections = _parse_sections(raw)
        self._rel_cache: dict[int, int] | None = None

    def vaddr_to_offset(self, vaddr: int, size: int = 1) -> int:
        """Map a file-backed virtual address range to its file offset."""
        for seg in self.loads:
            if seg.contains_file_vaddr(vaddr, size):
                return seg.offset + (vaddr - seg.vaddr)
        msg = f"virtual address {vaddr:#x} (+{size}) is not file-backed"
        raise DiscoveryError(msg)

    def try_offset_to_vaddr(self, offset: int, size: int = 1) -> int | None:
        """Return the virtual address for a file offset range, or None if unmapped."""
        for seg in self.loads:
            if seg.contains_file_offset(offset, size):
                return seg.vaddr + (offset - seg.offset)
        return None

    def offset_to_vaddr(self, offset: int, size: int = 1) -> int:
        """Map a file offset range inside a PT_LOAD segment to its virtual address."""
        vaddr = self.try_offset_to_vaddr(offset, size)
        if vaddr is None:
            msg = f"file offset {offset:#x} (+{size}) is outside PT_LOAD segments"
            raise DiscoveryError(msg)
        return vaddr

    def is_writable_vaddr(self, vaddr: int, size: int = 1) -> bool:
        """Return whether [vaddr, vaddr + size) lies inside a writable PT_LOAD segment."""
        return any(
            (seg.flags & PF_W) != 0 and seg.contains_mem_vaddr(vaddr, size) for seg in self.loads
        )

    def is_executable_vaddr(self, vaddr: int, size: int = 1) -> bool:
        """Return whether [vaddr, vaddr + size) lies inside an executable PT_LOAD segment."""
        return any(
            (seg.flags & PF_X) != 0 and seg.contains_file_vaddr(vaddr, size) for seg in self.loads
        )

    def read_vaddr(self, vaddr: int, size: int) -> bytes:
        """Read `size` bytes starting at virtual address `vaddr`."""
        off = self.vaddr_to_offset(vaddr, size)
        return self.data[off : off + size]

    def section(self, name: str) -> Section:
        """Return the named ELF section or raise DiscoveryError."""
        sec = self.sections.get(name)
        if sec is None:
            msg = f"missing required ELF section {name!r}"
            raise DiscoveryError(msg)
        return sec

    def find_unique_bytes(self, needle: bytes) -> int:
        """Return the unique virtual address matching `needle`."""
        matches: list[int] = []
        pos = 0
        while True:
            idx = self.data.find(needle, pos)
            if idx == -1:
                break
            pos = idx + 1
            vaddr = self.try_offset_to_vaddr(idx, len(needle))
            if vaddr is not None:
                matches.append(vaddr)
        if len(matches) != 1:
            msg = f"expected 1 mapped match for {needle!r}, found {len(matches)}"
            raise DiscoveryError(msg)
        return matches[0]

    def relative_relocations(self) -> dict[int, int]:
        """Return a cached mapping of R_X86_64_RELATIVE relocation target to addend."""
        if self._rel_cache is not None:
            return self._rel_cache
        reloc_sec = self.section(".rela.dyn")
        if reloc_sec.offset + reloc_sec.size > len(self.data):
            msg = ".rela.dyn extends past EOF"
            raise DiscoveryError(msg)
        rel_map: dict[int, int] = {}
        end = reloc_sec.offset + reloc_sec.size
        for off in range(reloc_sec.offset, end - RELOC_STRUCT.size + 1, RELOC_STRUCT.size):
            r_offset, r_info, r_addend = RELOC_STRUCT.unpack_from(self.data, off)
            if (r_info & RELOC_INFO_TYPE_MASK) == R_X86_64_RELATIVE:
                rel_map[r_offset] = r_addend
        self._rel_cache = rel_map
        return rel_map

    def find_exec_int3_cave(self, min_vaddr: int, min_size: int) -> tuple[int, int]:
        """Find the largest executable int3 padding run at or after `min_vaddr`."""
        pattern = re.compile(rb"\xcc{" + str(min_size).encode("ascii") + rb",}")
        best_usable = -1
        best_range: tuple[int, int] | None = None

        for seg in self.loads:
            if (seg.flags & PF_X) == 0:
                continue
            seg_end = seg.vaddr + seg.filesz
            scan_start_va = max(seg.vaddr, min_vaddr)
            if scan_start_va >= seg_end:
                continue
            off_start = seg.offset + (scan_start_va - seg.vaddr)
            off_end = seg.offset + seg.filesz
            for match in pattern.finditer(self.data[off_start:off_end]):
                lo = scan_start_va + match.start()
                hi = scan_start_va + match.end()
                aligned_lo = (lo + PAGE_ALIGN - 1) & ~(PAGE_ALIGN - 1)
                usable = hi - aligned_lo
                if usable >= min_size and usable > best_usable:
                    best_usable = usable
                    best_range = (lo, hi)

        if best_range is None:
            msg = f"no executable int3 cave >= {min_size} bytes found after {min_vaddr:#x}"
            raise DiscoveryError(msg)
        return best_range
