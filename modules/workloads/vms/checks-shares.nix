# The VM test boots a NixOS guest under nested KVM, so CI only forces its drvPath.
{
  config,
  inputs,
  lib,
  metaOwner,
  nixosAppHelpers,
  ...
}:
let
  flakeModules = config.flake.nixosModules;
  libvirtApp = nixosAppHelpers.getApp "libvirt";
  owner = metaOwner.username;

  hostModule =
    { lib, ... }:
    {
      imports = [
        libvirtApp
        flakeModules."workloads-networks"
        flakeModules."workloads-vms"
      ];

      # networks.nix turns WARP on for warp networks; none are declared here.
      options.programs.cloudflare-warp.extended.enable = lib.mkEnableOption "WARP";

      config = {
        _module.args = {
          hostName = "machine";
          inherit metaOwner;
        };
        networking.nftables.enable = true;
        users.users.${owner}.isNormalUser = true;
        system.stateVersion = lib.trivial.release;
      };
    };

  guest =
    attrs:
    {
      uuid = "00000000-0000-4000-8000-00000000000e";
      kind = "nixos";
      trust = "trusted";
      memory = 768;
      vcpus = 1;
      display = "headless";
      shares.rw.hostPath = "/srv/rw";
    }
    // attrs;

  windowsGuest =
    attrs:
    guest (
      {
        kind = "windows";
        memory = 4096;
        firmware = {
          secureBoot = true;
          enrolledKeys = true;
          tpm = true;
        };
        disks.root.size = 64;
        interfaces.lan = {
          network = "lan";
          hostOffset = 11;
        };
        windows.account.name = owner;
      }
      // attrs
    );
