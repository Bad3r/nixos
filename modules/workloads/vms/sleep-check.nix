# Needs /dev/kvm, so CI only forces its drvPath.
{
  config,
  metaOwner,
  nixosAppHelpers,
  ...
}:
let
  flakeModules = config.flake.nixosModules;
  libvirtApp = nixosAppHelpers.getApp "libvirt";
in
{
  perSystem =
    { pkgs, ... }:
    let
      domain =
        name: id:
        pkgs.writeText "${name}.xml" ''
          <domain type="qemu">
            <name>${name}</name>
            <uuid>00000000-0000-4000-8000-00000000000${toString id}</uuid>
            <memory unit="MiB">64</memory>
            <os>
              <type arch="x86_64" machine="q35">hvm</type>
            </os>
            <devices>
              <channel type="unix">
                <target type="virtio" name="org.qemu.guest_agent.0"/>
              </channel>
            </devices>
          </domain>
        '';
      # Stands in for systemd-sleep, so the units run their hooks without sleeping.
      sleepStub.serviceConfig.ExecStart = [
        ""
        "${pkgs.coreutils}/bin/touch /run/slept"
      ];
    in
    {
      checks.workloads-vm-sleep = pkgs.testers.runNixOSTest {
        name = "workloads-vm-sleep";

        nodes.machine =
          { lib, ... }:
          {
            imports = [
              libvirtApp
              flakeModules."workloads-networks"
              flakeModules."workloads-vms"
            ];

            # networks.nix turns WARP on for warp networks; this test declares none.
            options.programs.cloudflare-warp.extended.enable = lib.mkEnableOption "WARP";

            config = {
              _module.args = {
                hostName = "machine";
                inherit metaOwner;
              };
              networking.nftables.enable = true;
              users.users.${metaOwner.username}.isNormalUser = true;
              programs.libvirt.extended.enable = true;
              systemd.services = {
                systemd-suspend = sleepStub;
                systemd-hibernate = sleepStub;
                # Lets a subtest hold back the wake unit.
                workloads-vm-wake.unitConfig.ConditionPathExists = "!/run/no-wake";
              };
            };
          };

        testScript = ''
          def state(name):
              return machine.succeed(f"virsh domstate {name}").strip()

          def states():
              return {name: state(name) for name in ["alpha", "beta"]}

          wake_description = "Resume and restore guests after host sleep"

          # Journal lines after now, from PID 1 or one unit.
          def journal_since():
              cursor = machine.succeed("journalctl -n1 --show-cursor").split("-- cursor: ")[-1].strip()
              return lambda match: f"journalctl -b -o cat {match} --after-cursor='{cursor}'"

          def wait_for_wake(since):
              machine.wait_until_succeeds(f"{since('_PID=1')} | grep -E '(Finished|Failed to start) {wake_description}'")
              return machine.succeed(since("_PID=1"))

          # Runs a sleep unit, then waits for the wake unit it queues. systemd
          # unloads the finished wake unit, so its own journal lines tell the order.
          def sleep_cycle(unit, succeeds=True):
              machine.succeed("rm -f /run/slept")
              since = journal_since()
              (machine.succeed if succeeds else machine.fail)(f"systemctl start {unit}")
              assert (machine.execute("test -e /run/slept")[0] == 0) == succeeds
              events = wait_for_wake(since)
              assert f"Finished {wake_description}" in events, events
              stopped = f"{unit}: " + ("Deactivated successfully" if succeeds else "Failed with result")
              assert events.index(stopped) < events.index(f"Starting {wake_description}"), events

          machine.wait_for_unit("libvirtd.service")
          machine.succeed(
              "virsh define ${domain "alpha" 1}",
              "virsh define ${domain "beta" 2}",
              "virsh start alpha",
              "virsh start --paused beta",
          )

          with subtest("suspend pauses running guests and the wake unit resumes only those"):
              sleep_cycle("systemd-suspend.service")
              assert states() == {"alpha": "running", "beta": "paused"}, states()
              # No agent runs in the guest, so the clock resync only warns.
              wake = machine.succeed("journalctl -b -o cat -u workloads-vm-wake.service")
              assert "resumed alpha" in wake and "beta" not in wake, wake
              assert "alpha keeps a stale clock" in wake, wake

          with subtest("hibernation managed-saves active guests and the wake unit restores them"):
              sleep_cycle("systemd-hibernate.service")
              assert states() == {"alpha": "running", "beta": "paused"}, states()
              hibernate = machine.succeed("journalctl -b -o cat -u systemd-hibernate.service")
              assert "saved alpha" in hibernate and "saved beta" in hibernate, hibernate

          with subtest("a sleep cycle that ends during a wake is brought back by that wake"):
              since = journal_since()
              machine.succeed("systemctl start systemd-suspend.service")
              # alpha's agent never connects, so the wake sits in its agent wait.
              machine.wait_until_succeeds(f"{since('-u workloads-vm-wake.service')} | grep -x 'resumed alpha'")
              machine.succeed("systemctl start systemd-hibernate.service")
              events = wait_for_wake(since)
              assert events.count(f"Starting {wake_description}") == 1, events
              assert f"Finished {wake_description}" in events, events
              assert states() == {"alpha": "running", "beta": "paused"}, states()
              woken = machine.succeed(since("-u workloads-vm-wake.service"))
              assert "restored alpha" in woken and "restored beta" in woken, woken

          with subtest("a guest paused for suspend, then saved for hibernation, comes back running"):
              machine.succeed("touch /run/no-wake")
              machine.succeed("systemctl start systemd-suspend.service", "systemctl start systemd-hibernate.service")
              assert states() == {"alpha": "shut off", "beta": "shut off"}, states()
              machine.succeed("rm /run/no-wake", "systemctl start workloads-vm-wake.service")
              assert states() == {"alpha": "running", "beta": "paused"}, states()

          with subtest("a failed save aborts hibernation and the guests saved before it come back"):
              # libvirt refuses to managed-save a transient domain.
              machine.succeed("virsh create ${domain "gamma" 3}")
              since = journal_since()
              sleep_cycle("systemd-hibernate.service", succeeds=False)
              hibernate = machine.succeed(since("-u systemd-hibernate.service"))
              assert "transient" in hibernate and "saved beta" in hibernate, hibernate
              assert states() == {"alpha": "running", "beta": "paused"}, states()
              assert state("gamma") == "running"
              # The VM has no graphical session to notify.
              wake = machine.succeed("journalctl -b -o cat -u workloads-vm-wake.service")
              assert "no notification sent" not in wake, wake
        '';
      };
    };
}
