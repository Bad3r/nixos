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

          # `workloads grant` and `revoke` reach the proxy through it, which starts on first use.
          sockets.sbx-vsock = {
            Unit.Description = "Control socket of the sbx vsock grant proxy";
            Socket = {
              ListenStream = "%t/sbx/vsock.sock";
              SocketMode = "0600";
              DirectoryMode = "0700";
            };
            Install.WantedBy = [ "sockets.target" ];
          };

          services = {
            # sbx starts it before connecting; QEMU, virtlogd, and their helpers inherit its cgroup.
            sbx-libvirt = {
              Unit.Description = "libvirt session daemon for sbx sandboxes";
              Service = {
                Type = "notify";
                ExecStart = "${libvirtCfg.package}/bin/virtqemud --timeout 600";
                Slice = "sbx.slice";
                # Guests outlive a daemon restart, and the next daemon reattaches to them.
                KillMode = "process";
              };
            };

            # Holds every vsock grant's listeners and connections, so they all close with it.
            sbx-vsock = {
              Unit = {
                Description = "Listeners for vsock grants inside sbx sandbox namespaces";
                # A restarted socket reaches only a proxy started after it.
                PartOf = [ "sbx-vsock.socket" ];
              };
              Service = {
                ExecStart = "${sbx} vsock serve";
                Restart = "on-failure";
                # A grant without a port listens on every port of its ranges.
                LimitNOFILE = 65536;
                NoNewPrivileges = true;
                RestrictAddressFamilies = [
                  "AF_UNIX"
                  "AF_INET"
                  "AF_VSOCK"
                ];
              };
            };

            sbx-gc = {
              Unit.Description = "Remove expired and orphaned sbx sandboxes";
              Service = {
                Type = "oneshot";
                ExecStart = "${sbx} gc";
              };
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
