_:
let
  optionsModule =
    { config, lib, ... }:
    let
      inherit (lib) types;
      inherit (config.workloads) networks;

      # libvirt reports UUIDs in lowercase.
      uuidType = types.strMatching "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";

      hostOffset =
        description:
        lib.mkOption {
          type = types.ints.between 2 254;
          inherit description;
        };

      networkModule = {
        options.libvirt = {
          enable = lib.mkEnableOption "a libvirt network on this registry entry";

          uuid = lib.mkOption {
            type = uuidType;
            description = ''
              Identity of the libvirt network. The reconciler finds the network
              by this UUID; the name and bridge follow the attribute name.
            '';
          };

          dhcp = {
            start = hostOffset "Host part of the first address the DHCP range hands out.";
            end = hostOffset "Host part of the last address the DHCP range hands out.";

            leaseMinutes = lib.mkOption {
              type = types.nullOr types.ints.positive;
              default = null;
              description = "Lease time of the DHCP range in minutes; null keeps libvirt's hour.";
            };

            clientNames = lib.mkOption {
              type = types.bool;
              default = true;
              description = "Whether the resolver answers the hostnames DHCP clients send.";
            };
          };

          autostart = lib.mkOption {
            type = types.bool;
            default = true;
            description = ''
              Whether libvirtd starts the network with the daemon. The
              reconciler also starts an inactive autostart network after
              defining it.
            '';
          };

          sessionAttach = lib.mkOption {
            type = types.bool;
            default = false;
            description = "Whether `qemu:///session` guests may attach to the bridge through qemu-bridge-helper.";
          };

          bindLeases = lib.mkOption {
            type = types.bool;
            default = false;
            description = ''
              Whether each guest port may send from a single MAC that no
              other port holds, and IPv4 and ARP only from an address the
              network's DHCP server leased to that MAC. DHCP to the gateway
              and ARP probes pass, other frame types are dropped, and the
              bridge learns no address from link-local frames. DHCP messages
              may still name any client MAC, which costs pool space, not an
              address.
            '';
          };
        };
      };

      mediaModule = {
        options = {
          source = lib.mkOption {
            # A string, so the file never enters the store.
            type = types.strMatching "/.+";
            description = "Absolute runtime path of the regular file to stage, read with the owner's permissions.";
          };

          sha256 = lib.mkOption {
            type = types.nullOr (types.strMatching "[0-9a-f]{64}");
            default = null;
            description = "Hex SHA-256 the staged copy must match.";
          };
        };
      };

      imageModule =
        { name, ... }:
        {
          options = {
            artifact = lib.mkOption {
              type = types.str;
              default = name;
              description = "`legacyPackages.<system>.workloads` attribute that builds the image.";
            };

            outLink = lib.mkOption {
              type = types.strMatching "/.+";
              default = "/var/lib/workloads/images/${name}";
              description = "`nix build --out-link` result that keeps the image alive.";
            };

            expected = lib.mkOption {
              # Without string context, so the image stays out of the closure.
              type = types.strMatching "/nix/store/.+";
              apply = builtins.unsafeDiscardStringContext;
              description = ''
                Store path of the qcow2 image: the build output, followed by
                the image's path inside it when the output is a directory.
                While `outLink` does not lead to it, a guest that libvirt has
                not defined and whose disk is missing stays undefined.
              '';
            };
          };
        };

      diskModule = {
        options = {
          size = lib.mkOption {
            type = types.ints.positive;
            description = ''
              Virtual size in GiB. A disk is created at this size on its
              guest's first define and never resized; a declared size below the
              image's virtual size fails the guest unit.
            '';
          };

          bus = lib.mkOption {
            type = types.enum [
              "virtio"
              "sata"
            ];
            default = "virtio";
            description = "Bus the disk attaches to.";
          };

          seed = lib.mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "`workloads.images` entry the disk is copied from when it is created; null creates an empty disk.";
          };
        };
      };

      interfaceModule = {
        options = {
          network = lib.mkOption {
            type = types.str;
            description = "`workloads.networks` entry with a libvirt network.";
          };

          hostOffset = hostOffset "Host part of the address the network's DHCP server reserves for this interface; it lies outside the DHCP range.";
        };
      };

      guestModule =
        { name, config, ... }:
        let
          windows = config.kind == "windows";
          trusted = config.trust == "trusted";
          # libvirt draws a random MAC at every define that omits one.
          macOf =
            nic:
            let
              hash = builtins.hashString "sha256" "${config.uuid}/${nic}";
            in
            "52:54:00:"
            + lib.concatMapStringsSep ":" (index: builtins.substring (2 * index) 2 hash) [
              0
              1
              2
            ];
          networkOf =
            nic:
            networks.${config.interfaces.${nic}.network}
              or (throw "workloads.guests.${name}.interfaces.${nic}: no workloads.networks.${
                config.interfaces.${nic}.network
              }");
          derived =
            type: description: default: defaultText:
            lib.mkOption {
              inherit type default description;
              readOnly = true;
              defaultText = lib.literalExpression defaultText;
            };
        in
        {
          options = {
            uuid = lib.mkOption {
              type = uuidType;
              description = ''
                Identity of the guest: the reconciler finds the domain by this
                UUID, and its disks, NVRAM, TPM state, and MAC addresses derive
                from it. Generate it once and never change it.
              '';
            };

            ensure = lib.mkOption {
              type = types.enum [
                "present"
                "absent"
              ];
              default = "present";
              description = ''
                `absent` undefines a shut-off domain without snapshots or a
                managed save image and keeps its disks, NVRAM, and TPM state.
              '';
            };

            kind = lib.mkOption {
              type = types.enum [
                "windows"
                "nixos"
                "linux"
              ];
              description = "Guest operating system family; `windows` requires Secure Boot with enrolled keys and a TPM.";
            };

            trust = lib.mkOption {
              type = types.enum [
                "trusted"
                "untrusted"
              ];
              description = ''
                Trust class. Untrusted guests get no SPICE agent channel, so
                no clipboard, file transfer, or display resizing.
              '';
            };

            memory = lib.mkOption {
              type = types.ints.positive;
              description = "Memory in MiB.";
            };

            vcpus = lib.mkOption {
              type = types.ints.positive;
              description = "Virtual CPUs, presented as cores of one socket.";
            };

            cpuset = lib.mkOption {
              type = types.nullOr (types.strMatching "[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*");
              default = null;
              description = "Host CPUs the guest's vCPUs and emulator threads run on, in libvirt cpuset syntax.";
            };

            firmware = {
              secureBoot = lib.mkOption {
                type = types.bool;
                default = windows;
                defaultText = lib.literalExpression ''kind == "windows"'';
                description = "Whether UEFI enforces Secure Boot; it also turns on SMM.";
              };

              enrolledKeys = lib.mkOption {
                type = types.bool;
                default = windows;
                defaultText = lib.literalExpression ''kind == "windows"'';
                description = "Whether the firmware ships the Microsoft Secure Boot keys.";
              };

              tpm = lib.mkOption {
                type = types.bool;
                default = windows;
                defaultText = lib.literalExpression ''kind == "windows"'';
                description = "Whether the guest gets an emulated TPM 2.0 with its state in the guest directory.";
              };
            };

            disks = lib.mkOption {
              type = types.attrsOf (types.submodule diskModule);
              default = { };
              description = ''
                Disk images under the guest directory, named `<disk>.qcow2`,
                attached and booted in name order. Names match
                `[a-z0-9][a-z0-9-]*`.
              '';
            };

            interfaces = lib.mkOption {
              type = types.attrsOf (types.submodule interfaceModule);
              default = { };
              description = "Network interfaces, attached in name order.";
            };

            display = lib.mkOption {
              type = types.enum [
                "spice"
                "headless"
              ];
              default = "spice";
              description = "`spice` adds a SPICE console on a unix socket; `headless` leaves only the serial console.";
            };

            clipboard = lib.mkOption {
              type = types.bool;
              default = trusted;
              defaultText = lib.literalExpression ''trust == "trusted"'';
              description = "Whether the SPICE console shares the clipboard with the guest.";
            };

            fileTransfer = lib.mkOption {
              type = types.bool;
              default = trusted;
              defaultText = lib.literalExpression ''trust == "trusted"'';
              description = "Whether files dropped on the SPICE console are copied into the guest.";
            };

            guestAgent = lib.mkOption {
              type = types.bool;
              default = true;
              description = "Whether the guest gets the QEMU guest agent channel.";
            };

            usbRedirection = lib.mkOption {
              type = types.bool;
              default = false;
              description = ''
                Whether SPICE clients may redirect host USB devices into the
                guest. Any guest with it installs the setuid SPICE USB helper,
                which lets local users open USB devices.
              '';
            };

            install.media = lib.mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "`workloads.media` entries attached as read-only CD-ROMs, booted after the disks.";
            };

            autostart = lib.mkOption {
              type = types.bool;
              default = false;
              description = ''
                Whether libvirtd starts the guest with the daemon. The
                reconciler also starts it once, right after its first define.
              '';
            };

            extraDevicesXml = lib.mkOption {
              type = types.lines;
              default = "";
              description = "Raw XML appended to the domain's `<devices>`, validated with the rest of the domain.";
            };

            domainName = derived types.str "Name of the libvirt domain." name "<name>";

            stateDir =
              derived types.str "Directory holding the guest's disks, NVRAM, and TPM state."
                "/var/lib/workloads/guests/${config.uuid}"
                ''"/var/lib/workloads/guests/''${uuid}"'';

            nvramPath =
              derived types.str "UEFI variable store of the guest." "${config.stateDir}/nvram.fd"
                ''"''${stateDir}/nvram.fd"'';

            mac =
              derived (types.attrsOf types.str)
                "MAC address of each interface, derived from the UUID and the interface name."
                (lib.mapAttrs (nic: _: macOf nic) config.interfaces)
                "{ <nic> = \"52:54:00:...\"; }";

            bridge = derived (types.attrsOf types.str) "Bridge each interface attaches to." (lib.mapAttrs (
              nic: _: (networkOf nic).bridge
            ) config.interfaces) "{ <nic> = workloads.networks.<network>.bridge; }";

            address =
              derived (types.attrsOf types.str) "IPv4 address the network reserves for each interface."
                (lib.mapAttrs (
                  nic: interface:
                  "${lib.removeSuffix ".0/24" (networkOf nic).subnet}.${toString interface.hostOffset}"
                ) config.interfaces)
                "{ <nic> = \"<network prefix>.<hostOffset>\"; }";
          };
        };
    in
    {
      options.workloads = {
        networks = lib.mkOption {
          type = types.attrsOf (types.submodule networkModule);
        };

        guests = lib.mkOption {
          type = types.attrsOf (types.submodule guestModule);
          default = { };
          description = ''
            libvirt guests on `qemu:///system`, each defined by its own
            `workloads-vm-guest-<name>` unit. Definitions apply at the
            guest's next cold boot. Names match `[a-z0-9][a-z0-9-]*`.
          '';
        };

        images = lib.mkOption {
          type = types.attrsOf (types.submodule imageModule);
          default = { };
          description = "Nix-built disk images that seed guest disks, by runtime path.";
        };

        media = lib.mkOption {
          type = types.attrsOf (types.submodule mediaModule);
          default = { };
          description = ''
            Files staged as root-owned 0644 copies under
            {file}`/var/lib/workloads/media/<name>`, where QEMU can read them.
            Each run of `workloads-vm-media.service` resets an owner or mode
            libvirt changed and prunes staged files whose declaration is gone.
            Names match `[a-z0-9][a-z0-9._-]*`.
          '';
        };
      };
    };
in
{
  flake.nixosModules."workloads-vms" = optionsModule;
}
