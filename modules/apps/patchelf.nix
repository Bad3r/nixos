/*
  Package: patchelf
  Description: Small utility to modify the dynamic linker and RPATH of ELF executables.
  Homepage: nil
  Documentation: nil
  Repository: https://github.com/NixOS/patchelf

  Summary:
    * Rewrites the ELF `PT_INTERP` path and `DT_RPATH`/`DT_RUNPATH` entries of prebuilt binaries so they resolve against a chosen loader and library set.
    * Edits `DT_NEEDED` and `DT_SONAME` records to add, drop, or substitute shared-library dependencies without rebuilding from source.

  Options:
    --print-interpreter: Report the dynamic loader recorded in `PT_INTERP`.
    --set-interpreter: Point `PT_INTERP` at a different loader path.
    --print-rpath: Report the current `DT_RPATH`/`DT_RUNPATH` search path.
    --set-rpath: Replace the search path; `--add-rpath` appends and `--remove-rpath` clears it.
    --shrink-rpath: Drop search-path entries that supply no needed library; `--allowed-rpath-prefixes` restricts which entries survive.
    --force-rpath: Emit `DT_RPATH` instead of the default `DT_RUNPATH`.
    --print-needed: List `DT_NEEDED` dependencies.
    --add-needed: Record an extra shared-library dependency.
    --remove-needed: Drop a `DT_NEEDED` entry.
    --replace-needed: Swap one `DT_NEEDED` entry for another.
    --print-soname: Report `DT_SONAME`; `--set-soname` writes it.
    --clear-symbol-version: Strip the version requirement from a symbol.
    --no-default-lib: Set `DF_1_NODEFLIB` so the default library directories are skipped.
    --page-size: Override the assumed page size when relocating headers.
    --output: Write the patched result to a new file instead of in place.

  Notes:
    * nixpkgs pins `patchelf` to the 0.15.x series used by the stdenv fixup hook; `patchelfUnstable` carries the newer upstream snapshot at low priority.
*/
_:
let
  PatchelfModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.patchelf.extended;
    in
    {
      options.programs.patchelf.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable patchelf.";
        };

        package = lib.mkPackageOption pkgs "patchelf" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.patchelf = PatchelfModule;
}
