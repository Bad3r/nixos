/*
  Package: libstdcxx
  Description: GNU C++ standard library runtime from GCC for dynamically linked binaries.
  Homepage: https://gcc.gnu.org/onlinedocs/libstdc++/
  Documentation: https://gcc.gnu.org/onlinedocs/libstdc++/manual/using.html
  Repository: https://gcc.gnu.org/git/gcc.git

  Summary:
    * Provides the shared `libstdc++.so.6` runtime used by applications built against GCC's C++ standard library.
    * Includes low-level GCC runtime libraries such as `libgcc_s.so.1` that prebuilt native extensions and foreign binaries often require.
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
