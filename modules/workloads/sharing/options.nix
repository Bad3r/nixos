_:
let
  optionsModule =
    { lib, ... }:
    let
      inherit (lib) types;

      protoOption = lib.mkOption {
        type = types.enum [
          "tcp"
          "udp"
        ];
        default = "tcp";
        description = "Transport protocol of the ports.";
      };

      portModule =
        { config, ... }:
        {
          options = {
            port = lib.mkOption {
              type = types.nullOr types.port;
              default = null;
              description = "A single port; shorthand for equal `from` and `to`.";
            };

            from = lib.mkOption {
              type = types.port;
              default = if config.port == null then throw "a port entry needs `port` or `from`" else config.port;
              defaultText = lib.literalExpression "port";
              description = "First port of the range.";
            };

            to = lib.mkOption {
              type = types.port;
              default = config.from;
              defaultText = lib.literalExpression "from";
              description = "Last port of the range.";
            };

            proto = protoOption;
          };
        };

      # A bare number is a single TCP port.
      portsType = types.listOf (
        types.coercedTo types.port (port: { inherit port; }) (types.submodule portModule)
      );

      hostServiceModule = {
        options = {
          ports = lib.mkOption {
            type = portsType;
            description = ''
              Ports the service listens on: a number, or an entry with `port`
              or `from` and `to`, and `proto`.
            '';
          };

          bind = lib.mkOption {
            type = types.enum [
              "any"
              "loopback"
            ];
            description = ''
              `any`: the service listens on every address, the gateways
              included. `loopback`: it listens on 127.0.0.1 only, and a
              `systemd-socket-proxyd` on the gateway of each network that
              reaches it forwards there. Proxied ports are TCP only.
            '';
          };

          grantable = lib.mkOption {
            type = types.bool;
            default = false;
            description = "Whether runtime grants may open the service; links do not need it.";
          };
        };
      };

      guestModule = {
        options = {
          links = lib.mkOption {
            type = types.listOf types.str;
            default = [ ];
            example = [
              "host:dev:8080"
              "guest:win11:3389"
            ];
            description = ''
              Targets the guest may open connections to, as `host:<service>`,
              `guest:<name>`, or `service:<name>`, each with an optional
              `:<port>[/udp]`. Without a port, a link opens every port the
              target declares: a host service's `ports`, a guest's
              `grantable`, or a container service's container ports.
              Untrusted guests reach host services through grants only.
            '';
          };

          grantable = lib.mkOption {
            type = portsType;
            default = [ ];
            description = ''
              Ports runtime grants may open toward the guest, and the ports a
              link without a port opens.
            '';
          };
        };
      };

      interfaceModule = {
        options = {
          network = lib.mkOption {
            type = types.str;
            description = "`workloads.networks` entry the interface attaches to.";
          };
          address = lib.mkOption {
            type = types.str;
            description = "IPv4 address of the interface.";
          };
        };
      };

      endpointModule = {
        options = {
          trust = lib.mkOption {
            type = types.enum [
              "trusted"
              "untrusted"
            ];
            description = "Trust class of the object.";
          };

          interfaces = lib.mkOption {
            type = types.listOf (types.submodule interfaceModule);
            description = "Addresses of the object on workload networks; a link from another network uses the first, which for a guest is its alphabetically first interface name.";
          };

          ports = lib.mkOption {
            type = portsType;
            default = [ ];
            description = "Ports a link without a port opens toward the object.";
          };
        };
      };

      proxyModule = {
        options = {
          network = lib.mkOption {
            type = types.str;
            description = "`workloads.networks` entry whose gateway the proxy listens on.";
          };
          service = lib.mkOption {
            type = types.str;
            description = "`workloads.host.services` entry with `bind = \"loopback\"`.";
          };
          port = lib.mkOption {
            type = types.port;
            description = "TCP port the proxy listens on and forwards to on 127.0.0.1.";
          };
          sources = lib.mkOption {
            type = types.listOf types.str;
            description = "Addresses the proxy socket accepts connections from.";
          };
        };
      };
    in
    {
      options.workloads = {
        host.services = lib.mkOption {
          type = types.attrsOf (types.submodule hostServiceModule);
          default = { };
          description = ''
            Listeners on the host that links and grants name as
            `host:<name>`. Declaring one opens nothing. Names match
            `[a-z0-9][a-z0-9-]*`.
          '';
        };

        guests = lib.mkOption {
          type = types.attrsOf (types.submodule guestModule);
        };

        sharing = {
          endpoints = lib.mkOption {
            type = types.attrsOf (types.attrsOf (types.submodule endpointModule));
            default = { };
            internal = true;
            description = ''
              Link targets by kind (`guest`, `service`) and name; each runtime
              module adds its declared objects. Only guests are link sources,
              since only their addresses are pinned to their taps.
            '';
          };

          linkTargets = lib.mkOption {
            type = types.attrsOf (types.listOf (types.attrsOf types.str));
            readOnly = true;
            description = ''
              Link targets that guests on each `workloads.networks` entry
              reach, as `{ kind; name; address; }`. `host` targets carry the
              network's gateway address.
            '';
          };

          gatewayProxies = lib.mkOption {
            type = types.listOf (types.submodule proxyModule);
            default = [ ];
            internal = true;
            description = ''
              `systemd-socket-proxyd` instances on network gateways for
              loopback host services. Links add theirs; grants add the rest.
            '';
          };
        };
      };
    };
in
{
  flake.nixosModules."workloads-sharing" = optionsModule;
}
