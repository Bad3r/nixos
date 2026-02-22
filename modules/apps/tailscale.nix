/*
  Package: tailscale
  Description: Node agent for Tailscale, a mesh VPN built on WireGuard.
  Homepage: https://tailscale.com
  Documentation: https://tailscale.com/kb/
  Repository: https://github.com/tailscale/tailscale

  Summary:
    * Installs the Tailscale client and daemon used to join tailnets and route traffic over WireGuard.
    * Enables the NixOS tailscaled service so networking state is managed declaratively.

  Options:
    tailscale up: Bring the node online and apply advertised routes or exit-node settings.
    tailscale status: Show peer connectivity, tunnel health, and route state.
    tailscale ssh <target>: Open an SSH session over the tailnet identity plane.
*/
_:
let
  TailscaleModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.tailscale.extended;
    in
    {
      options.programs.tailscale.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable tailscale.";
        };

        package = lib.mkPackageOption pkgs "tailscale" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

        services.tailscale = {
          enable = true;
          inherit (cfg) package;
        };
      };
    };
in
{
  flake.nixosModules.apps.tailscale = TailscaleModule;
}
