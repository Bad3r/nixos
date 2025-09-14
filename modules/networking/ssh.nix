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
      options = {
        services.openssh.publicKey = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };

        dendritic.ssh.serverDefaults.enable =
          lib.mkEnableOption "Enable curated OpenSSH server defaults"
          // {
            default = true;
          };
      };

      config =
        let
          serverCfg = config.dendritic.ssh.serverDefaults;
        in
        lib.mkIf serverCfg.enable {
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

            # Keep extraConfig minimal and audited
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

    homeManagerModules.base =
      { lib, config, ... }:
      let
        cfg = config.dendritic.ssh.clientDefaults;
        home = config.home.homeDirectory;
      in
      {
        options.dendritic.ssh.clientDefaults.enable =
          lib.mkEnableOption "Enable curated SSH client defaults"
          // {
            default = true;
          };

        config = lib.mkIf cfg.enable {
          programs.ssh = {
            enable = true;
            # Disable HM default config to avoid deprecation log
            enableDefaultConfig = false;
            includes = [ "${home}/.ssh/hosts/*" ];
            # Typed defaults; host-specific overrides live in ~/.ssh/hosts/* files
            matchBlocks = {
              "*" = {
                identitiesOnly = true;
                # Use GPG agent's stable symlink for SSH agent socket
                identityAgent = "${home}/.gnupg/S.gpg-agent.ssh";
                # Auto-add keys to agent on first use
                addKeysToAgent = "yes";
                # Default identity file; host-specific files can override in includes
                identityFile = [ "${home}/.ssh/id_ed25519" ];
                setEnv.TERM = "xterm-256color";
                compression = false;
                hashKnownHosts = false;
              };
            };
          };
        };
      };
  };
}
