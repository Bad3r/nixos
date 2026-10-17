/*
  Package: binutils
  Description: GNU binary tools (linker, assembler, and object-file inspectors), wrapped for the Nix toolchain.
  Homepage: https://www.gnu.org/software/binutils/
  Documentation: https://sourceware.org/binutils/docs/
  Repository: https://sourceware.org/git/binutils-gdb.git

  Summary:
    * Provides `ld`, `as`, `ar`, `nm`, `objdump`, `readelf`, `strings`, `strip`, and the rest of GNU binutils.
    * Installs the nixpkgs wrapper, whose `ld` adds the Nix dynamic linker and library search paths.

  Options:
    readelf -d <file>: Show the dynamic section (NEEDED libraries, RPATH, RUNPATH).
    objdump -d <file>: Disassemble the executable sections.
    nm -D <file>: List dynamic symbols.
    strings <file>: Print the printable character runs in a file.

  Example Usage:
    * `readelf -d ./a.out` -- Check which shared libraries a binary needs.
    * `objdump -d -M intel ./a.out | less` -- Disassemble with Intel syntax.
    * `strip --strip-debug ./a.out` -- Drop debug symbols from a binary.
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
