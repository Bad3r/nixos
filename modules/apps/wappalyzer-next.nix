/*
  Package: wappalyzer-next
  Description: CLI for detecting website technology stacks powered by Wappalyzer fingerprints.
  Homepage: https://github.com/s0md3v/wappalyzer-next

  Summary:
    * Provides the `wappalyzer` command-line utility backed by the latest Wappalyzer dataset.
    * Useful when auditing targets during security assessments or automating reconnaissance workflows.

  Example Usage:
    * `wappalyzer https://example.org` — Enumerate detected technologies for the given URL.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.system.extended;
  SystemModule = {
    options.programs.system.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc "Whether to enable system.";
      };

      package = lib.mkPackageOption pkgs "system" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.system = SystemModule;
}
