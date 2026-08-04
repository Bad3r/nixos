/*
  Package: wafw00f
  Description: Identify and fingerprint the Web Application Firewall protecting a site.
  Homepage: nil
  Documentation: nil
  Repository: https://github.com/EnableSecurity/wafw00f

  Summary:
    * Sends crafted requests and analyzes the responses to detect and name the WAF (if any) fronting a target.
    * Recognizes a large set of WAF products; complements cdncheck's passive WAF detection with active probing.

  Options:
    -a, --findall: Report every matching WAF instead of stopping at the first.
    -l, --list: List all WAFs that wafw00f can detect.
    -i, --input <file>: Read targets from a file (text, JSON, or CSV).
    -o, --output <file>: Write results to the specified file.
    -f, --format <fmt>: Output format (json, csv, text) when writing to a file.
    -p, --proxy <url>: Route requests through the given proxy.
*/
_:
let
  Wafw00fModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.wafw00f.extended;
    in
    {
      options.programs.wafw00f.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable wafw00f.";
        };

        package = lib.mkPackageOption pkgs "wafw00f" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.wafw00f = Wafw00fModule;
}
