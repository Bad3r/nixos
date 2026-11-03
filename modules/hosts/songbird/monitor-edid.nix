{
  config,
  lib,
  secretsRoot,
  ...
}:
let
  secretFile = secretsRoot + "/songbird-monitor.edid";
  inherit (config.flake.lib.nixos.hosts.songbird) sopsRuntimeReady;
  ready = sopsRuntimeReady && builtins.pathExists secretFile;
in
{
  configurations.nixos.songbird.module =
    { config, ... }:
    {
      config = lib.mkMerge [
        (lib.mkIf ready {
          # The EDID carries the panel's serial number.
          sops.secrets."songbird/monitor-edid" = {
            sopsFile = secretFile;
            format = "binary";
            mode = "0400";
          };

          # Keeps a screen for RustDesk while the panel sleeps off the bus.
          gpu.nvidia.alwaysConnected = {
            device = "DFP-5";
            edid = config.sops.secrets."songbird/monitor-edid".path;
          };
        })

        (lib.mkIf (!ready) {
          warnings = [
            "songbird keeps no X screen while its monitor sleeps until SOPS decryption keys are configured and songbird-monitor.edid is available."
          ];
        })
      ];
    };
}
