/*
  Package: wappalyzer-next
  Description: CLI for detecting website technology stacks powered by Wappalyzer fingerprints.
  Repository: https://github.com/s0md3v/wappalyzer-next

  Summary:
    * Provides the `wappalyzer` command backed by the latest Wappalyzer dataset.
*/
_:
let
  WappalyzerNextModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."wappalyzer-next".extended;
    in
    {
      options.programs."wappalyzer-next".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Wappalyzer Next.";
        };

        package = lib.mkPackageOption pkgs "wappalyzer-next" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."wappalyzer-next" = WappalyzerNextModule;
}
