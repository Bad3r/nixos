/*
  Package: htop
  Description: Interactive process viewer and system monitor.
  Homepage: https://htop.dev/
  Documentation: https://htop.dev/
  Repository: https://github.com/htop-dev/htop

  Summary:
    * Displays real-time CPU, memory, and process metrics with color-coded bars and interaction shortcuts.
    * Allows filtering, tree views, and sending signals to processes directly from the interface.

  Options:
    --tree: Visualize processes in a hierarchical tree to inspect parent/child relationships.
    -u <user>: Filter the process list to a specific UID when launching htop.
    --sort-key <field>: Choose the metric used for ordering processes (e.g., `htop --sort-key PERCENT_CPU`).
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  HtopModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.htop.extended;
    in
    {
      options.programs.htop.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable htop.";
        };

        package = lib.mkPackageOption pkgs "htop" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.htop = HtopModule;
}
