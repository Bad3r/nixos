/*
  Package: libstdcxx
  Description: GNU C++ standard library runtime from GCC for dynamically linked binaries.
  Homepage: https://gcc.gnu.org/onlinedocs/libstdc++/
  Documentation: https://gcc.gnu.org/onlinedocs/libstdc++/manual/using.html
  Repository: https://gcc.gnu.org/git/gcc.git

  Summary:
    * Provides the shared `libstdc++.so.6` runtime used by applications built against GCC's C++ standard library.
    * Includes low-level GCC runtime libraries such as `libgcc_s.so.1` that are commonly required by prebuilt native extensions and foreign binaries.

  Options:
    lib/libstdc++.so.6: Runtime shared library for C++ applications linked against GNU libstdc++.
    lib/libgcc_s.so.1: GCC support library used for exception handling and stack unwinding.
    NIX_LD_LIBRARY_PATH: Add this package to runtime library paths for foreign binaries that require `libstdc++.so.6`.
*/
_:
let
  LibstdcxxModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.libstdcxx.extended;
    in
    {
      options.programs.libstdcxx.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable libstdcxx.";
        };

        package = lib.mkPackageOption pkgs [
          "stdenv"
          "cc"
          "cc"
          "lib"
        ] { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.libstdcxx = LibstdcxxModule;
}
