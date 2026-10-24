# Needs /dev/kvm with nested virtualization, so CI only forces its drvPath.
{
  config,
  lib,
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
      uuids = {
        default = "00000000-0000-4000-8000-000000000001";
        lab = "00000000-0000-4000-8000-000000000002";
        alpha = "00000000-0000-4000-8000-00000000000a";
        gamma = "00000000-0000-4000-8000-00000000000c";
        delta = "00000000-0000-4000-8000-00000000000d";
        adhoc = "00000000-0000-4000-8000-0000000000ad";
      };

      seedImage = pkgs.runCommand "workloads-vms-test-seed.qcow2" { } ''
        ${pkgs.qemu-utils}/bin/qemu-img create -q -f qcow2 "$out" 64M
      '';

      unmarkedDomain =
        name: uuid:
        pkgs.writeText "${name}.xml" ''
          <domain type="qemu">
            <name>${name}</name>
            <uuid>${uuid}</uuid>
            <memory unit="MiB">64</memory>
            <os>
              <type arch="x86_64" machine="q35">hvm</type>
            </os>
          </domain>
        '';

      guest =
        attrs:
        {
          kind = "linux";
          trust = "untrusted";
          memory = 256;
          vcpus = 1;
          display = "headless";
          disks.root.size = 1;
        }
        // attrs;

      alpha = guest {
        uuid = uuids.alpha;
        firmware.tpm = true;
        interfaces.eth.network = "lab";
        interfaces.eth.hostOffset = 10;
      };
      gamma = guest {
        uuid = uuids.gamma;
        kind = "nixos";
        trust = "trusted";
        display = "spice";
        autostart = true;
        disks.root = {
          size = 1;
          seed = "seed";
        };
        interfaces.eth.network = "lab";
        interfaces.eth.hostOffset = 11;
      };
      delta = guest {
        uuid = uuids.delta;
        interfaces.eth.network = "lab";
        interfaces.eth.hostOffset = 12;
      };
      changedAlpha = lib.recursiveUpdate alpha { memory = 192; };

      stateDir = name: "/var/lib/workloads/guests/${uuids.${name}}";
    in
    {
      checks.workloads-vms = pkgs.testers.runNixOSTest {
        name = "workloads-vms";

        nodes.machine =
          { lib, ... }:
          {
            imports = [
              libvirtApp
              flakeModules."workloads-networks"
              flakeModules."workloads-vms"
            ];

            # networks.nix turns WARP on for warp networks; these use none.
            options.programs.cloudflare-warp.extended.enable = lib.mkEnableOption "WARP";

            config = {
              _module.args = {
                hostName = "machine";
                inherit metaOwner;
              };

              virtualisation = {
                cores = 2;
                memorySize = 2048;
              };
              networking.nftables.enable = true;
              users.users.${metaOwner.username}.isNormalUser = true;

              systemd.tmpfiles.settings.workloads-vms-test."/var/lib/workloads/images/seed.qcow2"."L+".argument =
                "${seedImage}";

              workloads = {
                networks = {
                  default = {
                    id = 0;
                    egress = "none";
                    libvirt = {
                      enable = true;
                      uuid = uuids.default;
                      dhcp = {
                        start = 100;
                        end = 200;
                      };
                    };
                  };
                  lab = {
                    id = 5;
                    egress = "none";
                    libvirt = {
                      enable = true;
                      uuid = uuids.lab;
                      dhcp = {
                        start = 100;
                        end = 200;
                      };
                    };
                  };
                };

                images.seed = {
                  path = "/var/lib/workloads/images/seed.qcow2";
                  expected = "${seedImage}";
                };

                # Specialisations replace the whole set.
                guests = lib.mkDefault { inherit alpha gamma; };
              };

              specialisation = {
                changed.configuration.workloads.guests = {
                  alpha = changedAlpha;
                  inherit gamma delta;
                };
                renamed.configuration.workloads.guests = {
                  beta = changedAlpha;
                  inherit delta;
                };
                absent.configuration.workloads.guests = {
                  beta = changedAlpha // {
                    ensure = "absent";
                  };
                  inherit delta;
                };
              };
            };
          };

        testScript =
          { nodes, ... }:
          let
            toplevel = nodes.machine.system.build.toplevel;
            switch = name: "${toplevel}/specialisation/${name}/bin/switch-to-configuration test";
          in
          ''
            import xml.etree.ElementTree as ET

            def journal(unit):
                return machine.succeed(f"journalctl -b -o cat -u {unit}")

            # The scenarios restart one unit faster than its start limit allows.
            def restart(unit):
                return f"systemctl reset-failed {unit}; systemctl restart {unit}"

            def state(name):
                return machine.succeed(f"virsh domstate {name}").strip()

            def memory(name, flags=""):
                root = ET.fromstring(machine.succeed(f"virsh dumpxml {flags} {name}"))
                return int(root.findtext("memory", ""))

            machine.wait_for_unit("multi-user.target")
            machine.succeed("test -c /dev/kvm")
            machine.succeed("virsh define ${unmarkedDomain "adhoc" uuids.adhoc}")
            adhoc = machine.succeed("virsh dumpxml --inactive adhoc")

            with subtest("the stock default network is taken over"):
                machine.wait_for_unit("workloads-vm-net-default.service")
                xml = machine.succeed("virsh net-dumpxml --inactive default")
                assert "${uuids.default}" in xml and "192.168.122.1" not in xml, xml

            with subtest("guests are defined with their files and only autostart guests run"):
                machine.wait_for_unit("workloads-vm-guest-alpha.service")
                machine.wait_for_unit("workloads-vm-guest-gamma.service")
                assert state("alpha") == "shut off"
                assert state("gamma") == "running"
                machine.succeed("virsh destroy gamma")
                gamma_nvram = "${stateDir "gamma"}/nvram.fd"
                # A first define that stopped before writing NVRAM resumes, start included.
                machine.succeed(f"rm {gamma_nvram}")
                machine.succeed(restart("workloads-vm-guest-gamma.service"))
                machine.succeed(f"test -f {gamma_nvram}")
                assert state("gamma") == "running"
                machine.succeed("virsh destroy gamma")
                # A domain lost by hand comes back without a second first start.
                machine.succeed("virsh undefine gamma --keep-nvram --keep-tpm")
                machine.succeed(restart("workloads-vm-guest-gamma.service"))
                assert state("gamma") == "shut off"
                alpha_dir = "${stateDir "alpha"}"
                machine.succeed(f"test -f {alpha_dir}/root.qcow2 -a -f {alpha_dir}/nvram.fd")
                assert machine.succeed(f"stat -c %a {alpha_dir}").strip() == "711"
                machine.succeed(
                    "qemu-img info ${stateDir "gamma"}/root.qcow2 | grep -F 'virtual size: 1 GiB'"
                )
                lab = machine.succeed("virsh net-dumpxml lab")
                assert "ip='172.16.5.10'" in lab and "ip='172.16.5.11'" in lab, lab

            with subtest("a running guest keeps its definition and running networks gain reservations"):
                machine.succeed("virsh start --paused alpha")
                machine.succeed("${switch "changed"}")
                assert "older definition" in journal("workloads-vm-guest-alpha.service")
                assert state("alpha") == "paused"
                assert memory("alpha") == 256 * 1024
                assert memory("alpha", "--inactive") == 192 * 1024
                lab = machine.succeed("virsh net-dumpxml lab")
                assert "ip='172.16.5.12'" in lab, lab
                assert "older definition" not in journal("workloads-vm-net-lab.service")

            with subtest("a rename waits until the guest is shut off"):
                machine.fail("${switch "renamed"}")
                assert "shut it down so it can be renamed to 'beta'" in journal(
                    "workloads-vm-guest-beta.service"
                )
                machine.succeed("virsh destroy alpha")
                machine.succeed(restart("workloads-vm-guest-beta.service"))
                assert "renamed domain 'alpha' to 'beta'" in journal("workloads-vm-guest-beta.service")
                assert machine.succeed("virsh domuuid beta").strip() == "${uuids.alpha}"
                machine.fail("virsh dominfo alpha")

            with subtest("undeclared owned objects are reported, unmarked ones ignored"):
                machine.succeed(restart("workloads-vm-orphans.service"))
                orphans = journal("workloads-vm-orphans.service")
                assert "guest 'gamma'" in orphans and "adhoc" not in orphans, orphans

            with subtest("a missing disk fails the guest"):
                beta_disk = f"{alpha_dir}/root.qcow2"
                machine.succeed(f"mv {beta_disk} {beta_disk}.moved")
                machine.fail(restart("workloads-vm-guest-beta.service"))
                assert "is missing" in journal("workloads-vm-guest-beta.service")
                machine.succeed(f"mv {beta_disk}.moved {beta_disk}")
                machine.succeed(restart("workloads-vm-guest-beta.service"))

            with subtest("an unmarked domain holding a declared UUID is refused"):
                machine.succeed("virsh undefine beta --keep-nvram --keep-tpm")
                machine.succeed("virsh define ${unmarkedDomain "intruder" uuids.alpha}")
                machine.fail(restart("workloads-vm-guest-beta.service"))
                assert "never takes over" in journal("workloads-vm-guest-beta.service")
                machine.succeed("virsh undefine intruder")
                # A guest with NVRAM never gets a fresh disk, even without its domain.
                machine.succeed(f"mv {beta_disk} {beta_disk}.moved")
                machine.fail(restart("workloads-vm-guest-beta.service"))
                assert journal("workloads-vm-guest-beta.service").count("is missing") == 2
                machine.fail(f"test -e {beta_disk}")
                machine.succeed(f"mv {beta_disk}.moved {beta_disk}")
                machine.succeed(restart("workloads-vm-guest-beta.service"))
                assert state("beta") == "shut off"

            with subtest("an absent guest is undefined and keeps its files"):
                machine.succeed("${switch "absent"}")
                machine.fail("virsh dominfo beta")
                machine.succeed(f"test -f {alpha_dir}/root.qcow2 -a -f {alpha_dir}/nvram.fd -a -d {alpha_dir}/tpm")
                assert "ip='172.16.5.10'" not in machine.succeed("virsh net-dumpxml lab")

            with subtest("the unmarked domain is untouched"):
                assert machine.succeed("virsh dumpxml --inactive adhoc") == adhoc
          '';
      };
    };
}
