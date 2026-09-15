# Cross-host SSH host-key pinning: every shared host carries the other
# fleet members' host keys in /etc/ssh/ssh_known_hosts, so the first
# connection between fleet hosts is never trust-on-first-use (issue #349).
# Each host's own key is pinned separately by nixosModules.ssh from
# services.openssh.publicKey. A host's Cloudflare Mesh address (meshIp in
# modules/<host>/policy.nix) joins its names once recorded, so the
# <host>.warp alias from modules/networking/ssh-hosts.nix is pinned too.
# Pins come from fleetHostKeys below; modules/networking/ssh-hosts.nix refuses
# a meshIp for a host without an entry here, while .local aliases stay unpinned.
# The tailnet FQDN is intentionally not listed: this repository is public
# and the MagicDNS name is not disclosed here.
# GitHub's key is pinned for the same reason: the github.com alias in
# modules/networking/ssh-hosts.nix routes through ssh.github.com:443, and
# non-interactive git (plugin marketplaces, submodules) fails on an unknown key.
{ config, lib, ... }:
let
  meshIpOf = config.flake.lib.nixos.meshIpOf;

  fleetHostKeys = {
    songbird = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINptd1paBJhCCHf8L2FolFAcCtzlBJQp6SIi4dLSiP53";
    tpnix = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBhF9ZGsiViA4iOeGgNSjlzIcSdHZV0m3kTXU6fHusJ0";
  };

  # Published at https://api.github.com/meta (ssh_keys); same key serves ssh.github.com:443.
  githubHostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";

  body =
    { config, ... }:
    {
      programs.ssh.knownHosts =
        lib.mapAttrs' (
          name: publicKey:
          let
            meshIp = meshIpOf name;
          in
          lib.nameValuePair "fleet-${name}" {
            hostNames = [
              name
              "${name}.local"
            ]
            ++ lib.optional (meshIp != null) meshIp;
            inherit publicKey;
          }
        ) (lib.filterAttrs (name: _: name != config.networking.hostName) fleetHostKeys)
        // {
          github = {
            hostNames = [
              "github.com"
              "ssh.github.com"
              "[ssh.github.com]:443"
            ];
            publicKey = githubHostKey;
          };
        };
    };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
  flake.lib.nixos.fleetHostKeys = fleetHostKeys;
}
