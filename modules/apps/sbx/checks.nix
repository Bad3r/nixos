# Needs /dev/kvm with nested virtualization, so CI only forces its drvPath.
# On a busy host the nested guest's SMM firmware can hang before the boot loader, failing create.
#   nix build "path:.#checks.x86_64-linux.sbx-windows-base"
{ metaOwner, nixosAppHelpers, ... }:
let
  owner = metaOwner.username;
  uuid = "00000000-0000-4000-8000-0000000000b1";
  golden = "/var/lib/workloads/golden/${uuid}";
  bases = "/home/${owner}/.local/share/sbx/bases/win11";
in
{
  perSystem =
    { config, pkgs, ... }:
    let
      # Stands in for the Windows disk: an unsigned image boots, since the
      # stand-in NVRAM enrolls no keys and so leaves Secure Boot off.
      standIn = config.workloads.artifacts.sbx-nixos;
    in
    {
      checks.sbx-windows-base = pkgs.testers.runNixOSTest {
        name = "sbx-windows-base";

        nodes.machine =
          { config, ... }:
          let
            sbxCfg = config.programs.sbx.extended;
          in
          {
            imports = [
              (nixosAppHelpers.getApp "libvirt")
              (nixosAppHelpers.getApp "sbx")
            ];

            _module.args = {
              hostName = "machine";
              inherit metaOwner;
            };

            # sbx-qemu needs vsock network namespaces, which the latest kernel has.
            boot.kernelPackages = pkgs.linuxPackages_latest;
            virtualisation = {
              cores = 2;
              memorySize = 3072;
              # The golden copy and two exports of the stand-in image, above the floor.
              diskSize = 16384;
            };
            networking.nftables.enable = true;
            environment.systemPackages = [ pkgs.swtpm ];
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
                running = 1;
                memory = 1;
                sliceMemory = 2;
                cpus = "0-1";
                ttl = 1;
                maxTtl = 24;
                disk = 2;
                minFree = 1;
              };
              sandbox = {
                memory = 256;
                maxMemory = 768;
                windowsMemory = 768;
                disk = 1;
                maxFile = 1;
              };
              windowsBases.win11 = {
                inherit uuid;
                disk = "root";
              };
            };
            # What the sbx Home Manager part declares.
            systemd.user.services.sbx-libvirt = {
              description = "libvirt session daemon for sbx sandboxes";
              path = [ config.virtualisation.libvirtd.qemu.swtpm.package ];
              serviceConfig = {
                Type = "notify";
                ExecStart = "${config.programs.libvirt.extended.package}/bin/virtqemud --timeout 600";
                Slice = "sbx.slice";
                KillMode = "process";
                LimitFSIZE = "${toString sbxCfg.sandbox.maxFile}G";
              };
            };
          };

        testScript =
          { nodes, ... }:
          let
            ovmf = nodes.machine.virtualisation.libvirtd.qemu.firmwarePackages.ovmf-full;
          in
          ''
            import json
            import xml.etree.ElementTree as ET

            def as_owner(command):
                return f"runuser -u ${owner} -- env XDG_RUNTIME_DIR=/run/user/1000 LIBVIRT_AUTOSTART=0 {command}"

            def sbx(command):
                return json.loads(machine.succeed(as_owner(f"sbx --json {command}")))

            def export_log():
                return machine.succeed("journalctl -b -o cat -u sbx-base@win11.service")

            def versions():
                return machine.succeed("ls ${bases}").split()

            machine.wait_for_unit("multi-user.target")
            machine.wait_for_unit("user@1000.service")

            with subtest("the export names the golden copy it waits for"):
                machine.fail("systemctl start sbx-base@win11.service")
                assert "systemctl start workloads-golden@win11.service" in export_log()

            # The layout workloads-golden@ writes, from the stand-in image.
            machine.succeed(
                "install -d -m 0700 ${golden} /run/tpm",
                "cp ${standIn}/*.qcow2 ${golden}/root.qcow2",
                "install -m 0600 ${ovmf}/FV/OVMF_VARS.fd ${golden}/nvram.fd",
                "swtpm_setup --tpm2 --tpmstate /run/tpm --createek --config /dev/null",
                "cp -a /run/tpm ${golden}/tpm",
                "echo '<domain/>' > ${golden}/domain.xml",
            )

            with subtest("the owner gets a read-only copy, and only a changed golden copy repeats"):
                machine.succeed("systemctl start sbx-base@win11.service")
                [first] = versions()
                export = f"${bases}/{first}"
                assert machine.succeed(f"stat -c '%U %a' {export}/disk.qcow2 {export}/nvram.fd").split() == ["${owner}", "400"] * 2
                machine.succeed(f"test -s {export}/tpm/tpm2-00.permall")
                machine.fail(f"test -e {export}/domain.xml")
                assert machine.succeed("stat -c '%U %a' ${golden}").split() == ["root", "700"]
                machine.succeed("systemctl start sbx-base@win11.service")
                assert "nothing to export" in export_log()
                assert versions() == [first]
                machine.succeed("sleep 1; touch ${golden}/nvram.fd; systemctl start sbx-base@win11.service")
                assert len(versions()) == 2
                assert sbx("base list")[-1]["path"] == f"${bases}/{versions()[-1]}"

            with subtest("a Windows sandbox boots the newest export in the session daemon"):
                created = sbx("create win11 --name w --ttl 30m")
                assert created["cid"] is None, created
                info = sbx("info w")
                assert info["image"] == f"${bases}/{versions()[-1]}/disk.qcow2", info
                xml = machine.succeed(as_owner("virsh -c qemu:///session dumpxml sbx-w"))
                root = ET.fromstring(xml)
                # libvirt names the firmware by its /run/libvirt/nix-ovmf link.
                assert root.findtext("os/loader[@secure='yes']", "").endswith("/FV/OVMF_CODE.fd"), xml
                assert root.find(f"devices/tpm/backend/source[@path='{info['directory']}/tpm']") is not None, xml
                assert root.find("devices/vsock") is None and root.find("devices/interface") is None, xml
                assert root.findtext("devices/emulator", "").endswith("sbx-qemu"), xml
                qemu = machine.succeed("pgrep -o -f 'guest=sbx-w'").strip()
                namespaces = machine.succeed(f"readlink /proc/{qemu}/ns/net /proc/1/ns/net").split()
                assert namespaces[0] != namespaces[1], namespaces
                machine.succeed(as_owner("pgrep -u ${owner} swtpm"))
                result = sbx("exec w -- /run/current-system/sw/bin/uname -s")
                assert result["exit_code"] == 0 and result["stdout"] == "Linux\n", result

            with subtest("gc keeps the export a sandbox uses and prunes the rest"):
                machine.succeed("sleep 1; touch ${golden}/nvram.fd; systemctl start sbx-base@win11.service")
                older, used, newest = versions()
                pruned = sbx("gc")
                assert pruned == [{"name": f"win11/{older}", "reason": "superseded export"}], pruned
                assert versions() == [used, newest]

            with subtest("the file size limit stops an overlay that outgrows it"):
                virtual = json.loads(machine.succeed(f"qemu-img info --output=json ${bases}/{used}/disk.qcow2"))["virtual-size"]
                seek = virtual // (1 << 20) - 1100
                machine.fail(as_owner(f"sbx exec w --timeout 10m -- /run/current-system/sw/bin/dd if=/dev/zero of=/dev/vda bs=1M seek={seek} count=1100 oflag=direct"))
                # The write past the limit fails with EFBIG, and the disk's error policy pauses the guest.
                machine.wait_until_succeeds(as_owner("virsh -c qemu:///session domstate --reason sbx-w | grep -F 'paused (I/O error)'"))
                size = int(machine.succeed(f"stat -c %s {info['directory']}/disk.qcow2"))
                assert size <= 1 << 30, size

            with subtest("destroy removes the sandbox, and gc then its export"):
                sbx("destroy w")
                machine.fail(f"test -e {info['directory']}")
                sbx("gc")
                assert versions() == [newest]
          '';
      };
    };
}
