{ lib, ... }:
{
  configurations.nixos.songbird.module = {
    services.openssh = {
      enable = lib.mkDefault false;
      # publicKey is unset until the first boot on this configuration
      # generates /etc/ssh/ssh_host_ed25519_key.pub (the stock install never
      # ran sshd). Pin it here and in modules/hosts/common/ssh-known-hosts.nix
      # in the same change: modules/configurations/nixos.nix rejects a host
      # key without a matching fleetHostKeys entry.
    };
  };
}
