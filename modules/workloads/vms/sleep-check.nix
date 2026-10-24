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
  sbxApp = nixosAppHelpers.getApp "sbx";
  owner = metaOwner.username;
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
      # A sandbox as sbx records it; the test script fills in its expiry.
      sandbox =
        emulator: name:
        pkgs.writeText "sbx-${name}.xml" ''
          <domain type="qemu">
            <name>sbx-${name}</name>
            <metadata>
              <sbx:sandbox xmlns:sbx="https://github.com/Bad3r/nixos/sbx">
                <sbx:base>nixos</sbx:base>
                <sbx:image>/nonexistent</sbx:image>
                <sbx:net>none</sbx:net>
                <sbx:created>0</sbx:created>
                <sbx:expires>@EXPIRES@</sbx:expires>
              </sbx:sandbox>
            </metadata>
            <memory unit="MiB">64</memory>
            <os>
              <type arch="x86_64" machine="q35">hvm</type>
            </os>
            <devices>
              <emulator>${emulator}</emulator>
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
          { config, lib, ... }:
          {
            imports = [
              libvirtApp
              sbxApp
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
              users.users.${owner} = {
                isNormalUser = true;
                uid = 1000;
                # Keeps the user manager, and so sbx-libvirt, running without a login.
                linger = true;
              };
              programs.libvirt.extended.enable = true;
              programs.sbx.extended = {
                enable = true;
                package = pkgs.callPackage ../../../packages/sbx { };
                limits = {
                  running = 3;
                  memory = 1;
                  sliceMemory = 2;
                  cpus = "0";
                  ttl = 1;
                  maxTtl = 24;
                  disk = 1;
                  minFree = 1;
                };
                sandbox = {
                  memory = 256;
                  maxMemory = 512;
                };
              };
              # Room above sbx's 1G free-space floor for the session save images.
              virtualisation.diskSize = 3072;
              # What the sbx Home Manager part declares.
              systemd.user.services.sbx-libvirt = {
                description = "libvirt session daemon for sbx sandboxes";
                serviceConfig = {
                  Type = "notify";
                  ExecStart = "${config.programs.libvirt.extended.package}/bin/virtqemud --timeout 600";
                  Slice = "sbx.slice";
                  KillMode = "process";
                };
              };
              systemd.services = {
                systemd-suspend = sleepStub;
                systemd-hibernate = sleepStub;
                # Lets a subtest hold back the wake unit.
                workloads-vm-wake.unitConfig.ConditionPathExists = "!/run/no-wake";
              };
            };
          };

        testScript =
          { nodes, ... }:
          let
            session = sandbox "${nodes.machine.programs.libvirt.extended.qemuPackage}/bin/qemu-system-x86_64";
          in
          ''
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

            with subtest("a guest that vanishes before its clock sync does not stop the wake"):
                machine.succeed("virsh create ${domain "delta" 4}")
                since = journal_since()
                machine.succeed("systemctl start systemd-suspend.service")
                # alpha's agent wait comes first, so delta is gone before its sync.
                machine.wait_until_succeeds(f"{since('-u workloads-vm-wake.service')} | grep -x 'resumed delta'")
                machine.succeed("virsh destroy delta")
                events = wait_for_wake(since)
                assert f"Finished {wake_description}" in events, events
                woken = machine.succeed(since("-u workloads-vm-wake.service"))
                assert "warning: delta keeps a stale clock" in woken, woken

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

            machine.succeed("virsh destroy gamma")

            def as_owner(command):
                return f"runuser -u ${owner} -- env XDG_RUNTIME_DIR=/run/user/1000 LIBVIRT_AUTOSTART=0 {command}"

            def sessions():
                names = machine.succeed(as_owner("virsh -c qemu:///session list --all --name")).split()
                return {
                    name.removeprefix("sbx-"): machine.succeed(as_owner(f"virsh -c qemu:///session domstate {name}")).strip()
                    for name in names
                }

            def define(name, ttl, *start):
                expires = int(machine.succeed("date +%s")) + ttl
                machine.succeed(
                    f"sed -e 's/@EXPIRES@/{expires}/' -e 's/sbx-x/sbx-{name}/' ${session "x"} > /run/sbx-{name}.xml",
                    as_owner(f"virsh -c qemu:///session define /run/sbx-{name}.xml"),
                    as_owner(f"virsh -c qemu:///session start {' '.join(start)} sbx-{name}"),
                )

            with subtest("the hook leaves a user without an active sbx daemon alone"):
                machine.wait_for_unit("user@1000.service")
                # Every cycle above ran `sbx sleep` as the owner.
                machine.succeed("journalctl -b -t runuser | grep -q 'session opened for user ${owner}'")
                machine.fail(as_owner("systemctl --user is-active sbx-libvirt.service"))
                machine.fail("pgrep -u ${owner} virtqemud")
                machine.fail("test -e /run/user/1000/sbx")

            with subtest("suspend pauses running sandboxes and the wake unit resumes only those"):
                machine.succeed(as_owner("systemctl --user start sbx-libvirt.service"))
                define("live", 7200)
                define("idle", 7200, "--paused")
                sleep_cycle("systemd-suspend.service")
                assert sessions() == {"live": "running", "idle": "paused"}, sessions()
                suspend = machine.succeed("journalctl -b -o cat -u systemd-suspend.service")
                assert "sandbox=live action=paused" in suspend and "idle" not in suspend, suspend
                wake = machine.succeed("journalctl -b -o cat -u workloads-vm-wake.service")
                assert "sandbox=live action=resumed" in wake, wake
                # No agent runs in the guest, so the clock resync only warns.
                assert "warning: live keeps a stale clock" in wake, wake

            with subtest("hibernation saves sandboxes within their TTL and the wake restores those"):
                define("old", -60)
                define("short", 600)
                machine.succeed("touch /run/no-wake")
                since = journal_since()
                machine.succeed("systemctl start systemd-hibernate.service")
                hibernate = machine.succeed(since("-u systemd-hibernate.service"))
                assert "sandbox=old action=destroyed" in hibernate, hibernate
                assert sessions() == {"live": "shut off", "idle": "shut off", "short": "shut off"}, sessions()
                saves = machine.succeed(as_owner("virsh -c qemu:///session list --all --with-managed-save --name"))
                assert len(saves.split()) == 3, saves
                # short outlives its TTL across the sleep.
                machine.succeed("date -s @$(( $(date +%s) + 3600 ))")
                machine.succeed("rm /run/no-wake", "systemctl start workloads-vm-wake.service")
                assert sessions() == {"live": "running", "idle": "paused"}, sessions()
                wake = machine.succeed(since("-u workloads-vm-wake.service"))
                for line in ("sandbox=live action=restored", "sandbox=idle action=restored", "sandbox=short action=destroyed"):
                    assert line in wake, wake
                machine.fail("test -e /run/user/1000/sbx/saved")

            with subtest("sandboxes that would breach the free-space floor abort hibernation"):
                avail = int(machine.succeed("df --output=avail -B1 /home/${owner} | tail -1"))
                # Above the 1G floor, below it plus the two 64M save images.
                machine.succeed(f"fallocate -l {avail - (1 << 30) - (100 << 20)} /home/${owner}/fill")
                since = journal_since()
                sleep_cycle("systemd-hibernate.service", succeeds=False)
                hibernate = machine.succeed(since("-u systemd-hibernate.service"))
                assert "keeps a 1G floor" in hibernate and "sandboxes of ${owner} not saved" in hibernate, hibernate
                machine.succeed("rm /home/${owner}/fill")
                assert sessions() == {"live": "running", "idle": "paused"}, sessions()
                assert states() == {"alpha": "running", "beta": "paused"}, states()
          '';
      };
    };
}
