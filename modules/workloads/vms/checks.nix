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
        adhoc = "00000000-0000-4000-8000-0000000000ad";
        sbx = "00000000-0000-4000-8000-0000000000bb";
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
      changedAlpha = lib.recursiveUpdate alpha { memory = 192; };
      seedLink = "/var/lib/workloads/images/seed.qcow2";
      lateLink = "/var/lib/workloads/images/late.qcow2";
      oldLink = "/var/lib/workloads/images/old.qcow2";

      stateDir = name: "/var/lib/workloads/guests/${uuids.${name}}";

      # Session guests on the sessionAttach network: busybox in an initrd,
      # with the NIC sbx renders. The probe reports each reachability check.
      owner = metaOwner.username;
      home = "/home/${owner}";
      sbxPackage = pkgs.callPackage ../../../packages/sbx { };
      sbxPython = "${pkgs.python3.interpreter} -I";
      busybox = pkgs.pkgsStatic.busybox;
      sessionKernel = pkgs.linuxPackages.kernel;
      # Decompressed in load order, so the static busybox insmod loads them.
      sessionModules =
        pkgs.runCommand "workloads-vms-test-modules"
          {
            nativeBuildInputs = [
              pkgs.kmod
              pkgs.xz
            ];
          }
          ''
            mkdir "$out"
            for module in virtio_pci virtio_net af_packet; do
              modprobe --show-depends -d ${sessionKernel.modules} -S ${sessionKernel.modDirVersion} "$module"
            done | awk '$1 == "insmod" && !seen[$2]++ { print $2 }' | while read -r path; do
              name=$(basename "$path" .xz)
              xz -dc "$path" > "$out/$name"
              echo "$name" >> "$out/order"
            done
          '';
      udhcpcScript = pkgs.writeScript "udhcpc-script" ''
        #!${busybox}/bin/sh
        case "$1" in
          bound)
            ip addr add "$ip/$mask" dev "$interface"
            ip link set "$interface" mtu "''${mtu:-1500}"
            ip route add default via "$router"
            echo "SBX lease ip=$ip router=$router dns=$dns mtu=$mtu"
            ;;
        esac
      '';
      # Sends three frames of one ethertype; busybox has no raw sender.
      # Store references would pull glibc into the guest's small initrd.
      sendFrame =
        pkgs.runCommandCC "sendframe"
          {
            buildInputs = [ pkgs.glibc.static ];
            nativeBuildInputs = [ pkgs.nukeReferences ];
            allowedReferences = [ ];
          }
          ''
            cp ${pkgs.writeText "sendframe.c" ''
              #include <linux/if_packet.h>
              #include <net/if.h>
              #include <stdio.h>
              #include <stdlib.h>
              #include <string.h>
              #include <sys/socket.h>

              static int mac(const char *text, unsigned char *out) {
                return sscanf(text, "%hhx:%hhx:%hhx:%hhx:%hhx:%hhx",
                              &out[0], &out[1], &out[2], &out[3], &out[4], &out[5]) == 6;
              }

              int main(int argc, char **argv) {
                unsigned char frame[64] = {0};
                struct sockaddr_ll to = {0};
                if (argc != 5 || !mac(argv[3], frame) || !mac(argv[2], frame + 6)) return 2;
                unsigned long type = strtoul(argv[4], NULL, 16);
                frame[12] = type >> 8;
                frame[13] = type & 0xff;
                int sock = socket(AF_PACKET, SOCK_RAW, 0);
                to.sll_family = AF_PACKET;
                to.sll_ifindex = if_nametoindex(argv[1]);
                to.sll_halen = 6;
                memcpy(to.sll_addr, frame, 6);
                for (int i = 0; i < 3; i++)
                  if (sendto(sock, frame, sizeof frame, 0, (struct sockaddr *)&to, sizeof to) < 0) return 1;
                return 0;
              }
            ''} sendframe.c
            $CC -static -O2 -o "$out" sendframe.c
            nuke-refs "$out"
          '';
      sessionInit = pkgs.writeScript "init" ''
        #!${busybox}/bin/sh
        export PATH=${busybox}/bin
        mkdir -p /proc /sys /dev
        mount -t proc proc /proc
        mount -t sysfs sysfs /sys
        mount -t devtmpfs devtmpfs /dev
        exec >/dev/ttyS0 2>&1
        while read -r module; do
          insmod ${sessionModules}/"$module"
        done < ${sessionModules}/order
        for arg in $(cat /proc/cmdline); do
          case "$arg" in
            sbx.role=*) role=''${arg#*=} ;;
            sbx.peer=*) peer=''${arg#*=} ;;
            sbx.host=*) host=''${arg#*=} ;;
          esac
        done
        ip link set lo up
        ip link set eth0 up
        udhcpc -i eth0 -n -q -t 30 -T 2 -O mtu -x "hostname:$role" -s ${udhcpcScript} || echo "SBX no lease"
        if [ "$role" = probe ]; then
          gateway=$(ip route | awk '/^default/ { print $3 }')
          check() { if "$@" >/dev/null 2>&1; then echo ok; else echo blocked; fi; }
          # The lease binding follows the DHCP ACK by a moment.
          for _ in 1 2 3 4 5 6 7 8 9 10; do ping -c 1 -W 1 "$gateway" >/dev/null 2>&1 && break; done
          echo "SBX gateway-ping=$(check ping -c 1 -W 3 "$gateway")"
          echo "SBX gateway-tcp=$(check nc -z -w 3 "$gateway" 53)"
          echo "SBX host-name=$(check nslookup -type=a host.vm "$gateway")"
          echo "SBX peer-name=$(check nslookup -type=a peer "$gateway")"
          echo "SBX gateway-http=$(check wget -q -T 3 -O /dev/null "http://$gateway:8080/")"
          echo "SBX host-http=$(check wget -q -T 3 -O /dev/null "http://$host:8080/")"
          echo "SBX peer-ping=$(check ping -c 2 -W 3 "$peer")"
          # The host counts UDP to port 4444 by source address.
          echo own | nc -u -w 1 "$gateway" 4444
          ip addr add "$peer/32" dev eth0
          arping -U -c 2 -I eth0 -s "$peer" "$gateway" >/dev/null 2>&1
          echo spoof | nc -u -w 1 -s "$peer" "$gateway" 4444
          ip addr del "$peer/32" dev eth0
          echo "SBX own-tcp=$(check nc -z -w 3 "$gateway" 53)"
          # The peer's MAC from this port: link-local, then ARP with the peer's leased pair.
          ${sendFrame} eth0 ${peerMac} 01:80:c2:00:00:0e 88cc
          ip link set eth0 down
          ip link set eth0 address ${peerMac}
          ip link set eth0 up
          ip addr add "$peer/32" dev eth0
          arping -U -c 2 -I eth0 -s "$peer" "$gateway" >/dev/null 2>&1
          echo "SBX done"
        fi
        while :; do sleep 3600; done
      '';
      sessionInitrd = pkgs.makeInitrd {
        contents = [
          {
            object = sessionInit;
            symlink = "/init";
          }
        ];
      };
      renderSessionDomain = pkgs.writeText "render-session-domain.py" ''
        import sys
        import xml.etree.ElementTree as ET

        sys.path.insert(0, "${sbxPackage}/lib/sbx")
        from sbx.core import bridge_interface

        name, mac, cmdline = sys.argv[1:]
        domain = ET.Element("domain", type="kvm")
        ET.SubElement(domain, "name").text = name
        ET.SubElement(domain, "memory", unit="MiB").text = "128"
        system = ET.SubElement(domain, "os")
        ET.SubElement(system, "type", arch="x86_64", machine="q35").text = "hvm"
        ET.SubElement(system, "kernel").text = "${sessionKernel}/bzImage"
        ET.SubElement(system, "initrd").text = "${sessionInitrd}/initrd"
        ET.SubElement(system, "cmdline").text = f"console=ttyS0 panic=-1 {cmdline}"
        # Without ACPI, q35's PCIe root ports leave the NIC powered off.
        features = ET.SubElement(domain, "features")
        ET.SubElement(features, "acpi")
        ET.SubElement(features, "apic")
        devices = ET.SubElement(domain, "devices")
        ET.SubElement(devices, "emulator").text = "${pkgs.qemu_kvm}/bin/qemu-system-x86_64"
        devices.append(bridge_interface("vn-sbx", mac))
        serial = ET.SubElement(devices, "serial", type="file")
        ET.SubElement(serial, "source", path=f"${home}/{name}.log")
        ET.SubElement(serial, "target", port="0")
        ET.SubElement(devices, "memballoon", model="none")
        print(ET.tostring(domain, encoding="unicode"))
      '';
      sessionDomain =
        name: mac: cmdline:
        pkgs.runCommand "workloads-vms-test-${name}.xml" { } ''
          ${sbxPython} ${renderSessionDomain} ${name} ${mac} "${cmdline}" > "$out"
        '';
      peerMac = "52:54:00:00:00:0b";
      probeMac = "52:54:00:00:00:0c";
      # sbx's own reader; it exits non-zero until the lease exists.
      leaseOf = pkgs.writeText "lease-of.py" ''
        import sys
        import time
        from pathlib import Path

        sys.path.insert(0, "${sbxPackage}/lib/sbx")
        from sbx.core import lease_address

        address = lease_address(Path("/var/lib/libvirt/dnsmasq/vn-sbx.status"), sys.argv[1], time.time())
        if address is None:
            sys.exit(1)
        print(address)
      '';
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
              # Open on every interface, so only the workload table keeps session guests out.
              networking.firewall.allowedTCPPorts = [ 8080 ];
              users.users.${owner} = {
                isNormalUser = true;
                uid = 1000;
                # The session daemon needs the user's runtime directory.
                linger = true;
              };

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
                  sbx = {
                    id = 6;
                    egress = "warp";
                    isolatePeers = true;
                    libvirt = {
                      enable = true;
                      uuid = uuids.sbx;
                      dhcp = {
                        start = 2;
                        end = 254;
                        leaseMinutes = 10;
                        clientNames = false;
                      };
                      sessionAttach = true;
                      bindLeases = true;
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
                guests = lib.mkDefault { inherit alpha gamma zeta; };
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
            peerDomain = sessionDomain "peer" peerMac "sbx.role=peer";
            probeDomain = sessionDomain "probe" probeMac "sbx.role=probe sbx.peer=@PEER@ sbx.host=@HOST@";
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

            with subtest("the host and the network's resolver answer declared names"):
                assert machine.succeed("getent hosts gamma.vm").split() == ["172.16.5.11", "gamma", "gamma.vm"]
                assert dig("host.vm") == "172.16.0.1"
                # The host takes the first interface, a network's resolver the one on that network.
                assert dig("gamma") == dig("gamma.vm") == "172.16.0.11"
                machine.fail("dig +time=1 +tries=1 @172.16.5.1 host.vm")
                report = json.loads(machine.succeed("workloads names --json"))
                assert [entry["name"] for entry in report["names"]] == ["alpha", "gamma"], report
                assert report["sandboxes"] is None, report

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

            def as_owner(command):
                return (
                    # No /run/wrappers on PATH: libvirt must name the setuid bridge helper itself.
                    "runuser -u ${owner} -- env HOME=${home} XDG_RUNTIME_DIR=/run/user/1000 PATH=/run/current-system/sw/bin "
                    + command
                )

            with subtest("session guests on a sessionAttach network reach only DHCP and DNS on the host"):
                machine.wait_for_unit("workloads-vm-net-sbx.service")
                machine.wait_for_unit("user@1000.service")
                machine.succeed("grep -Fx 'allow vn-sbx' /etc/qemu/bridge.conf")
                assert "expiry='10'" in machine.succeed("virsh net-dumpxml sbx")
                machine.succeed("systemd-run --unit=probe-http ${pkgs.python3.interpreter} -m http.server 8080")
                machine.wait_until_succeeds("curl -sf http://127.0.0.1:8080/ >/dev/null")

                machine.succeed(as_owner("virsh -c qemu:///session create ${peerDomain}"))
                try:
                    peer = machine.wait_until_succeeds(as_owner("${sbxPython} ${leaseOf} ${peerMac}"), timeout=90).strip()
                except Exception:
                    # The guest's console tells a failed boot from a missing lease.
                    print(machine.succeed("cat ${home}/peer.log"))
                    raise
                assert peer.startswith("172.16.6."), peer
                # The host reaches the peer, so only the bridge isolation can block the probe's ping.
                machine.wait_until_succeeds(f"ping -c 1 -W 1 {peer}", timeout=30)

                host = machine.succeed("ip -4 -o addr show dev eth1 | awk '{ print $4 }' | cut -d/ -f1").strip()
                machine.succeed(f"sed -e 's/@PEER@/{peer}/' -e 's/@HOST@/{host}/' ${probeDomain} > /run/probe.xml")
                machine.succeed(
                    "nft add table inet probe-count"
                    " && nft 'add chain inet probe-count pre { type filter hook prerouting priority -400; }'"
                    f" && nft add rule inet probe-count pre iifname vn-sbx udp dport 4444 ip saddr {peer} counter"
                    f" && nft add rule inet probe-count pre iifname vn-sbx udp dport 4444 ip saddr != {peer} counter"
                )
                machine.succeed(as_owner("virsh -c qemu:///session create /run/probe.xml"))
                machine.wait_until_succeeds("grep -F 'SBX done' ${home}/probe.log")
                report = machine.succeed("grep -F SBX ${home}/probe.log")
                print(report)
                assert "mtu=1240" in report, report
                for check in ("gateway-ping", "gateway-tcp", "host-name", "own-tcp"):
                    assert f"SBX {check}=ok" in report, report
                for check in ("peer-name", "gateway-http", "host-http", "peer-ping"):
                    assert f"SBX {check}=blocked" in report, report
                neighbor = machine.succeed(f"ip neigh show {peer} dev vn-sbx")
                assert "${peerMac}" in neighbor, neighbor
                rules = json.loads(machine.succeed("nft -j list chain inet probe-count pre"))["nftables"]
                spoofed, own = [
                    next(e["counter"]["packets"] for e in item["rule"]["expr"] if "counter" in e)
                    for item in rules
                    if "rule" in item
                ]
                assert (spoofed, own > 0) == (0, True), (spoofed, own)
                peer_tap = machine.succeed(as_owner("virsh -c qemu:///session domiflist peer")).split("\n")[2].split()[0]
                fdb = [
                    entry["ifname"]
                    for entry in json.loads(machine.succeed("bridge -j fdb show br vn-sbx"))
                    if entry["mac"] == "${peerMac}"
                ]
                assert fdb == [peer_tap], (fdb, peer_tap)
                assert machine.succeed("cat /sys/class/net/vn-sbx/bridge/no_linklocal_learn").strip() == "1"
          '';
      };
    };
}
