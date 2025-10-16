/*
  Package: duplicati
  Description: Backup client for encrypted, deduplicated cloud storage workflows.
  Homepage: https://www.duplicati.com/
  Documentation: https://docs.duplicati.com/
  Repository: https://github.com/duplicati/duplicati

  Summary:
    * Provides the Duplicati CLI and web UI for managing encrypted backups.
    * Supports scheduling, retention policies, and cloud storage targets.

  Example Usage:
    * `sudo systemctl enable --now duplicati` — start the Duplicati web server.
    * `duplicati-cli list-backups` — inspect configured backup jobs on the CLI.
*/

{
  flake.nixosModules.apps."duplicati" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.duplicati ];
    };
}
