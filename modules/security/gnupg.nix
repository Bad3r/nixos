{
  flake.nixosModules.base =
    { pkgs, ... }:
    {
      programs.gnupg.agent = {
        enable = true;
        enableSSHSupport = true;
        enableExtraSocket = true;
        pinentryPackage = pkgs.pinentry-curses;
        # Cache GPG/SSH passphrases for ~15 minutes
        # Modern NixOS uses agent.settings mapped to gpg-agent.conf keys
        settings = {
          default-cache-ttl = 900;
          default-cache-ttl-ssh = 900;
          max-cache-ttl = 900;
          max-cache-ttl-ssh = 900;
        };
      };
    };
}
