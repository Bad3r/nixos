# LIEF Ghidra extension

The extension builds its Java plugin and native JNI bridge from the same
source as the pinned nixpkgs LIEF library. It builds against the pinned
Ghidra package. No prebuilt extension ZIP is used.

A small local JNI adapter forwards the plugin's logging calls to Ghidra's
`Msg` class. It replaces the logging-only `ghidra-jni` build dependency,
whose headers are not included in LIEF's public source distribution.

Build the extension and run its headless check:

```sh
nix build path:.#lief-ghidra
nix build path:.#lief-ghidra.tests.headless
```

Songbird selects the extension through `programs.ghidra.extended.extensions`.
The Ghidra app module composes all selected extensions into one package with
`ghidra.withExtensions`. Additional nixpkgs extensions can be added to the same
list, such as `pkgs.ghidra-extensions.findcrypt`; another launcher is not needed.
An extension missing from nixpkgs needs its own build recipe, as LIEF does here.
The extension carries its native bridge and
LIEF library; no files need to be copied into the user's Ghidra settings.
Existing Ghidra projects and settings remain outside the package.

The package uses the standard LIEF library. Features that require LIEF
Extended, including DWARF editing, remain unavailable.

## Updates

LIEF's Java sources, native bridge sources, and shared library follow the
same nixpkgs package when `flake.lock` changes. Ghidra follows that pin too,
so the extension is rebuilt against the selected Ghidra version.

The package updater refreshes the separate `google/jni-bind` headers to
the latest stable release. The release is resolved to a full commit and
an unpacked source hash in `hashes.json`.

```sh
/home/vx/nixos/packages/lief-ghidra/update.py
/home/vx/nixos/packages/lief-ghidra/update.py --check-release
/home/vx/nixos/packages/lief-ghidra/update.py --force --dry-run
```

The repository's package updater runner discovers this executable script
automatically. `--check-release` checks upstream release metadata without
hashing or writing. `--dry-run` prints changes without writing. An update
replaces the pin file only after metadata and hashing succeed, and refuses
to overwrite edits made while it was fetching. Rebuild the extension and
run the headless check after updating; a successful metadata update does
not establish API or runtime compatibility.

Sources:

- <https://lief.re/doc/latest/plugins/ghidra/index.html>
- <https://github.com/lief-project/LIEF/tree/main/plugins/ghidra>
- <https://github.com/google/jni-bind>
