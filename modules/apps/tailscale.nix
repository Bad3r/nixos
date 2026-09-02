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
    operator: Unix user allowed to change tailscaled state without root, applied as
      `tailscale set --operator`. Defaults to `flake.lib.meta.owner.username`; null
      leaves `tailscale up`, `down`, and `set` to root.
    sshHostAlias: Host alias written to `~/.ssh/hosts/<alias>` when tailscale is enabled.
    sshHostName: HostName used in the generated SSH match block (IP or MagicDNS name).
      Defaults to the `tailnetIp` of the registry host marked `primary` in
      `flake.lib.nixos.hosts`, so a primary-host handoff is a registry data change.
*/
{ config, lib, ... }:
let
  fleetHosts = config.flake.lib.nixos.hosts or { };
  ownerUsername = config.flake.lib.meta.owner.username or null;
  primaryTailnetIp = lib.findFirst (ip: ip != null) null (
    lib.mapAttrsToList (_: host: host.tailnetIp or null) (
      lib.filterAttrs (_: host: host.primary or false) fleetHosts
    )
  );
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

        operator = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = ownerUsername;
          description = ''
            Unix user allowed to change tailscaled state without root, passed as
            `tailscale set --operator`. Without it `tailscale up`, `tailscale down`
            and `tailscale set` answer only root, so user-facing tooling such as
            captive-portal cannot release or restore DNS. null keeps that default.
          '';
        };

        sshHostAlias = lib.mkOption {
          type = lib.types.str;
          default = "tailscale";
          description = "SSH host alias generated under `~/.ssh/hosts/` for tailscale access.";
        };

        sshHostName = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = primaryTailnetIp;
          description = ''
            SSH HostName for the tailscale host entry (IP or MagicDNS name).
            Defaults to the tailnetIp of the flake.lib.nixos.hosts entry marked
            primary; null skips the generated ~/.ssh/hosts alias.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

        # `tailscale set --operator` names a Unix user, and tailscaled resolves it
        # at runtime: a name no host account carries fails the tailscaled-set unit
        # after the switch instead of at eval.
        assertions = lib.optional (cfg.operator != null) {
          assertion = config.users.users ? ${cfg.operator};
          message = "programs.tailscale.extended.operator is '${cfg.operator}', which is not a declared user.";
        };

        services.tailscale = lib.mkMerge [
          {
            enable = true;
            inherit (cfg) package interfaceName;
            # nixpkgs runs `tailscale set` from a root oneshot only when this list
            # is non-empty, so the operator pref is re-applied on every boot.
            extraSetFlags =
              cfg.extraSetFlags ++ lib.optional (cfg.operator != null) "--operator=${cfg.operator}";
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
