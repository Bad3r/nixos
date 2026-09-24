{ inputs, ... }:
let
  body =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.host.virtualization.windowsGuest;
      nixvirt = inputs.nixvirt.lib;
      uri = "qemu:///system";
      name = "RDPWindows";
      vcpus = 4;

      # Identity. libvirt keys guest state on these, so a change strands it: the
      # domain UUID names the swtpm state directory, nvramPath holds the UEFI
      # variable store, and a volume name NixVirt cannot find is created empty.
      # The network UUID is identity too: NixVirt undefines by UUID and destroys
      # every domain on a network it replaces, so a change powers the guest off.
      domainUuid = "d40dd3b2-a6ad-4136-89d8-120cb5d3c098";
      winappsNetworkUuid = "44d27dc5-b0b5-4673-9c6b-2cceb995b733";
      defaultNetworkUuid = "84712988-20f5-4ffa-b6a2-acb45df49078";
      poolUuid = "7355d2f6-f1ff-4057-b6c8-a72475c936d4";
      nvramPath = "/var/lib/libvirt/qemu/nvram/${name}_VARS.fd";
      poolName = "winapps";
      poolPath = "/var/lib/libvirt/winapps";
      volumeName = "${name}.qcow2";

      # NixVirt appends the MAC it derives from the domain UUID to the first
      # interface even when one is set. This is that value, so both elements
      # agree and the DHCP reservation holds.
      guestMac = "52:54:00:93:d8:09";

      # Outside the sources modules/hosts/common/firewall.nix trusts, Docker's
      # default address pools, and the CGNAT range the mesh and tailnet use.
      networkName = "winapps";
      bridge = "virbr-winapps";
      hostAddress = "172.16.213.1";
      guestAddress = "172.16.213.10";

      winappsNetwork = {
        name = networkName;
        uuid = winappsNetworkUuid;
        forward.mode = "nat";
        bridge.name = bridge;
        ip = {
          address = hostAddress;
          netmask = "255.255.255.0";
          # No range: dnsmasq serves the reservation only, so a guest with
          # another MAC gets no address instead of a wrong one.
          dhcp.host = {
            mac = guestMac;
            ip = guestAddress;
          };
        };
      };

      defaultNetwork = nixvirt.network.templates.bridge {
        uuid = defaultNetworkUuid;
        subnet_byte = 122;
      };

      pool = {
        type = "dir";
        name = poolName;
        uuid = poolUuid;
        target.path = poolPath;
      };

      # NixVirt creates the volume when the name is missing and never touches an
      # existing one. `present = false` is the one setting that deletes it.
      volume = {
        name = volumeName;
        capacity = {
          count = 64;
          unit = "GiB";
        };
        allocation = {
          count = 0;
          unit = "bytes";
        };
        target.format.type = "qcow2";
      };

      template = nixvirt.domain.templates.windows {
        inherit name;
        uuid = domainUuid;
        vcpu.count = vcpus;
        memory = {
          count = 8;
          unit = "GiB";
        };
        storage_vol = {
          pool = poolName;
          volume = volumeName;
        };
        virtio_drive = true;
        # QXL: the virtio GL form needs a render node qemu-libvirtd cannot open.
        virtio_video = false;
        nvram_path = nvramPath;
        install_vol = cfg.installIso;
        install_virtio = cfg.installIso != null;
      };

      domain = template // {
        os = template.os // {
          # OVMFFull is built with SMM_REQUIRE: secure plus smm keep the UEFI
          # variable store writable from SMM only.
          loader = template.os.loader // {
            secure = true;
          };
        };
        features = template.features // {
          smm.state = true;
        };
        # libvirt maps vCPUs to sockets without a topology, and Windows client
        # editions use two sockets at most.
        cpu = template.cpu // {
          topology = {
            sockets = 1;
            dies = 1;
            cores = vcpus;
            threads = 1;
          };
        };
        # hypervclock alone keeps an idle Windows guest from polling the
        # emulated timers.
        clock = {
          offset = "localtime";
          timer = [
            {
              name = "rtc";
              present = false;
              tickpolicy = "catchup";
            }
            {
              name = "pit";
              present = false;
              tickpolicy = "delay";
            }
            {
              name = "hpet";
              present = false;
            }
            {
              name = "kvmclock";
              present = false;
            }
            {
              name = "hypervclock";
              present = true;
            }
          ];
        };
        devices = template.devices // {
          # nixpkgs' libvirtd-config keeps this link pointed at
          # libvirtd.qemu.package; the template's value is NixVirt's own qemu.
          emulator = "/run/libvirt/nix-emulators/qemu-system-x86_64";
          interface = {
            type = "network";
            mac.address = guestMac;
            source.network = networkName;
            model.type = "virtio";
          };
          # Replaces the template's list, which also carries a SPICE WebDAV
          # folder-sharing channel.
          channel = [
            {
              type = "spicevmc";
              target = {
                type = "virtio";
                name = "com.redhat.spice.0";
              };
            }
            {
              type = "unix";
              target = {
                type = "virtio";
                name = "org.qemu.guest_agent.0";
              };
            }
          ];
          # Console through the libvirt connection only; the template's QXL form
          # listens on an unauthenticated loopback TCP port.
          graphics = template.devices.graphics // {
            listen.type = "none";
          };
        };
      };

      virsh = "${config.virtualisation.libvirtd.package}/bin/virsh";
    in
    {
      imports = [ inputs.nixvirt.nixosModules.default ];

      options.host.virtualization.windowsGuest = {
        enable = lib.mkEnableOption "the NixVirt-declared Windows guest that WinApps presents over RDP";

        name = lib.mkOption {
          type = lib.types.str;
          default = name;
          readOnly = true;
          description = "libvirt domain name of the guest.";
        };

        network.guestAddress = lib.mkOption {
          type = lib.types.str;
          default = guestAddress;
          readOnly = true;
          description = "IPv4 address the guest network reserves for the guest.";
        };

        installIso = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "/var/lib/libvirt/winapps/windows.iso";
          description = ''
            Windows installation ISO, readable by the qemu-libvirtd user. A value attaches it together
            with the virtio-win driver ISO; null leaves the drive empty. A change applies at the next
            guest start.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        host.virtualization.libvirt.enable = true;

        virtualisation = {
          libvirt = {
            enable = true;
            # NixVirt's default comes from its own nixpkgs instance.
            package = pkgs.libvirt;
            swtpm.enable = true;
            # The lists are exhaustive: NixVirt powers off and undefines every
            # object on the connection that is not declared here.
            # restart = false throughout: definitions embed store paths that move
            # with nixpkgs, and NixVirt's default powers an object off on any
            # change. A change applies at the object's next start.
            connections.${uri} = {
              networks = [
                {
                  definition = nixvirt.network.writeXML winappsNetwork;
                  active = true;
                  restart = false;
                }
                # For ad-hoc virt-manager guests; started on demand so no idle
                # bridge sits inside the range the host firewall trusts.
                {
                  definition = nixvirt.network.writeXML defaultNetwork;
                  active = null;
                  restart = false;
                }
              ];
              pools = [
                {
                  definition = nixvirt.pool.writeXML pool;
                  active = true;
                  restart = false;
                  volumes = [ { definition = nixvirt.volume.writeXML volume; } ];
                }
              ];
              # active = null: started on demand, never by NixVirt.
              domains = [
                {
                  definition = nixvirt.domain.writeXML domain;
                  active = null;
                  restart = false;
                }
              ];
            };
          };

          # The nixpkgs defaults resume every guest at boot and write guest RAM
          # to disk at host shutdown.
          libvirtd = {
            onBoot = "ignore";
            onShutdown = "shutdown";
          };
        };

        # NixVirt starts the pool without building it, so the target has to exist.
        systemd.tmpfiles.settings."10-windows-guest".${poolPath}.d = {
          user = "root";
          group = "root";
          mode = "0711";
        };

        # Head of the chain: nixos-fw accepts the open ports and LAN sources
        # before anything appended here. NEW only, so replies to host-initiated
        # connections still reach the ESTABLISHED rule. The chain is rebuilt on
        # every firewall start, which is the cleanup. Only the refuse rule takes
        # both families: DHCPv4 and the network's dnsmasq listener are IPv4 only,
        # so the accepts follow it in reverse order at position 1 each, landing
        # ahead of it on IPv4, while IPv6 gets only the refuse, at the head.
        networking.firewall.extraCommands = ''
          ip46tables -I nixos-fw 1 -i ${bridge} -m conntrack --ctstate NEW -j nixos-fw-refuse
          iptables -I nixos-fw 1 -i ${bridge} -p tcp --dport 53 -j nixos-fw-accept
          iptables -I nixos-fw 1 -i ${bridge} -p udp --dport 53 -j nixos-fw-accept
          iptables -I nixos-fw 1 -i ${bridge} -p udp --dport 67 -j nixos-fw-accept
        '';

        # The guest clock stops while the host sleeps. --now sets it from the
        # host through the guest agent; --sync would only make Windows run
        # w32tm /resync. Guarded because nixpkgs runs these lines under set -e.
        powerManagement.resumeCommands = lib.mkAfter ''
          if [ "$(LC_ALL=C ${virsh} --connect ${uri} domstate ${name} 2>/dev/null)" = running ]; then
            ${virsh} --connect ${uri} domtime ${name} --now || echo "windows-guest resume: domtime failed" >&2
          fi
        '';
      };
    };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
