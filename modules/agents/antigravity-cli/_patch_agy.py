# Copyright (c) 2026 Bad3r

"""Write a byte-patched copy of the agy CLI binary.

Usage: python3 -I _patch_agy.py IN OUT [--patches SET[,SET...]]

Patch sets (default: all seven):

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
  staticprompts switches the four pure-static PromptSection.Content methods (browser_safety,
                chrome_default_profile, work_efficiently, non_interactive_mode) from StaticString
                to TemplateSource{} so templateprovider loads system_prompts/<name>.tmpl from
                TEMPLATE_DATA_DIR when dev mode is active, and hooks
                templateprovider.(*TemplateProvider).loadEmbeddedTemplate to fall back to each
                built-in static string when no disk template is present.
  testjmp       skips CheckScriptGuard at 0x9e5bc0a (xor eax, eax ; nop ; nop ; nop).

Both opts stores and the loadEmbeddedTemplate fallback need more room than the hooked
instructions, so the hooks jump to code in int3 padding past the last Go function (findfunc reports
no Go function there, so async preemption skips it). Each hook re-executes the instructions it
replaces and jumps back. A nil opts still faults on the first access, now outside Go's symbol table,
so the runtime reports a fatal signal instead of a nil-pointer panic.

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

ALL = (
    "devmode",
    "notelemetry",
    "noautoupdate",
    "quietwatcher",
    "agygating",
    "staticprompts",
    "testjmp",
)

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
        # Pure-static mixins.(*Section).Content methods (staticprompts):
        # each is lea rax,[StaticString itab] ; lea rbx,[&StaticString] ; ret
        "static_string_itab": 0xD6F3DB8,
        "template_source_itab": 0xD6F5538,
        "template_source_zero": 0x110E64A0,
        "static_prompts": (
            ("browser_safety", 0x9A9E7E0, 0xBCED000),
            ("chrome_default_profile", 0x9A9E860, 0xBCED010),
            ("work_efficiently", 0x9AA1600, 0xBCED020),
            ("non_interactive_mode", 0x9AA74E0, 0xBCED070),
        ),
        # templateprovider.(*TemplateProvider).loadEmbeddedTemplate: save ReadFile results to stack
        "embed_read_hook": 0x8C3A985,
        "embed_read_orig": "48897c2438488944245848895c2440",
        # testjmp: skip CheckScriptGuard (call 0x86712c0 -> xor eax, eax ; nop3)
        "test_jmp_addr": 0x9E5BC0A,
        "test_jmp_orig": "e8b15681fe",
    },
}
OPTS_DEVMODE = 0x1
OPTS_DISABLE_TELEMETRY = 0x122
NOP2 = bytes.fromhex("6690")
NOP3 = bytes.fromhex("0f1f00")
NOP5 = bytes.fromhex("0f1f440000")
NOP8 = bytes.fromhex("0f1f840000000000")
INT3 = 0xCC
ARG_COUNT = 2
MAX_DISP8 = 0x7F
QWORD = 8
DWORD = 4
WORD = 2

Edit = tuple[int, bytes, bytes]


def fail(message: str) -> NoReturn:
    sys.exit(message)


def jmp(src: int, dst: int) -> bytes:
    return b"\xe9" + struct.pack("<i", dst - (src + 5))


def lea_rip(prefix: bytes, ins: int, target: int) -> bytes:
    return prefix + struct.pack("<i", target - (ins + len(prefix) + 4))


def align16(pc: int) -> int:
    return (pc + 0xF) & ~0xF


def _cmp_r11_str(body: bytearray, text: bytes, fixups: list[int]) -> None:
    """Emit literal byte comparisons against [r11], recording JNE rel32 fixups."""
    if not text or len(text) > MAX_DISP8:
        fail(f"unsupported static prompt name length {len(text)} for {text!r}")
    off = 0
    while len(text) - off >= QWORD:
        body += b"\x49\xba" + text[off : off + QWORD]  # movabs r10, imm64
        body += b"\x4d\x39\x13" if off == 0 else b"\x4d\x39\x53" + bytes([off])
        body += b"\x0f\x85\x00\x00\x00\x00"  # jne target
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


def static_prompts_patch(build: dict, pc: int) -> tuple[list[Edit], int]:
    """Route pure-static prompt sections through TEMPLATE_DATA_DIR with built-in fallbacks."""
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
        edits.append((content_addr, content_orig, content_new))

    hook = build["embed_read_hook"]
    orig = bytes.fromhex(build["embed_read_orig"])
    body = bytearray()
    done_fixups: list[int] = []
    load_fixups: list[int] = []

    # Only fall back when ReadFile (embed.FS or the provider's fs.FS) returned an error under subdir
    # "system_prompts".
    body += b"\x48\x85\xff"  # test rdi, rdi
    body += b"\x0f\x84\x00\x00\x00\x00"  # je .done
    done_fixups.append(len(body) - 4)
    subdir = b"system_prompts"
    body += b"\x48\x83\x7c\x24\x30" + bytes([len(subdir)])  # cmp QWORD PTR [rsp+0x30], len(subdir)
    body += b"\x0f\x85\x00\x00\x00\x00"  # jne .done
    done_fixups.append(len(body) - 4)
    body += b"\x4c\x8b\x5c\x24\x48"  # mov r11, QWORD PTR [rsp+0x48] (subdir.ptr)
    _cmp_r11_str(body, subdir, done_fixups)

    body += b"\x4c\x8b\x9c\x24\x48\x01\x00\x00"  # mov r11, QWORD PTR [rsp+0x148] (name.ptr)
    for name, _content_addr, static_addr in entries:
        name_b = name.encode("ascii")
        next_fixups: list[int] = []
        body += b"\x48\x83\xbc\x24\x50\x01\x00\x00" + bytes([len(name_b)])  # cmp [rsp+0x150], len
        body += b"\x0f\x85\x00\x00\x00\x00"  # jne .next
        next_fixups.append(len(body) - 4)
        _cmp_r11_str(body, name_b, next_fixups)
        body += lea_rip(b"\x4c\x8d\x1d", pc + len(body), static_addr)
        body += b"\xe9\x00\x00\x00\x00"  # jmp .load_static
        load_fixups.append(len(body) - 4)
        _patch_rel32(body, next_fixups, len(body))

    body += b"\xe9\x00\x00\x00\x00"  # jmp .done (no name matched)
    done_fixups.append(len(body) - 4)

    _patch_rel32(body, load_fixups, len(body))
    body += b"\x49\x8b\x03"  # mov rax, QWORD PTR [r11]
    body += b"\x49\x8b\x5b\x08"  # mov rbx, QWORD PTR [r11+0x8]
    body += b"\x31\xff"  # xor edi, edi
    body += b"\x31\xf6"  # xor esi, esi

    _patch_rel32(body, done_fixups, len(body))
    body += orig
    body += jmp(pc + len(body), hook + len(orig))

    edits += [
        (pc, bytes([INT3]) * len(body), bytes(body)),
        (hook, orig, jmp(hook, pc) + NOP8 + NOP2),
    ]
    return edits, align16(pc + len(body))


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


def _static_edits(build: dict, patches: list[str]) -> list[Edit]:
    """Build in-place edits that do not allocate code-cave stubs."""
    edits: list[Edit] = []
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
    if "testjmp" in patches:
        addr = build.get("test_jmp_addr")
        orig = build.get("test_jmp_orig")
        if addr is None or not orig:
            fail(f"patch set 'testjmp' is not supported on agy {build['version']}")
        edits.append((addr, bytes.fromhex(orig), b"\x31\xc0" + NOP3))
    return edits


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
    edits += _static_edits(build, patches)
    if "staticprompts" in patches:
        if not build.get("static_prompts"):
            fail(f"patch set 'staticprompts' is not supported on agy {build['version']}")
        more, pc = static_prompts_patch(build, pc)
        edits += more
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
