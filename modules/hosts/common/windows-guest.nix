{ inputs, metaOwner, ... }:
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
      domainUuid = "d40dd3b2-a6ad-4136-89d8-120cb5d3c098";
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

      networkName = "default";
      bridge = "virbr0";
      hostAddress = "10.11.11.1";
      guestAddress = "10.11.11.2";

      defaultNetworkTemplate = nixvirt.network.templates.bridge {
        uuid = defaultNetworkUuid;
        subnet_byte = 0;
      };
      defaultNetwork = defaultNetworkTemplate // {
        ip = {
          address = hostAddress;
          netmask = "255.255.255.0";
          dhcp = {
            range = {
              start = "10.11.11.3";
              end = "10.11.11.254";
            };
            host = {
              mac = guestMac;
              ip = guestAddress;
            };
          };
        };
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
          count = cfg.diskSize;
          unit = "GiB";
        };
        allocation = {
          count = 0;
          unit = "bytes";
        };
        target.format.type = "qcow2";
      };

      owner = config.users.users.${metaOwner.username};

      # Drop host privileges before virtiofsd creates its user namespace so guest
      # ownership requests cannot create files owned by another host account.
      virtiofsd = pkgs.writeShellScript "virtiofsd-transfer" ''
        exec ${lib.getExe' pkgs.util-linux "setpriv"} --reuid=${toString owner.uid} \
          --regid=${toString config.users.groups.${owner.group}.gid} --clear-groups --no-new-privs \
          ${lib.getExe pkgs.virtiofsd} "$@"
      '';

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
        # vhost-user hands guest RAM to virtiofsd, so it has to be shared.
        memoryBacking = {
          source.type = "memfd";
          access.mode = "shared";
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
          filesystem = {
            type = "mount";
            accessmode = "passthrough";
            driver.type = "virtiofs";
            binary.path = "${virtiofsd}";
            source.dir = cfg.transferDir;
            target.dir = "transfer";
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

        rdpUser = lib.mkOption {
          type = lib.types.str;
          default = "outlook";
          readOnly = true;
          description = "Local Windows account the RemoteApp launcher signs in as.";
        };

        transferDir = lib.mkOption {
          type = lib.types.str;
          default = "/mnt/outlook";
          readOnly = true;
          description = ''
            Host directory the guest mounts over virtiofs, so every guest session sees it, the
            virt-manager console as well as RDP.
          '';
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

        diskSize = lib.mkOption {
          type = lib.types.ints.positive;
          default = 64;
          description = ''
            Capacity in GiB of the guest volume. NixVirt creates the volume at this size and never
            resizes an existing one, so raise it after `virsh vol-resize` to keep the declaration
            matching the disk.
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
            # The domain embeds store paths that move with nixpkgs, so changes
            # apply on its next start. Network XML has no store paths and restarts
            # only when its definition changes.
            connections.${uri} = {
              networks = [
                {
                  definition = nixvirt.network.writeXML defaultNetwork;
                  active = true;
                  restart = null;
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
        systemd.tmpfiles.settings."10-windows-guest" = {
          ${poolPath}.d = {
            user = "root";
            group = "root";
            mode = "0711";
          };
          ${cfg.transferDir}.d = {
            inherit (owner) group;
            user = metaOwner.username;
            mode = "0700";
          };
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
          iptables -I nixos-fw 1 -i ${bridge} -s 10.11.11.0/24 -p tcp --dport 8000:9999 -m conntrack --ctstate NEW -j nixos-fw-accept
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
