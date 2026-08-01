/*
  Package: gowitness
  Description: Headless-Chrome web screenshot utility with a reporting interface.
  Homepage: nil
  Documentation: https://github.com/sensepost/gowitness/wiki
  Repository: https://github.com/sensepost/gowitness

  Summary:
    * Drives headless Chrome to capture screenshots of URLs and host lists for visual recon triage.
    * Stores captures in a database and serves a report UI for browsing screenshots, headers, and technologies.

  Options:
    scan: Screenshot targets using the subcommands below.
    scan single:
      -u, --url <target>: Single URL to screenshot.
    scan file:
      -f, --file <file>: File of URLs to screenshot.
    scan (persistent across scan subcommands):
      --screenshot-path <dir>: Directory to write screenshots to.
      --write-db: Persist results to the SQLite database.
    report: Serve or export the web report UI over captured results.
*/
_:
let
  GowitnessModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.gowitness.extended;
    in
    {
      options.programs.gowitness.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable gowitness.";
        };

        package = lib.mkPackageOption pkgs "gowitness" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.gowitness = GowitnessModule;
}
