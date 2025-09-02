{
  configurations.nixos.tec.module = _: {
    # SSH server configuration
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "no";
      };
    };

    # SSH public key will be generated on first boot
    # Can be found at /etc/ssh/ssh_host_ed25519_key.pub after installation

    # SSH client configuration
    programs.ssh = {
      extraConfig = ''
        Host *
          IdentityAgent /run/user/1000/gnupg/S.gpg-agent.ssh
          SetEnv OPENSSL_CONF=/etc/ssl/openssl.cnf
      '';
    };
  };
}
