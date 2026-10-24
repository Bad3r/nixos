_:
let
  optionsModule =
    { lib, ... }:
    let
      inherit (lib) types;

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
    in
    {
      options.workloads = {
        networks = lib.mkOption {
          type = types.attrsOf (types.submodule networkModule);
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
