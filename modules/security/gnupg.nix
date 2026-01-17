{
  flake.nixosModules.base =
    { pkgs, ... }:
    {
      programs.gnupg.agent = {
        enable = true;
        enableSSHSupport = true;
        enableExtraSocket = true;
        pinentryPackage = pkgs.pinentry-curses;
        # Cache GPG/SSH passphrases for 8 hours
        # Modern NixOS uses agent.settings mapped to gpg-agent.conf keys
        settings = {
          default-cache-ttl = 28800;
          default-cache-ttl-ssh = 28800;
          max-cache-ttl = 28800;
          max-cache-ttl-ssh = 28800;
        };
      };
    };
}
