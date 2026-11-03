{
  config,
  lib,
  metaOwner,
  secretsRoot,
  ...
}:
let
  secretFile = secretsRoot + "/workloads-ssh.yaml";
  inherit (config.flake.lib.nixos.hosts.songbird) sopsRuntimeReady;
  ready = sopsRuntimeReady && builtins.pathExists secretFile;
  keyPath = "/home/${metaOwner.username}/.ssh/keys/workloads-guest";
in
{
  configurations.nixos.songbird.module =
    { config, ... }:
    let
      patterns = lib.concatMap (guest: guest.hostnames) (
        lib.attrValues (lib.filterAttrs (_: guest: guest.ensure == "present") config.workloads.guests)
      );
    in
    {
      config = lib.mkMerge [
        (lib.mkIf (ready && patterns != [ ]) {
          home-manager.users.${metaOwner.username} = {
            sops.secrets."ssh/workloads-guest" = {
              sopsFile = secretFile;
              format = "yaml";
              key = "guest_ssh_key";
              path = keyPath;
              mode = "0400";
            };

            # ~/.ssh/config includes ~/.ssh/hosts/* ahead of its 1Password `Host *` block, so this wins for guests.
            home.file.".ssh/hosts/workloads".text = ''
              Host ${lib.concatStringsSep " " patterns}
                IdentityFile ${keyPath}
                IdentityAgent none
                IdentitiesOnly yes
            '';
          };
        })

        (lib.mkIf (!ready) {
          warnings = [
            "songbird workload guests use the 1Password SSH agent until ${toString secretFile} is available."
          ];
        })
      ];
    };
}
