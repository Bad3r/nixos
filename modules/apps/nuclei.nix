/*
  Package: nuclei
  Description: Template-based vulnerability scanner focusing on configurability, extensibility, and ease of use.
  Homepage: https://github.com/projectdiscovery/nuclei
  Documentation: https://docs.projectdiscovery.io/tools/nuclei
  Repository: https://github.com/projectdiscovery/nuclei

  Summary:
    * Executes YAML-based detection templates against URLs, hosts, or file lists with high concurrency and structured output.
    * Slots into the ProjectDiscovery pipeline downstream of subfinder, dnsx, and httpx for end-to-end recon and exploitation triage.

  Options:
    -u <target>: Target URL or host to scan (repeatable).
    -l <file>: Read targets from a file, one per line.
    -t <path>: Run only templates matching the given path or directory.
    -tags <list>: Filter templates by comma-separated tags (e.g. `cve,oast`).
    -severity <list>: Limit execution to templates of the listed severities (info, low, medium, high, critical).
    -as / -automatic-scan: Use wappalyzer-style technology detection to pick relevant templates automatically.
    -o <file>: Write findings to the specified output file.
    -j / -jsonl: Emit JSON-line output suitable for downstream tooling.
    -ud <dir>: Override the templates directory (defaults to `$HOME/.local/nuclei-templates`).
*/
_:
let
  NucleiModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.nuclei.extended;
    in
    {
      options.programs.nuclei.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable nuclei.";
        };

        package = lib.mkPackageOption pkgs "nuclei" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.nuclei = NucleiModule;
}
