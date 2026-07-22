# Cross-host SSH host-key pinning: every shared host carries the other
# fleet members' host keys in /etc/ssh/ssh_known_hosts, so the first
# connection between fleet hosts is never trust-on-first-use (issue #349).
# Each host's own key is pinned separately by nixosModules.ssh from
# services.openssh.publicKey. The tailnet FQDN is intentionally not listed:
# this repository is public and the MagicDNS name is not disclosed here.
{ lib, ... }:
let
  fleetHostKeys = {
    system76 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKzgpGcpEJ7oOxjcKyr6/2/joFKN+yDP0G3YyTbp/ilb";
    tpnix = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBhF9ZGsiViA4iOeGgNSjlzIcSdHZV0m3kTXU6fHusJ0";
  };

  body =
    { config, ... }:
    {
      programs.ssh.knownHosts = lib.mapAttrs' (
        name: publicKey:
        lib.nameValuePair "fleet-${name}" {
          hostNames = [
            name
            "${name}.local"
          ];
          inherit publicKey;
        }
      ) (lib.filterAttrs (name: _: name != config.networking.hostName) fleetHostKeys);
    };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
