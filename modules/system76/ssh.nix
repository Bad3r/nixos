{ lib, ... }:
{
  configurations.nixos.system76.module = _: {
    # This is the host's SSH public key from /etc/ssh/ssh_host_ed25519_key.pub
    # Used for SSH known_hosts entries
    services.openssh.publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBexeVWyByGvdIKyr6A5B71MKquyPCvdgyhP8DMrNmHm root@system76";

    # SSH client configuration
    programs.ssh = {
      extraConfig = ''
        Host *
          SetEnv OPENSSL_CONF=/etc/ssl/openssl.cnf
      '';
    };

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
