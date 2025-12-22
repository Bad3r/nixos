_: {
  flake = {
    nixosModules.ssh =
      {
        lib,
        config,
        metaOwner,
        ...
      }:
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

          # SSH keys are set in modules/meta/owner.nix using metaOwner.sshKeys
        };
      };

    homeManagerModules.base =
      { metaOwner, ... }:
      let
        homeDirectory = "/home/${metaOwner.username}";
      in
      {
        programs.ssh = {
          enable = true;
          enableDefaultConfig = false;
          # Use metaOwner instead of config.home.homeDirectory
          includes = [ "${homeDirectory}/.ssh/hosts/*" ];
          matchBlocks = {
            "*" = {
              identitiesOnly = true;
              identityAgent = "${homeDirectory}/.gnupg/S.gpg-agent.ssh";
              addKeysToAgent = "yes";
              identityFile = [ "${homeDirectory}/.ssh/id_ed25519" ];
              setEnv.TERM = "xterm-256color";
              compression = false;
              hashKnownHosts = false;
            };
          };
        };
      };
  };
}
