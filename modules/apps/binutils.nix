/*
  Package: binutils
  Description: GNU binary tools (linker, assembler, and object-file inspectors), wrapped for the Nix toolchain.
  Homepage: https://www.gnu.org/software/binutils/
  Documentation: https://sourceware.org/binutils/docs/
  Repository: https://sourceware.org/git/binutils-gdb.git

  Summary:
    * Provides `ld`, `as`, `ar`, `nm`, `objdump`, `readelf`, `strings`, `strip`, and the rest of GNU binutils.

  Options:
    readelf -d <file>: Show the dynamic section (NEEDED libraries, RPATH, RUNPATH).
    objdump -d <file>: Disassemble the executable sections.
    nm -D <file>: List dynamic symbols.
*/
_:
let
  BinutilsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.binutils.extended;
    in
    {
      options.programs.binutils.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable binutils.";
        };

        package = lib.mkPackageOption pkgs "binutils" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.binutils = BinutilsModule;
}
