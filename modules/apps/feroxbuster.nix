/*
  Package: feroxbuster
  Description: Fast recursive content discovery tool for web directories, files, and parameters.
  Homepage: nil
  Documentation: https://epi052.github.io/feroxbuster-docs/
  Repository: https://github.com/epi052/feroxbuster

  Summary:
    * Performs recursive brute-force discovery across web paths with filtering, replay proxies, and parallel request tuning.
    * Supports automatic recursion, extension collection, response-size filtering, and wordlist-driven fuzzing.

  Options:
    feroxbuster -u <url>: Start a recursive content discovery scan against the target URL.
    -w <wordlist>: Supply a custom wordlist instead of the built-in defaults.
    --proxy <url>: Route requests through an intercepting proxy such as Burp Suite or ZAP.
*/
_:
let
  FeroxbusterModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.feroxbuster.extended;
    in
    {
      options.programs.feroxbuster.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable feroxbuster.";
        };

        package = lib.mkPackageOption pkgs "feroxbuster" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.feroxbuster = FeroxbusterModule;
}
