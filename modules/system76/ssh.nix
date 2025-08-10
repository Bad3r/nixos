# Module: system76/ssh.nix
# Purpose: Host-specific SSH public key for system76
# Pattern: This is the HOST's SSH public key, not user's authorized_keys
# Note: This should be the actual host key from /etc/ssh/ssh_host_ed25519_key.pub

{ config, ... }:
{
  configurations.nixos.system76.module = {
    # TODO: Replace with actual host SSH public key from the system
    # This is used for SSH known_hosts entries
    services.openssh.publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHj4fDeDKrAatG6IW5aEgA4ym8l+hj/r7Upeos11Gqu5 bad3r@unsigned.sh";
  };
}