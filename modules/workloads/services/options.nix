_:
let
  optionsModule =
    { lib, ... }:
    let
      inherit (lib) types;

      networkModule = {
        options.podman.enable = lib.mkEnableOption "a rootful Podman network on this registry entry";
      };

      portModule = {
        options = {
          host = lib.mkOption {
            type = types.port;
            description = "Port on the host's 127.0.0.1.";
          };

          container = lib.mkOption {
            type = types.port;
            description = "Port the container listens on.";
          };

          protocol = lib.mkOption {
            type = types.enum [
              "tcp"
              "udp"
            ];
            default = "tcp";
            description = "Transport protocol of the port.";
          };
        };
      };

      serviceModule = {
        options = {
          image = lib.mkOption {
            type = types.str;
            description = ''
              Image reference. With `imageFile`, the name and tag the archive
              loads as.
            '';
          };

          imageFile = lib.mkOption {
            type = types.nullOr types.package;
            default = null;
            description = "Image archive loaded before each start, such as a `dockerTools.buildImage` result.";
          };

          network = lib.mkOption {
            type = types.str;
            description = "Name of the `workloads.networks` entry, with `podman.enable` set, the container joins.";
          };

          address = lib.mkOption {
            type = types.ints.between 2 254;
            description = "Host part of the container's address in the network's subnet.";
          };

          ports = lib.mkOption {
            type = types.listOf (types.submodule portModule);
            default = [ ];
            description = "Container ports the host reaches on 127.0.0.1.";
          };

          volumes = lib.mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Mounts in `podman run --volume` syntax.";
          };

          autostart = lib.mkOption {
            type = types.bool;
            default = false;
            description = "Whether the container starts at boot.";
          };
        };
      };
    in
    {
      options.workloads = {
        networks = lib.mkOption {
          type = types.attrsOf (types.submodule networkModule);
        };

        services = lib.mkOption {
          type = types.attrsOf (types.submodule serviceModule);
          default = { };
          description = ''
            Containers on rootful Podman, one per entry, run as
            `virtualisation.oci-containers.containers.svc-<name>`. Settings
            without an option here go on that container directly.
          '';
        };
      };
    };
in
{
  flake.nixosModules."workloads-services" = optionsModule;
}
