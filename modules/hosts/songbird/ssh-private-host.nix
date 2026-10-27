{
  config,
  lib,
  metaOwner,
  secretsRoot,
  ...
}:
let
  secretFile = secretsRoot + "/songbird.yaml";
  secretFileExists = builtins.pathExists secretFile;
  inherit (config.flake.lib.nixos.hosts.songbird) sopsRuntimeReady;
  ready = sopsRuntimeReady && secretFileExists;
  homeDirectory = "/home/${metaOwner.username}";
in
{
  configurations.nixos.songbird.module = {
    config = lib.mkMerge [
      (lib.mkIf ready {
        # Keep aliases and the account encrypted; the config path joins the
        # existing ~/.ssh/hosts/* include after user sops-nix activation.
        home-manager.users.${metaOwner.username}.sops.secrets = {
          "ssh/private-host/config" = {
            sopsFile = secretFile;
            format = "yaml";
            key = "private_ssh_host_config";
            path = "${homeDirectory}/.ssh/hosts/private-host";
            mode = "0400";
          };

          "ssh/private-host/identity-pub" = {
            sopsFile = secretFile;
            format = "yaml";
            key = "private_ssh_host_pubkey";
            path = "${homeDirectory}/.ssh/private-host-identity.pub";
            mode = "0444";
          };
        };
      })

      (lib.mkIf (!ready) {
        warnings = [
          "songbird private SSH host alias is disabled until SOPS decryption keys are configured and songbird.yaml is available."
        ];
      })
    ];
  };
}
