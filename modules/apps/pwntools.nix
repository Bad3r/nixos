/*
  Package: pwntools
  Description: CTF framework and exploit development library.
  Homepage: https://github.com/Gallopsled/pwntools
  Documentation: https://docs.pwntools.com/
  Repository: https://github.com/Gallopsled/pwntools

  Summary:
    * Provides process and remote tubes, ELF parsing, ROP chain building, shellcode assembly, and format-string helpers.
    * Installs the `pwn` command and its helpers such as `checksec`, `cyclic`, `shellcraft`, and `asm`; the Python library needs a `python3.withPackages` environment.
*/
_:
let
  PwntoolsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.pwntools.extended;
    in
    {
      options.programs.pwntools.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable pwntools.";
        };

        package = lib.mkPackageOption pkgs "pwntools" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.pwntools = PwntoolsModule;
}
