# DDisasm

Build GrammaTech's prebuilt stable package for x86_64 Linux:

```sh
nix build path:.#ddisasm
nix build path:.#ddisasm.tests.roundtrip
```

GitHub Releases stops at 1.8.0 from December 2023, but GrammaTech's stable
APT repository publishes newer versions, including 1.9.5. This package
installs that repository's `.deb` and the matching GTIRB, pretty-printer,
and Capstone binary libraries. It patches ELF loader paths for NixOS;
it does not run Debian installation scripts or compile upstream sources.

The vendor binaries require Boost 1.71 and Protobuf's `libprotobuf.so.17`.
Those ABI versions are supplied by pinned official Ubuntu Focal packages.
Nixpkgs supplies glibc, the GCC runtime, and zlib. Bundled libraries are
private to DDisasm; they do not replace the host's packages.

Run the updater from any directory:

```sh
/home/vx/nixos/packages/ddisasm/update.py
/home/vx/nixos/packages/ddisasm/update.py --force --dry-run
```

The updater selects the newest stable DDisasm version in GrammaTech's APT
index and the exact vendor library versions declared by that package.
It verifies downloaded artifacts against the index's SHA256 values before
replacing `hashes.json`. A failed download, checksum mismatch, or concurrent
edit leaves the existing pins intact. The Ubuntu ABI libraries remain
fixed; a release requiring an unhandled dependency fails explicitly.

`--dry-run` prints changes without writing. `--check-release` checks release
metadata without downloading artifacts. `--force` verifies every artifact,
including the fixed runtime libraries. The repository's package updater
runner discovers this script automatically. Build the package and run its
roundtrip check after updating.

The roundtrip check compiles a small ELF executable, disassembles it to
GTIRB and assembly, recompiles the assembly, and compares its output with
the original. It also checks that disassembly leaves the input unchanged.
This check covers native x86_64 ELF, not every supported ISA or PE files.

Sources:

- <https://github.com/GrammaTech/ddisasm>
- <https://download.grammatech.com/gtirb/files/apt-repo/dists/focal/stable/binary-amd64/Packages>
- <https://archive.ubuntu.com/ubuntu/dists/focal/main/binary-amd64/Packages.gz>
- <https://archive.ubuntu.com/ubuntu/dists/focal-updates/main/binary-amd64/Packages.gz>
