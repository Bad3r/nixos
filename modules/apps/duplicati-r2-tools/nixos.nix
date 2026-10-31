/*
  Package: duplicati-r2-tools
  Description: Operator-facing query and extract tools for Duplicati R2 archives.
  Repository: https://github.com/Bad3r/nixos

  Summary:
    * `duplicati-r2-list` queries paths, snapshots, and file history from a target's local Duplicati database, read-only.
    * `duplicati-r2-extract` restores single files or globs from R2 archives to a directory or stdout.
*/
_:
let
  DuplicatiR2ToolsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.duplicati-r2-tools.extended;
    in
    {
      options.programs.duplicati-r2-tools.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to install duplicati-r2-tools (Cut A: duplicati-r2-list and Cut B: duplicati-r2-extract).";
        };

        packages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [
            pkgs.duplicati-r2-tools.list
            pkgs.duplicati-r2-tools.extract
          ];
          defaultText = lib.literalExpression "[ pkgs.duplicati-r2-tools.list pkgs.duplicati-r2-tools.extract ]";
          description = "duplicati-r2-tools binaries to install on PATH.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = cfg.packages;
      };
    };
in
{
  flake.nixosModules.apps."duplicati-r2-tools" = DuplicatiR2ToolsModule;
}
