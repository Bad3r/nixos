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
          default-cache-ttl = 27900;
          default-cache-ttl-ssh = 27900;
          max-cache-ttl = 27900;
          max-cache-ttl-ssh = 27900;
        };
      };
    };
}
