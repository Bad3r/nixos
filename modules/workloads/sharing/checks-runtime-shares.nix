# NixOS VM test for runtime shares: `workloads share` hot-plugs a declared share
# into a NixOS system guest through workload-grantd and a sandbox's shared
# directory and a declared share into an sbx sandbox. Needs /dev/kvm with nested virtualization, so CI
# only forces its drvPath; run it with
#   nix build "path:.#checks.x86_64-linux.workloads-runtime-shares"
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
  inherit (nixosAppHelpers) getApp;
  owner = metaOwner.username;
  home = "/home/${owner}";
in
{
  perSystem =
    {
      config,
      pkgs,
      system,
      ...
    }:
    let
      base = config.workloads.artifacts.sbx-nixos;

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
    in
    {
      checks.workloads-runtime-shares = pkgs.testers.runNixOSTest {
        name = "workloads-runtime-shares";

        nodes.machine =
          { config, ... }:
          let
            image = guestImage config.workloads.guests.epsilon.mounts;
          in
          {
            imports = [
              (getApp "libvirt")
              (getApp "sbx")
              (getApp "workloads")
              flakeModules."workloads-networks"
              flakeModules."workloads-vms"
              flakeModules."workloads-sharing"
            ];

            # networks.nix turns WARP on for warp networks; none are declared here.
            options.programs.cloudflare-warp.extended.enable = lib.mkEnableOption "WARP";

            config = {
              _module.args = {
                hostName = "machine";
                inherit metaOwner;
              };

              # The latest kernel has the vsock namespaces sbx-qemu requires.
              boot.kernelPackages = pkgs.linuxPackages_latest;
              virtualisation = {
                cores = 2;
                memorySize = 4096;
                diskSize = 8192;
                additionalPaths = [ base ];
              };
              users.users = {
                ${owner} = {
                  isNormalUser = true;
                  uid = 1000;
                  # Keeps the user manager, and so sbx-libvirt, running without a login.
                  linger = true;
                };
                eve.isNormalUser = true;
              };
              networking.nftables.enable = true;
              system.stateVersion = lib.trivial.release;

              programs = {
                libvirt.extended.enable = true;
                workloads.extended.package = pkgs.callPackage ../../../packages/workloads { };
                sbx.extended = {
                  enable = true;
                  package = pkgs.callPackage ../../../packages/sbx { };
                  limits = {
                    running = 1;
                    memory = 1;
                    sliceMemory = 2;
                    cpus = "0-1";
                    ttl = 1;
                    maxTtl = 24;
                    disk = 20;
                    minFree = 1;
                  };
                  sandbox = {
                    memory = 1024;
                    maxMemory = 1024;
                    disk = 1;
                  };
                };
              };
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

              systemd.tmpfiles.settings.workloads-runtime-shares-test = {
                "/var/lib/workloads/images/epsilon"."L+".argument = "${image}";
                "/srv/rw".d.user = owner;
                "/srv/late".d.user = owner;
                "/srv/more".d.user = owner;
                "/srv/docs".d.user = owner;
                "/srv/docs/hello"."f+" = {
                  user = owner;
                  argument = "hello";
                };
              };

              workloads = {
                images.epsilon.expected = "${image}/${image.passthru.filePath}";
                guests.epsilon = {
                  uuid = "00000000-0000-4000-8000-00000000000f";
                  kind = "nixos";
                  trust = "trusted";
                  memory = 768;
                  vcpus = 1;
                  display = "headless";
                  autostart = true;
                  disks.root = {
                    size = 8;
                    seed = "epsilon";
                  };
                  shares = {
                    rw.hostPath = "/srv/rw";
                    late = {
                      hostPath = "/srv/late";
                      runtime = true;
                    };
                    more = {
                      hostPath = "/srv/more";
                      readOnly = true;
                      runtime = true;
                    };
                  };
                };
                grants.sandboxShares.docs.hostPath = "/srv/docs";
              };
            };
          };

        testScript =
          { nodes, ... }:
          let
            firmware = "${nodes.machine.programs.libvirt.extended.qemuPackage}/share/qemu/firmware";
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
                """Run a shell script in the system guest; return its exit code and output."""
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

            def as_owner(command):
                return f"runuser -u ${owner} -- env XDG_RUNTIME_DIR=/run/user/1000 TMPDIR=${home}/tmp {command}"

            def workloads(command):
                return json.loads(machine.succeed(as_owner(f"workloads --json {command}")))

            def refused(command, code):
                answer = json.loads(machine.fail(as_owner(f"workloads --json {command}")))
                assert answer["error"]["code"] == code, (command, answer)

            def sbx(command):
                return json.loads(machine.succeed(as_owner(f"sbx --json {command}")))

            def in_sandbox(script):
                # sbx exec exits with the guest command's status.
                _, out = machine.execute(as_owner(f"sbx --json exec s -- sh -c {shlex.quote(script)}"))
                result = json.loads(out)
                return result["exit_code"], result["stdout"] + result["stderr"]

            def session_xml():
                return machine.succeed(as_owner("virsh -c qemu:///session dumpxml sbx-s"))

            daemons = "pgrep -c -u ${owner} -x virtiofsd"

            machine.wait_for_unit("workloads-vm-guest-epsilon.service")
            machine.wait_for_unit("workload-grantd.socket")
            machine.wait_for_unit("user@1000.service")
            wait_for_guest()

            with subtest("a declared runtime share attaches to a running guest"):
                booted = int(machine.succeed(daemons))
                answer = workloads("share attach epsilon late")
                assert answer["share"] == {
                    "target": "guest:epsilon",
                    "tag": "late",
                    "read_only": False,
                    "attached": True,
                    "mount_point": "/mnt/late",
                }, answer
                assert "/srv/late" in machine.succeed("virsh dumpxml epsilon")
                guest_succeed("mount /mnt/late && echo guest > /mnt/late/from-guest")
                assert machine.succeed("stat -c %U /srv/late/from-guest").strip() == "${owner}"
                assert workloads("share attach epsilon more")["share"]["read_only"] is True
                code, out = guest("mount /mnt/more && touch /mnt/more/x")
                assert code != 0 and "Read-only" in out, out
                entries = machine.succeed("journalctl -t workload-grant -o json --no-pager")
                decisions = [json.loads(line) for line in entries.splitlines()]
                assert any(
                    entry.get("WORKLOAD_GRANT_DECISION") == "attached"
                    and entry.get("WORKLOAD_GRANT_CALLER_UID") == "1000"
                    for entry in decisions
                ), entries

            with subtest("the helper refuses what no runtime share declares"):
                refused("share attach epsilon late", "already-attached")
                refused("share attach epsilon rw", "not-declared")
                refused("share attach epsilon nope", "not-declared")
                refused("share attach ghost late", "not-declared")
                answer = json.loads(machine.fail("runuser -u eve -- workloads --json share attach epsilon rw"))
                assert answer["error"]["code"] == "os-error", answer

            with subtest("an attached share survives a managed save"):
                machine.succeed("virsh managedsave epsilon")
                refused("share detach epsilon late", "saved")
                machine.succeed("virsh start epsilon")
                wait_for_guest()
                assert guest_succeed("cat /mnt/late/from-guest").strip() == "guest"

            with subtest("detach removes the device and its virtiofsd"):
                guest_succeed("umount /mnt/late /mnt/more")
                for tag in ("late", "more"):
                    assert workloads(f"share detach epsilon {tag}")["share"]["attached"] is False
                xml = machine.succeed("virsh dumpxml epsilon")
                assert "/srv/late" not in xml and "/srv/more" not in xml, xml
                machine.wait_until_succeeds(f"test $({daemons}) -eq {booted}")
                refused("share detach epsilon late", "not-attached")

            machine.succeed(as_owner(
                "sh -c 'mkdir -p ${home}/tmp ${home}/.config/qemu/firmware ${home}/.local/share/sbx/bases"
                " && ln -s ${firmware}/50-edk2-x86_64-secure.json ${firmware}/60-edk2-x86_64.json ${home}/.config/qemu/firmware/"
                " && ln -s ${base} ${home}/.local/share/sbx/bases/nixos'"
            ))
            machine.succeed("modprobe -a vhost_vsock")
            sbx("create nixos --name s --ttl 30m")
            shared = "${home}/.local/share/sbx/s/shared"

            with subtest("a sandbox takes its shared directory read-write"):
                answer = workloads("share attach sbx-s shared")
                assert answer["share"] == {
                    "target": "sbx-s",
                    "tag": "shared",
                    "read_only": False,
                    "attached": True,
                    "host_path": shared,
                }, answer
                code, out = in_sandbox("mkdir -p /mnt/shared && mount -t virtiofs shared /mnt/shared && echo guest > /mnt/shared/from-guest")
                assert code == 0, out

            with subtest("every guest user writes as the owner"):
                code, out = in_sandbox(
                    "setpriv --reuid=1000 --regid=100 --clear-groups"
                    " sh -c 'mkdir -p /mnt/shared/d/e && echo user > /mnt/shared/d/e/f'"
                    " && mkdir /mnt/shared/closed && touch /mnt/shared/closed/x"
                    " && chown 4242:4242 /mnt/shared/closed/x && chmod 0 /mnt/shared/closed"
                )
                assert code == 0, out
                owners = machine.succeed(f"find {shared} -printf '%u:%g\\n' | sort -u").split()
                assert owners == ["${owner}:users"], owners

            with subtest("a declared sandbox share is read-only even remounted"):
                assert workloads("share attach sbx-s docs")["share"]["read_only"] is True
                code, out = in_sandbox("mkdir -p /mnt/docs && mount -t virtiofs docs /mnt/docs && cat /mnt/docs/hello")
                assert (code, out.strip()) == (0, "hello"), out
                code, out = in_sandbox("mount -o remount,rw /mnt/docs && touch /mnt/docs/x")
                assert code != 0, out
                machine.fail("test -e /srv/docs/x")

            with subtest("a sandbox gets no other host directory"):
                refused("share attach sbx-s /srv/docs", "not-declared")
                refused("share attach sbx-s ${home}", "not-declared")
                refused("share attach sbx-s shared", "already-attached")
                refused("share attach sbx-s xfer", "not-declared")

            with subtest("sandbox shares survive a managed save"):
                machine.succeed(as_owner("sbx sleep save"))
                machine.succeed(as_owner("sbx sleep restore"))
                code, out = in_sandbox("cat /mnt/shared/from-guest /mnt/docs/hello")
                assert (code, out.split()) == (0, ["guest", "hello"]), out

            with subtest("detach removes the sandbox shares, and destroy their files"):
                in_sandbox("umount /mnt/shared /mnt/docs")
                for tag in ("shared", "docs"):
                    assert workloads(f"share detach sbx-s {tag}")["share"]["attached"] is False
                    refused(f"share detach sbx-s {tag}", "not-attached")
                assert "<filesystem" not in session_xml()
                sbx("destroy s")
                machine.fail("test -e ${home}/.local/share/sbx/s")
          '';
      };
    };
}
