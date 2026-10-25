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
  workloadsApp = nixosAppHelpers.getApp "workloads";
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
        zeta = "00000000-0000-4000-8000-00000000000f";
        eta = "00000000-0000-4000-8000-000000000e1a";
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
        interfaces = {
          eth = {
            network = "lab";
            hostOffset = 11;
          };
          lan = {
            network = "default";
            hostOffset = 11;
          };
        };
      };
      delta = guest {
        uuid = uuids.delta;
        interfaces.eth.network = "lab";
        interfaces.eth.hostOffset = 12;
      };
      zeta = guest {
        uuid = uuids.zeta;
        disks.root = {
          size = 1;
          seed = "late";
        };
      };
      eta = guest {
        uuid = uuids.eta;
        install.media = [ "installer" ];
      };
      installerSource = "/srv/media/installer.iso";
      installerContent = "installer";
      changedAlpha = lib.recursiveUpdate alpha { memory = 192; };
      seedLink = "/var/lib/workloads/images/seed.qcow2";
      lateLink = "/var/lib/workloads/images/late.qcow2";
      oldLink = "/var/lib/workloads/images/old.qcow2";

      stateDir = name: "/var/lib/workloads/guests/${uuids.${name}}";
    in
    {
      checks.workloads-vms = pkgs.testers.runNixOSTest {
        name = "workloads-vms";

        nodes.machine =
          { lib, pkgs, ... }:
          {
            imports = [
              libvirtApp
              workloadsApp
              flakeModules."workloads-networks"
              flakeModules."workloads-vms"
              flakeModules."workloads-names"
              # workloads-names registers services too.
              flakeModules."workloads-services"
              (nixosAppHelpers.getApp "podman")
              (nixosAppHelpers.getApp "docker-compose")
            ];

            # Stands in for the WARP app that warp networks turn on.
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
              environment.systemPackages = [ pkgs.dnsutils ];
              programs.workloads.extended.package = pkgs.callPackage ../../../packages/workloads { };
              users.users.${metaOwner.username}.isNormalUser = true;

              systemd.tmpfiles.settings.workloads-vms-test.${seedLink}."L+".argument = "${seedImage}";

              workloads = {
                networks = {
                  default = {
                    id = 0;
                    egress = "warp";
                    resolve = lib.mkDefault [ "gamma" ];
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
                  outLink = seedLink;
                  expected = "${seedImage}";
                };
                # The test script links it, standing in for a late `nix build`.
                images.late = {
                  outLink = lateLink;
                  expected = "${seedImage}";
                };

                # Specialisations replace the whole set.
                # The test script writes the source, standing in for a manual download.
                media.installer = {
                  source = installerSource;
                  sha256 = builtins.hashString "sha256" installerContent;
                };

                guests = lib.mkDefault {
                  inherit
                    alpha
                    gamma
                    zeta
                    eta
                    ;
                };
              };

              specialisation = {
                changed.configuration.workloads.guests = {
                  alpha = changedAlpha;
                  inherit gamma delta;
                };
                renamed.configuration.workloads = {
                  guests = {
                    beta = changedAlpha;
                    inherit delta;
                  };
                  networks.default.resolve = [ "delta" ];
                };
                absent.configuration.workloads = {
                  guests = {
                    beta = changedAlpha // {
                      ensure = "absent";
                    };
                    inherit delta;
                  };
                  networks.default.resolve = [ "delta" ];
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
            import json
            import xml.etree.ElementTree as ET

            def journal(unit):
                return machine.succeed(f"journalctl -b -o cat -u {unit}")

            def warnings(unit):
                return machine.succeed(f"journalctl -b -o cat -p warning -u {unit}")

            # The scenarios restart one unit faster than its start limit allows.
            def restart(unit):
                return f"systemctl reset-failed {unit}; systemctl restart {unit}"

            def state(name):
                return machine.succeed(f"virsh domstate {name}").strip()

            def dig(name):
                return machine.succeed(f"dig +short @172.16.0.1 {name}").strip()

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

            with subtest("a seeded guest stays undefined until its image is built"):
                zeta_unit = "workloads-vm-guest-zeta.service"
                zeta_disk = "${stateDir "zeta"}/root.qcow2"
                machine.wait_for_unit(zeta_unit)
                assert machine.succeed(f"systemctl show -P SubState {zeta_unit}").strip() == "exited"
                assert "${lateLink} is missing; build it" in warnings(zeta_unit)
                machine.fail("virsh dominfo zeta")
                machine.fail("test -e ${stateDir "zeta"}")
                assert "zeta" not in journal("workloads-vm-orphans.service")
                machine.succeed("ln -s ${oldLink} ${lateLink}")
                machine.succeed(restart(zeta_unit))
                assert "${lateLink} is stale: it points at ${oldLink}" in warnings(zeta_unit)
                machine.fail("virsh dominfo zeta")
                machine.succeed("ln -sfn ${seedImage} ${lateLink}")
                machine.succeed(restart(zeta_unit))
                assert state("zeta") == "shut off"
                machine.succeed(f"test -f {zeta_disk}")
                # An existing disk never reads its seed.
                machine.succeed("ln -sfn ${oldLink} ${lateLink}")
                machine.succeed(restart(zeta_unit))
                # A defined guest that lost its NVRAM and disk fails instead of waiting.
                machine.succeed(f"mv {zeta_disk} {zeta_disk}.moved; rm ${stateDir "zeta"}/nvram.fd")
                machine.fail(restart(zeta_unit))
                assert "is defined, but its disk waits" in journal(zeta_unit)
                machine.succeed("virsh dominfo zeta")
                machine.succeed(f"mv {zeta_disk}.moved {zeta_disk}")
                machine.succeed(restart(zeta_unit))

            with subtest("a guest with install media stays undefined until they are staged"):
                eta_unit = "workloads-vm-guest-eta.service"
                media_unit = "workloads-vm-media.service"
                machine.wait_for_unit(eta_unit)
                assert machine.succeed(f"systemctl show -P SubState {media_unit}").strip() == "exited"
                assert "${installerSource} is missing, so 'installer' is not staged" in warnings(media_unit)
                assert "staged medium /var/lib/workloads/media/installer is missing" in warnings(eta_unit)
                machine.fail("virsh dominfo eta")
                machine.succeed("install -d -o ${metaOwner.username} /srv/media")
                # A present source with the wrong content fails instead of waiting.
                machine.succeed("su ${metaOwner.username} -c 'printf wrong > ${installerSource}'")
                machine.fail(restart(media_unit))
                assert "declared" in journal(media_unit)
                machine.fail("test -e /var/lib/workloads/media/installer")
                machine.succeed("su ${metaOwner.username} -c 'printf ${installerContent} > ${installerSource}'")
                machine.succeed(restart(media_unit))
                machine.succeed("test -f /var/lib/workloads/media/installer")
                machine.succeed(restart(eta_unit))
                assert state("eta") == "shut off"

            with subtest("the host and the network's resolver answer declared names"):
                assert machine.succeed("getent hosts gamma.vm").split() == ["172.16.5.11", "gamma", "gamma.vm"]
                assert dig("host.vm") == "172.16.0.1"
                # The host takes the first interface, a network's resolver the one on that network.
                assert dig("gamma") == dig("gamma.vm") == "172.16.0.11"
                machine.fail("dig +time=1 +tries=1 @172.16.5.1 host.vm")
                report = json.loads(machine.succeed("workloads names --json"))
                assert [entry["name"] for entry in report["names"]] == ["alpha", "gamma"], report
                assert report["sandboxes"] is None, report

            with subtest("a golden copy needs a shut-off guest and never replaces one"):
                golden_unit = "workloads-golden@alpha.service"
                golden = "/var/lib/workloads/golden/${uuids.alpha}"
                machine.succeed("virsh start alpha")
                machine.fail(f"systemctl start {golden_unit}")
                assert "is not shut off" in journal(golden_unit)
                machine.fail(f"test -e {golden}")
                machine.succeed("virsh destroy alpha")
                machine.succeed(restart(golden_unit))
                for item in ["root.qcow2", "nvram.fd", "tpm", "domain.xml"]:
                    machine.succeed(f"test -e {golden}/{item}")
                # A successful oneshot is unloaded, so there is no failed state to reset.
                machine.fail(f"systemctl start {golden_unit}")
                assert "exists; move it aside" in journal(golden_unit)

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
                assert "status: NXDOMAIN" in machine.succeed("dig @172.16.0.1 gamma.vm")
                assert dig("delta.vm") == "172.16.5.12"
                assert "older definition" not in journal("workloads-vm-net-default.service")
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
