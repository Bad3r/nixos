# Pentesting Toolkit: Reverse Engineering & Dynamic Analysis

[Back to Pentesting Toolkit](../toolkit.md)

## Reverse Engineering & Dynamic Analysis

- cutter
  - run..: `cutter $binary`
  - Repo.: <https://github.com/rizinorg/cutter>
  - Docs.: <https://cutter.re/>
  - Desc.: Rizin-powered reverse engineering GUI with decompiler, graph view, and integrated debugger.
- frida-tools
  - run..: `frida -U $process`
  - Repo.: <https://github.com/frida/frida-tools>
  - Docs.: <https://frida.re/docs/>
  - Desc.: Dynamic instrumentation of native and managed runtimes.
- gdb
  - run..: `gdb $binary`
  - Repo.: <https://sourceware.org/git/binutils-gdb.git>
  - Docs.: <https://sourceware.org/gdb/documentation/>
  - Desc.: GNU debugger for native binary inspection and exploit development.
- ghidra
  - run..: `ghidra`
  - Repo.: <https://github.com/NationalSecurityAgency/ghidra>
  - Docs.: <https://ghidra-sre.org/>
  - Desc.: NSA reverse engineering platform with decompiler.
- ltrace
  - run..: `ltrace $binary`
  - Repo.: <https://gitlab.com/cespedes/ltrace>
  - Docs.: <https://www.ltrace.org/>
  - Desc.: Library call tracer.
- patchelf
  - run..: `patchelf --print-interpreter --print-rpath --print-needed $binary`
  - Repo.: <https://github.com/NixOS/patchelf>
  - Docs.: <https://github.com/NixOS/patchelf#readme>
  - Desc.: Rewrites the ELF interpreter, RPATH/RUNPATH, and DT_NEEDED records of prebuilt binaries so foreign or stripped samples load under a chosen loader and library set; nixpkgs pins this attribute to the 0.15.x stdenv series while `patchelfUnstable` carries the newer snapshot.
- strace
  - run..: `strace $binary`
  - Repo.: <https://github.com/strace/strace>
  - Docs.: <https://strace.io/>
  - Desc.: System call tracer.
- valgrind
  - run..: `valgrind $binary`
  - Repo.: <https://sourceware.org/git/valgrind.git>
  - Docs.: <https://valgrind.org/docs/>
  - Desc.: Memory error and vulnerability inspection toolkit.