in
{
  perSystem =
    { pkgs, system, ... }:
    let
      guestImage =
        mounts:
        (inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            flakeModules."workloads-guest-base"
            {
              _module.args = {
                hostName = "epsilon";
                inherit metaOwner;
              };
              workloads.guest.shares = mounts;
              documentation.enable = false;
              boot.loader.timeout = 0;
              system.stateVersion = lib.trivial.release;
            }
          ];
        }).config.system.build.images.qemu-efi;

      # Assertion messages from the workloads.guests prefix only: the bare
      # evaluation also trips the boot loader and root file system checks.
      evaluate =
        guests:
        (inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            hostModule
            {
              # Windows guests name a password secret and need a network.
              options.sops = {
                secrets = lib.mkOption {
                  type = lib.types.attrsOf lib.types.attrs;
                  default = { };
                };
                useSystemdActivation = lib.mkOption { default = false; };
              };
              config = {
                users.users.staff = {
                  isNormalUser = true;
                  group = "root";
                };
                sops.secrets."workloads/win/password" = { };
                workloads = {
                  networks.lan = {
                    id = 1;
                    egress = "none";
                    libvirt = {
                      enable = true;
                      uuid = "00000000-0000-4000-8000-0000000000a1";
                      dhcp = {
                        start = 100;
                        end = 200;
                      };
                    };
                  };
                  inherit guests;
                };
              };
            }
          ];
        }).config;

      shareFailures =
        guests:
        map (assertion: assertion.message) (
          lib.filter (
            assertion: !assertion.assertion && lib.hasPrefix "workloads.guests." assertion.message
          ) (evaluate guests).assertions
        );

      assertionCases = [
        {
          name = "an untrusted guest with a share";
          guests.lab = guest { trust = "untrusted"; };
          expected = [ "workloads.guests.lab: untrusted guests get no shares" ];
        }
        {
          name = "a share owned by root";
          guests.lab = guest {
            shares.rw = {
              hostPath = "/srv/rw";
              owner = "root";
            };
          };
          expected = [ "workloads.guests.lab: shares.rw: the owner and its primary group must not be root" ];
        }
        {
          name = "a share owned by a user whose primary group is root";
          guests.lab = guest {
            shares.rw = {
              hostPath = "/srv/rw";
              owner = "staff";
            };
          };
          expected = [ "workloads.guests.lab: shares.rw: the owner and its primary group must not be root" ];
        }
        {
          name = "a share owned by an undeclared user";
          guests.lab = guest {
            shares.rw = {
              hostPath = "/srv/rw";
              owner = "nobody-here";
            };
          };
          expected = [ "workloads.guests.lab: shares.rw: owner nobody-here is not a declared user" ];
        }
        {
          name = "an untrusted guest with its share disabled";
          guests.lab = guest {
            trust = "untrusted";
            shares.rw = {
              enable = false;
              hostPath = "/srv/rw";
            };
          };
          expected = [ ];
        }
        {
          name = "a Windows guest with two shares on one drive letter";
          guests.win = windowsGuest {
            shares = {
              a = {
                hostPath = "/srv/a";
                driveLetter = "Y";
              };
              b = {
                hostPath = "/srv/b";
                driveLetter = "Y";
              };
            };
          };
          expected = [ "workloads.guests.win: shares: two shares take the same driveLetter" ];
        }
        {
          name = "a Windows guest with 21 shares";
          guests.win = windowsGuest {
            shares = lib.genAttrs (map (i: "s${toString i}") (lib.range 1 21)) (tag: {
              hostPath = "/srv/${tag}";
            });
          };
          expected = [
            "workloads.guests.win: shares: a Windows guest mounts at most 20 shares, on G to Z, a drop included unless shares.drop.enable = false"
          ];
        }
        {
          name = "a Windows guest serving two shares through VirtioFsSvc";
          guests.win = windowsGuest {
            windows.virtiofs.mode = "service";
            shares = {
              a.hostPath = "/srv/a";
              b.hostPath = "/srv/b";
            };
          };
          expected = [
            "workloads.guests.win: windows.virtiofs.mode = \"service\" mounts one share, attached at boot, a drop included unless shares.drop.enable = false"
          ];
        }
        {
          name = "a Windows guest serving a runtime share through VirtioFsSvc";
          guests.win = windowsGuest {
            windows.virtiofs.mode = "service";
            shares.a = {
              hostPath = "/srv/a";
              runtime = true;
            };
          };
          expected = [
            "workloads.guests.win: windows.virtiofs.mode = \"service\" mounts one share, attached at boot, a drop included unless shares.drop.enable = false"
          ];
        }
        {
          name = "a tag longer than 36 characters";
          guests.lab = guest { shares.${lib.fixedWidthString 37 "a" ""}.hostPath = "/srv/rw"; };
          expected = [
            "workloads.guests.lab: shares.${lib.fixedWidthString 37 "a" ""}: tags must match [a-z0-9][a-z0-9-]* and have at most 36 characters"
          ];
        }
      ];

      driveLetters =
        (evaluate {
          win = windowsGuest {
            shares = {
              a.hostPath = "/srv/a";
              b = {
                hostPath = "/srv/b";
                driveLetter = "Z";
              };
              c = {
                hostPath = "/srv/c";
                runtime = true;
              };
              d = {
                enable = false;
                hostPath = "/srv/d";
              };
            };
          };
        }).workloads.guests.win.windows.virtiofs.driveLetters;

      assertionMismatches =
        lib.optional (
          driveLetters != {
            a = "Y";
            b = "Z";
            c = "X";
          }
        ) "drive letters: got ${builtins.toJSON driveLetters}"
        ++ lib.concatMap (
          case:
          let
            got = shareFailures case.guests;
          in
          lib.optional (got != case.expected) "${case.name}: got ${builtins.toJSON got}"
        ) assertionCases;
    in
    {
      # Thrown at evaluation, since CI forces drvPaths without building checks.
      checks.workloads-vms-share-assertions =
        if assertionMismatches != [ ] then
          throw "workloads-vms-share-assertions: ${lib.concatStringsSep "; " assertionMismatches}"
        else
          pkgs.runCommandLocal "workloads-vms-share-assertions" { } ''
            echo "ok: ${toString (lib.length assertionCases)} cases" > $out
          '';

      checks.workloads-vms-shares = pkgs.testers.runNixOSTest {
        name = "workloads-vms-shares";

        nodes.machine =
          { config, ... }:
          let
            image = guestImage config.workloads.guests.epsilon.mounts;
          in
          {
            imports = [ hostModule ];

            virtualisation = {
              cores = 2;
              memorySize = 3072;
              diskSize = 8192;
            };

            systemd.tmpfiles.settings.workloads-vms-shares-test = {
              "/var/lib/workloads/images/epsilon"."L+".argument = "${image}";
              "/srv/rw".d = {
                user = owner;
                mode = "0777";
              };
              "/srv/ro".d.user = owner;
              "/srv/ro/hello"."f+" = {
                user = owner;
                argument = "hello";
              };
              "/srv/late".d.user = owner;
              "/srv/late/note"."f+" = {
                user = owner;
                argument = "late";
              };
            };

            workloads = {
              images.epsilon.expected = "${image}/${image.passthru.filePath}";

              guests.epsilon = guest {
                autostart = true;
                disks.root = {
                  size = 8;
                  seed = "epsilon";
                };
                shares = {
                  rw.hostPath = "/srv/rw";
                  ro = {
                    hostPath = "/srv/ro";
                    readOnly = true;
                  };
                  late = {
                    hostPath = "/srv/late";
                    readOnly = true;
                    runtime = true;
                  };
                };
              };
            };
          };

        testScript =
          let
            lateXml = "/etc/workloads/shares/epsilon/late.xml";
          in
          ''
            import base64
            import json
            import shlex
            import time

            def agent(command):
                out = machine.succeed(
                    f"virsh qemu-agent-command epsilon {shlex.quote(json.dumps(command))}"
                )
                return json.loads(out)["return"]

            def guest(script):
                """Run a shell script in the guest; return its exit code and output."""
                pid = agent({
                    "execute": "guest-exec",
                    "arguments": {
                        "path": "/run/current-system/sw/bin/sh",
                        "arg": ["-c", f"PATH=/run/current-system/sw/bin; {script}"],
                        "capture-output": True,
                    },
                })["pid"]
                while True:
                    status = agent({"execute": "guest-exec-status", "arguments": {"pid": pid}})
                    if status["exited"]:
                        out = base64.b64decode(status.get("out-data", "")).decode()
                        err = base64.b64decode(status.get("err-data", "")).decode()
                        return status["exitcode"], out + err
                    time.sleep(0.5)

            def guest_succeed(script):
                code, out = guest(script)
                assert code == 0, f"{script}: exit {code}: {out}"
                return out

            def wait_for_guest():
                machine.wait_until_succeeds(
                    "virsh qemu-agent-command epsilon '{\"execute\":\"guest-ping\"}'", timeout=600
                )
                for _ in range(120):
                    if guest("findmnt /mnt/rw && findmnt /mnt/ro")[0] == 0:
                        return
                    time.sleep(1)
                raise AssertionError(guest("systemctl status mnt-rw.mount mnt-ro.mount")[1])

            daemons = "pgrep -c -u ${owner} -x virtiofsd"

            def as_owner(command):
                machine.succeed(f"runuser -u ${owner} -- sh -c {shlex.quote(command)}")

            def owner_of(path):
                return machine.succeed(f"stat -c %U {path}").strip()

            machine.wait_for_unit("workloads-vm-guest-epsilon.service")
            xml = machine.succeed("virsh dumpxml epsilon")
            assert "<source type='memfd'/>" in xml and "/srv/late" not in xml, xml

            with subtest("shares mount at boot and virtiofsd runs as the owner"):
                wait_for_guest()
                machine.fail("pgrep -u root -x virtiofsd")
                booted = int(machine.succeed(daemons))
                assert guest_succeed("findmnt -no FSTYPE /mnt/rw").strip() == "virtiofs"

            with subtest("guest writes land owned by the share owner"):
                as_owner("echo host > /srv/rw/from-host")
                assert guest_succeed("cat /mnt/rw/from-host").strip() == "host"
                guest_succeed("echo guest > /mnt/rw/from-root")
                assert owner_of("/srv/rw/from-root") == "${owner}"
                guest_succeed("runuser -u ${owner} -- touch /mnt/rw/from-owner")
                # Only the owner's uid and gid are mapped into virtiofsd's user namespace.
                for ids in ["--reuid=4242 --regid=0", "--reuid=0 --regid=4242"]:
                    code, out = guest(f"setpriv {ids} --clear-groups touch /mnt/rw/other")
                    assert code != 0 and "Invalid argument" in out, f"{ids}: {out}"
                for name in machine.succeed("ls /srv/rw").split():
                    assert owner_of(f"/srv/rw/{name}") == "${owner}", name

            with subtest("a read-only share refuses writes even when remounted rw"):
                assert guest_succeed("cat /mnt/ro/hello").strip() == "hello"
                assert guest("touch /mnt/ro/x")[0] != 0
                guest_succeed("mount -o remount,rw /mnt/ro")
                code, out = guest("touch /mnt/ro/x")
                assert code != 0 and "Read-only" in out, out
                machine.fail("test -e /srv/ro/x")

            with subtest("a runtime share attaches live"):
                machine.succeed("virsh attach-device epsilon ${lateXml} --live")
                guest_succeed("mount /mnt/late")
                assert guest_succeed("cat /mnt/late/note").strip() == "late"

            with subtest("managed save and restore keep the shares working"):
                machine.succeed("virsh managedsave epsilon")
                assert machine.succeed("virsh domstate epsilon").strip() == "shut off"
                machine.succeed("virsh dominfo epsilon | grep -E 'Managed save: +yes'")
                as_owner("echo saved > /srv/rw/while-saved")
                machine.succeed("virsh start epsilon")
                wait_for_guest()
                assert guest_succeed("cat /mnt/rw/while-saved").strip() == "saved"
                guest_succeed("echo restored > /mnt/rw/after-restore")
                assert owner_of("/srv/rw/after-restore") == "${owner}"
                assert guest_succeed("cat /mnt/late/note").strip() == "late"
                guest_succeed("umount /mnt/late")
                machine.succeed("virsh detach-device epsilon ${lateXml} --live")
                machine.wait_until_succeeds(f"test $({daemons}) -eq {booted}")
          '';
      };
    };
}
