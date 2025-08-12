{ config, ... }:
{
  configurations.nixos.system76.module = {
    # This is the host's SSH public key from /etc/ssh/ssh_host_ed25519_key.pub
    # Used for SSH known_hosts entries
    services.openssh.publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBexeVWyByGvdIKyr6A5B71MKquyPCvdgyhP8DMrNmHm root@system76";
  };
}