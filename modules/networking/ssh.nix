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
  flake.modules = {
    nixos.base = {
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

        users.users.${config.flake.meta.owner.username}.openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGPoHVrToSwWfz+DaUX68A9v70V7k3/REqGxiDqjLOS+"
        ];

        programs.ssh.knownHosts = lib.mapAttrs (_name: nixos: {
          hostNames = [ nixos.config.networking.fqdn ];
          inherit (nixos.config.services.openssh) publicKey;
        }) reachableNixoss;
      };
    };

    homeManager.base = args: {
      programs.ssh = {
        enable = true;
        compression = true;
        hashKnownHosts = false;
        includes = [ "${args.config.home.homeDirectory}/.ssh/hosts/*" ];
        matchBlocks = lib.mkMerge (
          (lib.mapAttrsToList (_name: nixos: {
            "${nixos.config.networking.fqdn}" = {
              identityFile = "~/.ssh/id_ed25519";
            };
          }) reachableNixoss)
          ++ [
            {
              # Tailscale host configuration
              "system76-tailscale" = {
                hostname = "100.64.1.5";
                user = args.config.home.username;
                port = 22;
                forwardX11 = true;
                forwardAgent = true;
              };
            }
            {
              "*" = {
                setEnv.TERM = "xterm-256color";
                identitiesOnly = true;
              };
            }
          ]
        );
      };
    };
  };
}
