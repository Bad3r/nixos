_:
let
  sleepModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      python = pkgs.python3.withPackages (ps: [ ps.libvirt ]);
      systemctl = "${config.systemd.package}/bin/systemctl";
      vmSleep = "${python.interpreter} -I ${./_vm-sleep.py}";

      # Pre phase per sleep unit.
      phases = {
        systemd-suspend = "pause";
        systemd-hibernate = "save";
        systemd-hybrid-sleep = "save";
        systemd-suspend-then-hibernate = "save";
      };

      # Covers qemu:///system; session guests need the same phase run per user.
      hook = phase: [ "${vmSleep} ${phase} --systemctl ${systemctl}" ];
    in
    {
      config = lib.mkIf config.programs.libvirt.extended.enable {
        systemd.services =
          lib.mapAttrs (_: phase: {
            serviceConfig = {
              # Ahead of other pre commands, such as an unmount a guest could hold busy.
              ExecStartPre = lib.mkBefore (hook phase);
              # Queued, so the resume path never waits on guests; ahead of other
              # post commands, since a failing one skips the rest.
              ExecStopPost = lib.mkBefore [
                "${systemctl} start --no-block workloads-vm-wake.service"
              ];
            };
          }) phases
          // {
            workloads-vm-wake = {
              description = "Resume and restore guests after host sleep";
              # Starts once each sleep unit has run its whole ExecStopPost list.
              after = map (unit: "${unit}.service") (lib.attrNames phases);
              # loginctl, runuser, and notify-send for the failure notification.
              path = [
                config.systemd.package
                pkgs.util-linux
                pkgs.libnotify
              ];
              serviceConfig = {
                Type = "oneshot";
                ExecStart = hook "wake";
              };
            };
          };
      };
    };
in
{
  flake.nixosModules."workloads-vms" = sleepModule;
}
