# The SN720 volume vault76: LUKS2 over XFS, mounted at /srv/vault76.
# It has no snapshots and no second copy, so a deleted file is gone.
{ metaOwner, ... }:
let
  uuid = "6746bf2b-3e77-405b-a74f-77baa6686ac3";
  mountPoint = "/srv/vault76";
  # The auto-lock default; `vault76 unlock --timeout` overrides it until the next lock.
  autolockMinutes = 90;
  vaultFileSystem = {
    device = "/dev/mapper/vault76";
    fsType = "xfs";
    options = [
      "noatime"
      "discard"
      "noauto"
      "nofail"
      "x-systemd.device-timeout=60s"
    ];
  };

  vaultModule =
    {
      config,
      lib,
      options,
      pkgs,
      ...
    }:
    let
      cli = pkgs.writeShellApplication {
        name = "vault76";
        # notify-send comes from the auto-lock unit's path.
        runtimeInputs = [
          config.systemd.package
          pkgs.coreutils
          pkgs.cryptsetup
          pkgs.gawk
          pkgs.gnused
          pkgs.procps
          pkgs.psmisc
          pkgs.util-linux
        ];
        runtimeEnv = {
          VAULT76_UUID = uuid;
          VAULT76_DEFAULT_TIMEOUT = toString (autolockMinutes * 60);
          VAULT76_OWNER = metaOwner.username;
        };
        text = builtins.readFile ./_vault76.sh;
      };
    in
    {
      # Opens on demand only: noauto here and on the mount keeps it out of
      # cryptsetup.target and local-fs.target. Starting srv-vault76.mount pulls
      # in systemd-cryptsetup@vault76.service, which unlocks through an enrolled
      # YubiKey (FIDO2 PIN and touch) and asks for the passphrase when no
      # enrolled key shows up within token-timeout (30 s by default).
      environment.etc."crypttab".text = ''
        vault76 UUID=${uuid} none luks,discard,noauto,nofail,fido2-device=auto,timeout=120s,x-systemd.device-timeout=60s
      '';

      # discard trims a deleted file's blocks at once instead of at the weekly
      # fstrim, at the cost of slower deletes.
      fileSystems.${mountPoint} = vaultFileSystem;

      environment.systemPackages = [ cli ];

      # Every mount brings the auto-lock along, whatever started it. It counts
      # reads and writes on /dev/mapper/vault76, warns the owner's desktop a
      # minute ahead, and closes the volume once it is unmounted.
      systemd.services.vault76-autolock = {
        description = "Lock vault76 when its drive sees no reads or writes";
        wantedBy = [ "srv-vault76.mount" ];
        after = [ "srv-vault76.mount" ];
        path = [ pkgs.libnotify ];
        serviceConfig = {
          ExecStart = "${lib.getExe cli} autolock-daemon";
          # A dead loop would leave the volume open with nothing watching it.
          Restart = "on-failure";
          RestartSec = "10s";
        };
      };

      # The nightly updatedb would write every file name on the volume to the
      # locate database on root.
      services.locate.prunePaths = options.services.locate.prunePaths.default ++ [ mountPoint ];
    };
