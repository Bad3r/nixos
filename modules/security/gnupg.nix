{
  flake.nixosModules.base =
    { pkgs, ... }:
    let
      pinentryDispatch = pkgs.callPackage ../../packages/pinentry-dispatch { };
    in
    {
      programs.gnupg.agent = {
        enable = true;
        enableSSHSupport = true;
        enableExtraSocket = true;
        pinentryPackage = pinentryDispatch;
        # Cache GPG/SSH passphrases for 8 hours
        # Modern NixOS uses agent.settings mapped to gpg-agent.conf keys
        settings = {
          default-cache-ttl = 28800;
          default-cache-ttl-ssh = 28800;
          max-cache-ttl = 28800;
          max-cache-ttl-ssh = 28800;
          # Avoid delayed fallback through secret-service when a secret-service query
          # stalls; go directly to pinentry instead.
          "no-allow-external-cache" = "";
        };
      };
    };
}
