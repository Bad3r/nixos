/*
  Package: sudo
  Description: Traditional Unix tool for delegating privileged commands.
  Homepage: https://www.sudo.ws/
  Documentation: https://www.sudo.ws/docs/

  Summary:
    * Provides the classic `sudo` binary for privilege escalation.
    * Included to cover hosts that still depend on sudo even when sudo-rs is enabled.
*/

{
  flake.nixosModules.apps.sudo =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.sudo ];
    };
}
