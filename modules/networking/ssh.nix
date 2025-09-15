{ config, ... }:
let
  fpConfig = config;
in
{
  flake = {
    nixosModules.ssh =
      { lib, config, ... }:
      {
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
              ClientAliveInterval = 60;
              ClientAliveCountMax = 3;
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

          # Populate known_hosts from each host's declared public key
          programs.ssh.knownHosts = lib.mkIf (config.services.openssh.publicKey != null) (
            let
              host = config.networking.hostName or "";
              domain = config.networking.domain or "";
              fqdn = lib.optional (domain != "") "${host}.${domain}";
              hostNames = lib.unique ([ host ] ++ fqdn);
              stripComment =
                key:
                let
                  parts = builtins.filter (s: s != "") (lib.splitString " " key);
                in
                if (builtins.length parts) >= 2 then
                  "${builtins.elemAt parts 0} ${builtins.elemAt parts 1}"
                else
                  key;
            in
            lib.optionalAttrs (host != "") {
              "${host}" = {
                inherit hostNames;
                publicKey = stripComment config.services.openssh.publicKey;
              };
            }
          );

          users.users.${fpConfig.flake.lib.meta.owner.username}.openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGPoHVrToSwWfz+DaUX68A9v70V7k3/REqGxiDqjLOS+"
          ];
        };
      };

    homeManagerModules.base =
      { config, ... }:
      let
        home = config.home.homeDirectory;
      in
      {
        programs.ssh = {
          enable = true;
          enableDefaultConfig = false;
          includes = [ "${home}/.ssh/hosts/*" ];
          matchBlocks = {
            "*" = {
              identitiesOnly = true;
              identityAgent = "${home}/.gnupg/S.gpg-agent.ssh";
              addKeysToAgent = "yes";
              identityFile = [ "${home}/.ssh/id_ed25519" ];
              setEnv.TERM = "xterm-256color";
              compression = false;
              hashKnownHosts = false;
            };
          };
        };
      };
  };
}
