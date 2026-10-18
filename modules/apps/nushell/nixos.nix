/*
  Package: nushell
  Description: Modern shell written in Rust.
  Homepage: https://www.nushell.sh/
  Documentation: https://www.nushell.sh/book/
  Repository: https://github.com/nushell/nushell

  Summary:
    * A new type of shell.
    * Pipelines use structured data rather than raw text.

  Options:
    -c: Run a command.
*/
_:
let
  NushellModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.nushell.extended;
    in
    {
      options.programs.nushell.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable nushell.";
        };

        package = lib.mkPackageOption pkgs "nushell" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.nushell = NushellModule;
}
