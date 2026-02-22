/*
  Package: tailscale
  Description: Node agent for Tailscale, a mesh VPN built on WireGuard.
  Homepage: https://tailscale.com
  Documentation: https://tailscale.com/kb/
  Repository: https://github.com/tailscale/tailscale

  Summary:
    * Installs the Tailscale client and daemon used to join tailnets and route traffic over WireGuard.
    * Enables the NixOS tailscaled service so networking state is managed declaratively.
    * Exposes common service and SSH host settings through `programs.tailscale.extended`.

  Options:
    tailscale up: Bring the node online and apply advertised routes or exit-node settings.
    tailscale status: Show peer connectivity, tunnel health, and route state.
    tailscale ssh <target>: Open an SSH session over the tailnet identity plane.
    authKeyFile: Optional file path containing a reusable auth key for non-interactive node registration.
    extraSetFlags: Additional arguments passed to `tailscale set` after daemon startup.
    interfaceName: Override the network interface name used by tailscaled (default `tailscale0`).
    sshHostAlias: Host alias written to `~/.ssh/hosts/<alias>` when tailscale is enabled.
    sshHostName: HostName used in the generated SSH match block (IP or MagicDNS name).
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

        authKeyFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Optional path to a Tailscale auth key file used by tailscaled.";
        };

        extraSetFlags = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Additional flags passed to `tailscale set` by the NixOS module.";
        };

        interfaceName = lib.mkOption {
          type = lib.types.str;
          default = "tailscale0";
          description = "Network interface name used for the tailscale tunnel.";
        };

        sshHostAlias = lib.mkOption {
          type = lib.types.str;
          default = "tailscale";
          description = "SSH host alias generated under `~/.ssh/hosts/` for tailscale access.";
        };

        sshHostName = lib.mkOption {
          type = lib.types.str;
          default = "100.64.1.5";
          description = "SSH HostName for the tailscale host entry (IP or MagicDNS name).";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

        services.tailscale = lib.mkMerge [
          {
            enable = true;
            inherit (cfg) package interfaceName extraSetFlags;
          }
          (lib.mkIf (cfg.authKeyFile != null) {
            inherit (cfg) authKeyFile;
          })
        ];
      };
    };
in
{
  flake.nixosModules.apps.tailscale = TailscaleModule;
}
