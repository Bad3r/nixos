/*
  Package: ssh-audit
  Description: Tool for ssh server auditing.
  Homepage: https://github.com/jtesta/ssh-audit
  Documentation: https://github.com/jtesta/ssh-audit
  Repository: https://github.com/jtesta/ssh-audit

  Summary:
    * Audits SSH servers for supported algorithms, banner details, and protocol hardening gaps.
    * Highlights weak ciphers, legacy key exchanges, and insecure configuration choices in scan output.

  Options:
    -4: Force an IPv4 connection to the audit target.
    -6: Force an IPv6 connection to the audit target.
    -j: Emit JSON output for machine-readable post-processing.
*/
_:
let
  SshAuditModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."ssh-audit".extended;
    in
    {
      options.programs.ssh-audit.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable ssh-audit.";
        };

        package = lib.mkPackageOption pkgs "ssh-audit" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.ssh-audit = SshAuditModule;
}
