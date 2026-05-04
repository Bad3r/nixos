/*
  Package: nuclei-templates
  Description: Curated detection templates that drive the nuclei vulnerability scanner.
  Homepage: https://github.com/projectdiscovery/nuclei-templates
  Documentation: https://docs.projectdiscovery.io/templates
  Repository: https://github.com/projectdiscovery/nuclei-templates

  Summary:
    * Installs the upstream template corpus covering CVEs, misconfigurations, default credentials, exposed panels, and DAST checks.
    * Provides templates for the http, dns, network, file, ssl, headless, code, javascript, and dast protocols, plus reusable workflow profiles.

  Options:
    /run/current-system/sw/share/nuclei-templates: Active system reference for the installed template tree.
    -t <category>/: Pass a category (e.g. `http/cves`, `network/`, `dns/`) to nuclei via `-t`.
    -w profiles/<file>.yml: Run a curated workflow profile bundled under `share/nuclei-templates/profiles`.

  Notes:
    * Data-only package; tools should reference files under `share/nuclei-templates` rather than expecting a CLI binary.
    * Pair with `programs.nuclei.extended.enable` and point `-ud` or `nuclei -update-template-dir` at this path to keep scans pinned to the system closure.
*/
_:
let
  NucleiTemplatesModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.nuclei-templates.extended;
    in
    {
      options.programs.nuclei-templates.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable nuclei-templates.";
        };

        package = lib.mkPackageOption pkgs "nuclei-templates" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.nuclei-templates = NucleiTemplatesModule;
}
