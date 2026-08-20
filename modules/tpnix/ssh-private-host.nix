{
  config,
  lib,
  metaOwner,
  secretsRoot,
  ...
}:
let
  secretFile = secretsRoot + "/tpnix.yaml";
  secretFileExists = builtins.pathExists secretFile;
  inherit (config.flake.lib.nixos.hosts.tpnix) sopsRuntimeReady;
  ready = sopsRuntimeReady && secretFileExists;
  homeDirectory = "/home/${metaOwner.username}";
in
{
  configurations.nixos.tpnix.module = {
    config = lib.mkMerge [
      (lib.mkIf ready {
        # Host aliases, address and account stay inside the encrypted block;
        # only the rendered file names are public. sops-install-secrets
        # symlinks each secret at its `path`, so the block lands inside the
        # ~/.ssh/hosts/* glob that programs.ssh.includes already carries
        # (modules/networking/ssh.nix). A dangling link before the user unit
        # runs is skipped by the glob rather than failing config parsing.
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
          "tpnix private SSH host alias is disabled until SOPS decryption keys are configured."
        ];
      })
    ];
  };
}
