{ lib, ... }:
{
  configurations.nixos.system76.module = _: {
    # Host SSH public key for known_hosts population (consumed by nixosModules.ssh)
    services.openssh.publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKzgpGcpEJ7oOxjcKyr6/2/joFKN+yDP0G3YyTbp/ilb root@system76";
    # Prepare secure sshd settings without enabling the service on this host
    services.openssh = {
      enable = lib.mkDefault false;
      settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "no";
      };
    };
  };
}
