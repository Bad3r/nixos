/*
  Package: duplicati-r2-tools
  Description: Operator-facing query and extract tools for Duplicati R2 archives.
  Repository: https://github.com/Bad3r/nixos

  Cut A ships `duplicati-r2-tools.list`, a read-only path/snapshot/history CLI
  that queries the per-target Duplicati SQLite at
  /var/lib/duplicati-r2/<slug>/duplicati-r2-<slug>.sqlite with mode=ro.
  Cut B ships `duplicati-r2-tools.extract`, a single-file extract CLI that
  fetches the dblocks containing a path's content blocks from R2 (or a
  file:// mirror), decrypts them through pyAesCrypt, and writes plaintext
  to a destination, stdout, or a glob-mode output directory.
  See docs/drafts/duplicati-r2-readonly-mount-investigation.md for the design.

  This module declares the standard programs.duplicati-r2-tools.extended.{enable,packages}
  options. The companion overlay in modules/custom-overlays/duplicati-r2-tools.nix
  exposes pkgs.duplicati-r2-tools.{list,extract}. The service module
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
