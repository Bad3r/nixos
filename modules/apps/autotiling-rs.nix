/*
  Package: autotiling-rs
  Description: Sway and i3 helper that alternates horizontal and vertical splits automatically.
  Homepage: https://github.com/ammgws/autotiling-rs
  Documentation: https://github.com/ammgws/autotiling-rs#readme
  Repository: https://github.com/ammgws/autotiling-rs

  Summary:
    * Listens to sway and i3 window focus events and toggles the next split orientation to keep layouts balanced.
    * Accepts workspace filters so you can confine autotiling to tiling workspaces while leaving others manual.

  Options:
    -w, --workspace <N> [<N>...]: Restrict autotiling to the given workspace numbers.
    -h, --help: Print usage information and exit.
    -V, --version: Show the installed autotiling-rs version.

  Example Usage:
    * `autotiling-rs` — Start the daemon to alternate horizontal and vertical splits globally.
    * `autotiling-rs --workspace 1 3 5` — Only adjust layouts on workspaces 1, 3, and 5.
    * `exec_always autotiling-rs` — Add to your sway config so autotiling launches on login.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.autotiling-rs.extended;
  AutotilingRsModule = {
    options.programs.autotiling-rs.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc "Whether to enable autotiling-rs.";
      };

      package = lib.mkPackageOption pkgs "autotiling-rs" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.autotiling-rs = AutotilingRsModule;
}
