/*
  Package: wgcf
  Description: WireGuard profile generator for Cloudflare WARP and Zero Trust.
  Homepage: https://github.com/ViRb3/wgcf
  Documentation: https://github.com/ViRb3/wgcf#readme
  Repository: https://github.com/ViRb3/wgcf

  Summary:
    * Registers Cloudflare WARP accounts and generates WireGuard profiles for standard WireGuard clients.

  Options:
    --accept-tos: Accept Cloudflare's terms during `wgcf register`.
    --profile <path>: Write the generated profile to a custom path with `wgcf generate`.
    --config <file>: Use a specific account configuration file.
*/
_:
let
  WgcfModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.wgcf.extended;
    in
    {
      options.programs.wgcf.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable wgcf.";
        };

        package = lib.mkPackageOption pkgs "wgcf" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.wgcf = WgcfModule;
}
