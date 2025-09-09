{ lib, config, ... }:
let
  reachableNixoss = lib.filterAttrs (
    _name: nixos:
    !(lib.any isNull [
      nixos.config.networking.domain
      nixos.config.networking.hostName
      nixos.config.services.openssh.publicKey
    ])
  ) config.flake.nixosConfigurations;
in
{
  flake = {
    nixosModules.base = {
      options.services.openssh.publicKey = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };

      config = {
        services.openssh = {
          enable = true;
          openFirewall = true;

          settings = {
            PasswordAuthentication = false;
            # Keepalive settings for connection stability
            ClientAliveInterval = 60;
            ClientAliveCountMax = 3;
            # Security hardening
            MaxAuthTries = 3;
            MaxSessions = 10;
            LogLevel = "INFO";
          };

          extraConfig = ''
            Include /etc/ssh/sshd_config.d/*
            Protocol 2
            Banner none
          '';
        };

        users.users.${config.flake.lib.meta.owner.username}.openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGPoHVrToSwWfz+DaUX68A9v70V7k3/REqGxiDqjLOS+"
        ];

        programs.ssh.knownHosts = lib.mapAttrs (_name: nixos: {
          hostNames = [ nixos.config.networking.fqdn ];
          inherit (nixos.config.services.openssh) publicKey;
        }) reachableNixoss;
      };
    };

    homeManagerModules.base = args: {
      programs.ssh = {
        enable = true;
        enableDefaultConfig = false; # Explicitly disable default config to avoid deprecation warning
        includes = [ "${args.config.home.homeDirectory}/.ssh/hosts/*" ];
        # Keep only sane defaults in the main config; host-specific
        # settings are provided via per-file includes in ~/.ssh/hosts/*.
        matchBlocks = {
          "*" = {
            identitiesOnly = true;
            setEnv.TERM = "xterm-256color";
            compression = false;
            hashKnownHosts = false;
          };
        };
      };
    };
  };
}
