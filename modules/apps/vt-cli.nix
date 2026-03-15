/*
  Package: vt-cli
  Description: VirusTotal Command Line Interface.
  Homepage: https://github.com/VirusTotal/vt-cli
  Documentation: https://github.com/VirusTotal/vt-cli
  Repository: https://github.com/VirusTotal/vt-cli

  Summary:
    * Interacts with the VirusTotal API from the terminal for lookups, scans, and hunting workflows.
    * Supports structured output and shell completion for scripting or analyst-driven investigation.

  Options:
    init: Initialize or re-initialize local vt CLI configuration.
    file: Get information about files stored in VirusTotal.
    url: Get information about URLs and URL analyses.
    scan: Submit files or URLs for scanning.
    search: Search VirusTotal Intelligence for matching samples.
    --format: Render command output as yaml, json, or csv.
    --apikey: Provide an API key directly on the command line.
*/
_:
let
  VtCliModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.vt-cli.extended;
    in
    {
      options.programs.vt-cli.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable vt-cli.";
        };

        package = lib.mkPackageOption pkgs "vt-cli" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.vt-cli = VtCliModule;
}
