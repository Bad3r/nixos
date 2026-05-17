/*
  Package: assetfinder
  Description: Find domains and subdomains potentially related to a given domain.
  Homepage: nil
  Documentation: nil
  Repository: https://github.com/tomnomnom/assetfinder

  Summary:
    * Queries passive sources such as crt.sh, certspotter, hackertarget, wayback machine, and optional API-backed providers.
    * Emits discovered domains on stdout for use in recon pipelines.

  Options:
    assetfinder <domain>: Find domains and subdomains related to the supplied domain.
    --subs-only: Only include subdomains of the search domain.

  Notes:
    * Some upstream sources require environment variables such as `FB_APP_ID`, `FB_APP_SECRET`, `VT_API_KEY`, or `SPYSE_API_TOKEN`.
*/
_:
let
  AssetfinderModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.assetfinder.extended;
    in
    {
      options.programs.assetfinder.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable assetfinder.";
        };

        package = lib.mkPackageOption pkgs "assetfinder" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.assetfinder = AssetfinderModule;
}
