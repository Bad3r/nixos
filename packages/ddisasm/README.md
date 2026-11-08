# DDisasm

Build the pinned source snapshot:

```sh
nix build path:.#ddisasm
nix build path:.#ddisasm.tests.roundtrip
```

The package follows GrammaTech/ddisasm's `main` branch through an immutable
commit and source hash in `hashes.json`. GitHub's latest release is 1.8.0
from December 2023. Upstream also documents Docker and Conan distributions;
its GitHub workflow builds on branch pushes.

Run the updater from any directory:

```sh
/home/vx/nixos/packages/ddisasm/update.py
/home/vx/nixos/packages/ddisasm/update.py --force --dry-run
```

The updater resolves DDisasm `main` and gtirb-pprinter `master`, reads each
version at the resolved commit, and hashes that commit's source archive.
It writes both pins together after every download succeeds. `--dry-run`
prints changes without writing; `--check-release` checks branch metadata
without downloading archives. The repository's package updater runner
discovers this script automatically.

GTIRB 2.3.2, libehp, and LIEF 0.16.6 remain fixed compatibility dependencies.
The libehp revision and LIEF iterator patch match upstream's Dockerfile.
The pretty printer is a snapshot because its published 2.1.0 tag is older
than DDisasm's required 2.2.6. These libraries remain private to the package.

The roundtrip check compiles a small ELF executable, disassembles it to
GTIRB and assembly, recompiles the assembly, and compares its output with
the original. It also checks that disassembly leaves the input unchanged.
This check covers the native ELF path, not every supported ISA or PE files.

Sources:

- <https://github.com/GrammaTech/ddisasm>
- <https://github.com/GrammaTech/ddisasm/releases>
- <https://github.com/GrammaTech/ddisasm/blob/main/Dockerfile>
