{ lib, ... }:
{
  configurations.nixos.tpnix.module = {
    services.openssh = {
      enable = lib.mkDefault false;
      # Host SSH public key for known_hosts population (consumed by nixosModules.ssh)
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBhF9ZGsiViA4iOeGgNSjlzIcSdHZV0m3kTXU6fHusJ0";
    };
  };
}
