/*
  Package: duplicati-r2-tools
  Description: Operator-facing query and (planned) extract tools for Duplicati R2 archives.
  Repository: https://github.com/Bad3r/nixos

  Stage 1 ships `duplicati-r2-tools.list`, a read-only path/snapshot/history CLI
  that queries the per-target Duplicati SQLite at
  /var/lib/duplicati-r2/<slug>/duplicati-r2-<slug>.sqlite with mode=ro.
  See docs/drafts/duplicati-r2-readonly-mount-investigation.md for the design.

  This module declares the standard programs.duplicati-r2-tools.extended.{enable,package}
  options. The companion overlay in modules/custom-overlays/duplicati-r2-tools.nix
  exposes pkgs.duplicati-r2-tools.list. The service module
  modules/services/duplicati-r2.nix auto-enables this when
  services.duplicati-r2.stateDirReadableBy is non-empty.
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
          description = "Whether to install duplicati-r2-tools (Cut A: duplicati-r2-list).";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs.duplicati-r2-tools.list;
          defaultText = lib.literalExpression "pkgs.duplicati-r2-tools.list";
          description = "duplicati-r2-list package providing /bin/duplicati-r2-list.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."duplicati-r2-tools" = DuplicatiR2ToolsModule;
}
