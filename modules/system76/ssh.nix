{ lib, ... }:
{
  configurations.nixos.system76.module = {
    services.openssh = {
      enable = lib.mkDefault false;
      # Host SSH public key for known_hosts population (consumed by nixosModules.ssh)
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKzgpGcpEJ7oOxjcKyr6/2/joFKN+yDP0G3YyTbp/ilb root@system76";
    };
  };
}