in
{
  configurations.nixos.songbird.module = vaultModule;

  # Needs /dev/kvm, so CI only forces its drvPath. Runs the module on a LUKS2
  # volume with the real UUID, opened by a keyfile in place of the YubiKeys.
  perSystem =
    { lib, pkgs, ... }:
    let
      # Records each call; with -A it answers as /tmp/notify-click says, or
      # waits like an unanswered notification.
      notifyStub = pkgs.writeShellScriptBin "notify-send" ''
        printf 'uid=%s bus=%s %s\n' "$(id -u)" "$DBUS_SESSION_BUS_ADDRESS" "$*" >>/tmp/notify.log
        for arg in "$@"; do
          if [ "$arg" = -A ]; then
            if [ -e /tmp/notify-click ]; then
              exec cat /tmp/notify-click
            fi
            exec sleep infinity
          fi
        done
      '';
    in
    {
      checks."songbird/vault76" = pkgs.testers.runNixOSTest {
        name = "songbird-vault76";

        nodes.machine = {
          imports = [ vaultModule ];
          environment.etc."crypttab".text = lib.mkForce ''
            vault76 UUID=${uuid} /etc/vault76-test.key luks,discard,noauto,nofail
          '';
          environment.systemPackages = [
            pkgs.cryptsetup
            pkgs.xfsprogs
          ];
          boot.supportedFilesystems = [ "xfs" ];
          virtualisation.emptyDiskImages = [ 512 ];
          # The test VM's own file systems replace fileSystems.
          virtualisation.fileSystems.${mountPoint} = vaultFileSystem;
          users.users.${metaOwner.username} = {
            isNormalUser = true;
            uid = 1000;
            # A user manager, and so the session bus, without a login.
            linger = true;
          };
          systemd.services.vault76-autolock.path = lib.mkBefore [ notifyStub ];
          # Holds each lock's stop job open after the mapping is gone, the window
          # in which a mount start gets canceled.
          systemd.services."systemd-cryptsetup@vault76" = {
            overrideStrategy = "asDropin";
            serviceConfig.ExecStopPost = "${pkgs.coreutils}/bin/sleep 5";
          };
        };

        testScript = ''
          import time

          uuid = "${uuid}"

          def locked():
              return machine.execute("test -e /dev/mapper/vault76")[0] != 0

          def notes():
              return machine.succeed("cat /tmp/notify.log 2>/dev/null || true")

          def reset_notes():
              machine.succeed("rm -f /tmp/notify.log /tmp/notify-click")

          def wait_locked(timeout):
              machine.wait_until_succeeds("! test -e /dev/mapper/vault76", timeout=timeout)

          def make_volume():
              machine.succeed(
                  "head -c 64 /dev/urandom > /etc/vault76-test.key",
                      f"cryptsetup luksFormat -q --type luks2 --pbkdf pbkdf2 --pbkdf-force-iterations 1000 --uuid {uuid} --key-file /etc/vault76-test.key /dev/vdb",
                  "cryptsetup open --key-file /etc/vault76-test.key /dev/vdb prep",
                  "mkfs.xfs -q /dev/mapper/prep",
                  "cryptsetup close prep",
                  "udevadm settle",
              )
              machine.wait_for_file(f"/dev/disk/by-uuid/{uuid}")

          key_opens = "cryptsetup open --test-passphrase --key-file /etc/vault76-test.key /dev/vdb"

          machine.wait_for_unit("multi-user.target")
          machine.wait_for_file("/run/user/1000/bus")
          make_volume()

          with subtest("arguments"):
              assert "vault76 is locked" in machine.succeed("vault76 status")
              for bad in ["", "unlock --timeout=1m", "unlock --timeout=90", "unlock --timeout=abc", "lock --timeout=1h", "--timeout=1h", "status --force", "unlock lock", "unlock --bogus", "--unlock", "extra"]:
                  machine.fail(f"vault76 {bad}")
              rc, out = machine.execute("setpriv --reuid=1000 --regid=100 --clear-groups vault76 unlock 2>&1")
              assert rc != 0 and "run it as root" in out, out

          with subtest("an idle volume locks a minute after the warning"):
              reset_notes()
              t0 = time.monotonic()
              out = machine.succeed("vault76 unlock --timeout=2m")
              assert "auto-lock: after 2m" in out, out
              machine.succeed("systemctl is-active vault76-autolock.service")
              machine.wait_until_succeeds("grep -qs 'locks in 1 minute' /tmp/notify.log", timeout=150)
              t_warn = time.monotonic() - t0
              assert not locked()
              wait_locked(120)
              t_lock = time.monotonic() - t0
              print(f"warning after {t_warn:.0f} s, lock after {t_lock:.0f} s")
              assert t_warn >= 55 and t_lock >= t_warn + 55, (t_warn, t_lock)
              machine.wait_until_succeeds("grep -qs 'vault76 locked' /tmp/notify.log", timeout=30)
              log = notes()
              assert "uid=1000 bus=unix:path=/run/user/1000/bus" in log, log
              machine.wait_until_fails("systemctl is-active vault76-autolock.service")
              machine.succeed("test ! -e /run/vault76/timeout")

          with subtest("a read after the warning keeps it unlocked"):
              machine.succeed("vault76 unlock --timeout=2m")
              machine.succeed("dd if=/dev/urandom of=/srv/vault76/f bs=1M count=4 conv=fsync")
              reset_notes()
              # XFS keeps writing its log for a while after a write, which
              # delays the warning past the 60 s of a clean mount.
              stat = "cat /sys/block/$(basename $(readlink -f /dev/mapper/vault76))/stat"
              t0 = time.monotonic()
              samples = []
              while machine.execute("grep -qs 'locks in 1 minute' /tmp/notify.log")[0] != 0:
                  fields = machine.succeed(stat).split()
                  samples.append((round(time.monotonic() - t0), fields[0], fields[4]))
                  assert time.monotonic() - t0 < 300, samples
                  time.sleep(5)
              print(f"warning {time.monotonic() - t0:.0f} s after the write; (s, reads, writes): {samples}")
              machine.succeed("sync && echo 3 > /proc/sys/vm/drop_caches && cat /srv/vault76/f > /dev/null")
              machine.wait_until_succeeds("grep -qs 'stays unlocked.*read or written' /tmp/notify.log", timeout=30)
              time.sleep(70)
              assert not locked()

          with subtest("Keep unlocked restarts the clock"):
              reset_notes()
              machine.succeed("echo default > /tmp/notify-click")
              # The previous subtest's warning may already be out; start over.
              machine.succeed("vault76 unlock --timeout=2m")
              machine.wait_until_succeeds("grep -qs 'stays unlocked.*locks after 2m' /tmp/notify.log", timeout=200)
              time.sleep(70)
              assert not locked()

          with subtest("--timeout=off holds it open, a new timeout locks it"):
              reset_notes()
              assert "auto-lock: off" in machine.succeed("vault76 unlock --timeout=off")
              stat = "cat /sys/block/$(basename $(readlink -f /dev/mapper/vault76))/stat"
              before = machine.succeed(stat).split()
              time.sleep(150)
              after = machine.succeed(stat).split()
              # No background reads or writes on an idle volume (fields 1 and 5).
              assert (before[0], before[4]) == (after[0], after[4]), (before, after)
              assert not locked()
              assert "locks in 1 minute" not in notes(), notes()
              machine.succeed("vault76 unlock --timeout=2m")
              wait_locked(200)

          with subtest("unlock right after the auto-lock waits for it"):
              # The mapping is gone, but systemd-cryptsetup's stop still runs.
              assert machine.succeed("systemctl show -P ActiveState systemd-cryptsetup@vault76.service").strip() == "deactivating"
              machine.succeed("vault76 unlock")
              machine.succeed("vault76 lock")

          with subtest("a busy volume stays unlocked until released"):
              reset_notes()
              machine.succeed("vault76 unlock --timeout=2m")
              machine.succeed("systemd-run --unit=holder --property=WorkingDirectory=/srv/vault76 sleep infinity")
              machine.wait_until_succeeds("tr '\\0' ' ' < /proc/$(systemctl show -P MainPID holder)/cmdline | grep -q '/sleep infinity'", timeout=10)
              rc, out = machine.execute("vault76 lock 2>&1")
              assert rc != 0 and "sleep" in out, out
              machine.wait_until_succeeds("grep -qs 'In use by: sleep' /tmp/notify.log", timeout=200)
              assert not locked()
              machine.succeed("systemctl stop holder")
              wait_locked(30)

          with subtest("a killed auto-lock comes back and still locks"):
              machine.succeed("vault76 unlock --timeout=2m")
              machine.wait_for_unit("vault76-autolock.service")
              machine.succeed("systemctl kill --signal=KILL vault76-autolock.service")
              machine.wait_until_succeeds("systemctl show -P NRestarts vault76-autolock.service | grep -qx 1", timeout=30)
              machine.wait_for_unit("vault76-autolock.service")
              wait_locked(200)

          with subtest("stopping the mount alone closes the volume"):
              machine.succeed("vault76 unlock")
              machine.succeed("systemctl stop srv-vault76.mount")
              wait_locked(30)
              assert "vault76 is locked" in machine.succeed("vault76 status")

          with subtest("manual unlock and lock"):
              assert "after 1h30m" in machine.succeed("vault76 unlock")
              assert "vault76 is locked" in machine.succeed("vault76 lock")
              assert locked()
              machine.wait_until_fails("systemctl is-active vault76-autolock.service")

          with subtest("a mount started through systemctl brings the auto-lock"):
              machine.succeed("systemctl start srv-vault76.mount")
              machine.wait_for_unit("vault76-autolock.service")
              machine.succeed("vault76 lock")
              assert locked()

          with subtest("wipe asks on a terminal and erases nothing unconfirmed"):
              rc, out = machine.execute("vault76 wipe < /dev/null 2>&1")
              assert rc != 0 and "--force" in out, out
              rc, out = machine.execute("echo nope | script -qec 'vault76 wipe' /dev/null")
              assert rc != 0 and "Type vault76" in out and "nothing was erased" in out, out
              machine.succeed(key_opens)

          with subtest("wipe refuses while the volume is in use"):
              machine.succeed("vault76 unlock")
              machine.succeed("systemd-run --unit=holder2 --property=WorkingDirectory=/srv/vault76 sleep infinity")
              machine.wait_until_succeeds("tr '\\0' ' ' < /proc/$(systemctl show -P MainPID holder2)/cmdline | grep -q '/sleep infinity'", timeout=10)
              rc, out = machine.execute("vault76 wipe --force 2>&1")
              assert rc != 0 and "sleep" in out, out
              machine.succeed(key_opens)
              assert not locked()
              machine.succeed("systemctl stop holder2")

          with subtest("a confirmed wipe locks, erases the key slots and zero-fills"):
              out = machine.succeed("echo vault76 | script -qec 'vault76 wipe' /dev/null")
              assert "erasing 1 key slots" in out and "vault76 is erased" in out, out
              assert locked()
              machine.fail(key_opens)
              # Neither header copy nor any data is left.
              machine.succeed("cmp -n 536870912 /dev/vdb /dev/zero")

          with subtest("wipe --force erases without asking"):
              make_volume()
              machine.succeed("vault76 unlock")
              out = machine.succeed("vault76 wipe --force < /dev/null")
              assert "vault76 is erased" in out, out
              assert locked()
              machine.fail(key_opens)
        '';
      };
    };
}
