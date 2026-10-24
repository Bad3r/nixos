_: {
  flake.homeManagerModules.apps.sbx =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "sbx" "extended" "enable" ] false osConfig;
      cfg = osConfig.programs.sbx.extended;
      libvirtCfg = osConfig.programs.libvirt.extended;
      sbx = lib.getExe cfg.finalPackage;
      descriptors = [
        "50-edk2-x86_64-secure.json"
        "60-edk2-x86_64.json"
      ];
    in
    {
      config = lib.mkIf nixosEnabled {
        # An unprivileged libvirt reads firmware descriptors from here, not from /var/lib/qemu.
        xdg.configFile = lib.listToAttrs (
          map (file: {
            name = "qemu/firmware/${file}";
            value.source = "${libvirtCfg.qemuPackage}/share/qemu/firmware/${file}";
          }) descriptors
        );

        systemd.user = {
          slices.sbx = {
            Unit.Description = "sbx agent sandboxes";
            Slice = {
              MemoryHigh = "${toString (cfg.limits.sliceMemory - 1)}G";
              MemoryMax = "${toString cfg.limits.sliceMemory}G";
              CPUWeight = 50;
              IOWeight = 50;
            };
          };

          # sbx starts it before connecting; QEMU, virtlogd, and their helpers inherit its cgroup.
          services.sbx-libvirt = {
            Unit.Description = "libvirt session daemon for sbx sandboxes";
            Service = {
              Type = "notify";
              ExecStart = "${libvirtCfg.package}/bin/virtqemud --timeout 600";
              Slice = "sbx.slice";
              # Guests outlive a daemon restart, and the next daemon reattaches to them.
              KillMode = "process";
            };
          };

          services.sbx-gc = {
            Unit.Description = "Remove expired and orphaned sbx sandboxes";
            Service = {
              Type = "oneshot";
              ExecStart = "${sbx} gc";
            };
          };

          timers.sbx-gc = {
            Unit.Description = "Remove expired and orphaned sbx sandboxes every 15 minutes";
            Timer.OnCalendar = "*:0/15";
            Install.WantedBy = [ "timers.target" ];
          };
        };
      };
    };
}
