/*
  Package: direnv
  Description: Shell extension that loads/unloads environment variables based on the current directory.
  Homepage: https://direnv.net
  Documentation: https://direnv.net/#usage
  Repository: https://github.com/direnv/direnv

  Summary:
    * Hooks into your shell to watch `.envrc` files and adjust environment variables automatically.

  Options:
    direnv allow: Authorize the current `.envrc` file.
    direnv deny: Revert authorization for a directory.
    direnv exec <dir> <command>: Execute a command within another directory’s environment.
*/
_:
let
  DirenvModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.direnv.extended;
    in
    {
      options.programs.direnv.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable direnv.";
        };

        package = lib.mkPackageOption pkgs "direnv" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.direnv = DirenvModule;
}
