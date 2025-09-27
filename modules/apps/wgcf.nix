/*
  Package: wgcf
  Description: WireGuard profile generator for Cloudflare WARP and Zero Trust.
  Homepage: https://github.com/ViRb3/wgcf
  Documentation: https://github.com/ViRb3/wgcf#readme
  Repository: https://github.com/ViRb3/wgcf

  Summary:
    * Registers Cloudflare WARP accounts and derives WireGuard configuration profiles for 1.1.1.1 with WARP.
    * Enables headless provisioning of WARP tunnels compatible with standard WireGuard clients.

  Options:
    --accept-tos: Required switch for `wgcf register --accept-tos` to acknowledge Cloudflare's terms.
    --profile <path>: Write the generated WireGuard configuration to a custom path with `wgcf generate --profile`.
    --config <file>: Load or update account metadata from a specific configuration file during `wgcf update --config`.
*/

{
  flake.nixosModules.apps.wgcf =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.wgcf ];
    };
}
