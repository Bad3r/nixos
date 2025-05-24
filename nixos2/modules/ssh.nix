# modules/ssh.nix

{ lib, config, ... }:
let
  reachableNixoss =
    config.flake.nixosConfigurations
    |> lib.filterAttrs (
      _name: nixos:
      !(lib.any isNull [
        nixos.config.networking.domain
        nixos.config.networking.hostName
        nixos.config.services.openssh.publicKey
      ])
    );
in
{
  flake.modules = {
    nixos.pc = {
      options.services.openssh.publicKey = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };

      config = {
        services.openssh = {
          enable = false;
          openFirewall = true;
          ports = [ 6234 ];
          hostKeys = [
            {
              comment = "Bad3r @${config.networking.hostName}";
              type = "ed25519";
              rounds = 100;
              path = "/etc/ssh/ed25519";
            } # automatically generate key w/ ssh-keygen
          ];

          settings = {
            PasswordAuthentication = false;
            PermitRootLogin = "no";
          };

          extraConfig = ''
            Include /etc/ssh/sshd_config.d/*
          '';
        };
        # TODO: add ssh key
        users.users.${config.flake.meta.owner.username}.openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAAAAAAAAAAAAAAAAAAAAAA"
        ];

        programs.ssh.knownHosts =
          reachableNixoss
          |> lib.mapAttrs (
            _name: nixos: {
              hostNames = [ nixos.config.networking.fqdn ];
              inherit (nixos.config.services.openssh) publicKey;
            }
          );
      };
    };

    homeManager.base = args: {
      programs.ssh = {
        enable = true;
        compression = true;
        hashKnownHosts = false;
        includes = [ "${args.config.home.homeDirectory}/.ssh/hosts/*" ];
        matchBlocks =
          reachableNixoss
          |> lib.mapAttrsToList (
            _name: nixos: {
              "${nixos.config.networking.fqdn}" = {
                identityFile = "ed25519";
              };
            }
          )
          |> lib.concat [
            {
              "*" = {
                setEnv.TERM = "xterm-256color";
                identitiesOnly = true;
              };
            }
          ]
          |> lib.mkMerge;
      };
    };
  };
}
