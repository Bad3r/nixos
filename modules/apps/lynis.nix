/*
  Package: lynis
  Description: Security auditing tool for Linux, macOS, and UNIX-based systems.
  Homepage: https://cisofy.com/lynis/
  Documentation: https://cisofy.com/lynis/
  Repository: https://github.com/CISOfy/lynis

  Summary:
    * Performs host security audits covering system hardening, service exposure, and configuration hygiene.
    * Generates findings, suggestions, and audit artifacts suited for repeatable workstation or server assessments.

  Options:
    audit system: Run the main system audit against the current host.
    show commands: Print supported Lynis commands and high-level usage.
    show profiles: List available audit profiles and their intended targets.
    --quick: Skip longer or lower-priority tests to reduce audit runtime.
*/
_:
let
  LynisModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.lynis.extended;
    in
    {
      options.programs.lynis.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable lynis.";
        };

        package = lib.mkPackageOption pkgs "lynis" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.lynis = LynisModule;
}
