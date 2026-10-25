# Evaluates assertions only; nothing is built or booted.
{
  config,
  lib,
  inputs,
  metaOwner,
  nixosAppHelpers,
  ...
}:
let
  flakeModules = config.flake.nixosModules;
in
{
  perSystem =
    { pkgs, ... }:
    let
      failuresAs =
        trust: links:
        let
          system = inputs.nixpkgs.lib.nixosSystem {
            modules = [
              (nixosAppHelpers.getApp "libvirt")
              (nixosAppHelpers.getApp "podman")
              (nixosAppHelpers.getApp "docker-compose")
              (nixosAppHelpers.getApp "workloads")
              flakeModules."workloads-networks"
              flakeModules."workloads-vms"
              flakeModules."workloads-services"
              flakeModules."workloads-sharing"
              flakeModules."workloads-names"
              (
                { lib, ... }:
                {
                  options.programs.cloudflare-warp.extended.enable = lib.mkEnableOption "WARP";

                  config = {
                    _module.args = {
                      hostName = "machine";
                      inherit metaOwner;
                    };
                    nixpkgs.pkgs = pkgs;
                    boot.isContainer = true;
                    system.stateVersion = "26.05";
                    networking.nftables.enable = true;
                    users.users.${metaOwner.username}.isNormalUser = true;

                    workloads = {
                      networks = {
                        lan = {
                          id = 1;
                          resolve = [ "web" ];
                          libvirt = {
                            enable = true;
                            uuid = "00000000-0000-4000-8000-000000000101";
                            dhcp = {
                              start = 100;
                              end = 200;
                            };
                          };
                        };
                        svc = {
                          id = 2;
                          podman.enable = true;
                        };
                      };

                      host.services.api = {
                        ports = [ 7000 ];
                        bind = "loopback";
                      };

                      services.web = {
                        image = "web";
                        network = "svc";
                        address = 10;
                      };

                      guests.client = {
                        uuid = "00000000-0000-4000-8000-000000000102";
                        kind = "linux";
                        inherit trust;
                        memory = 256;
                        vcpus = 1;
                        interfaces.eth = {
                          network = "lan";
                          hostOffset = 10;
                        };
                        inherit links;
                      };
                    };
                  };
                }
              )
            ];
          };
        in
        map (assertion: assertion.message) (
          lib.filter (assertion: !assertion.assertion) system.config.assertions
        );

      failures = failuresAs "trusted";
      fails =
        fragment: result:
        lib.assertMsg (lib.any (lib.hasInfix fragment) result) "no failure mentions '${fragment}': ${toString result}";

      linked = failures [ "service:web:80" ];
      unlinked = failures [ ];
    in
    {
      checks.workloads-sharing-eval =
        assert lib.assertMsg (linked == [ ]) "a linked service in resolve fails: ${toString linked}";
        assert lib.assertMsg (lib.any (lib.hasInfix "web is a service") unlinked)
          "an unlinked service in resolve passes: ${toString unlinked}";
        assert lib.assertMsg (
          failures [
            "service:web:80"
            "host:api"
          ] == [ ]
        ) "a linked host service fails";
        assert fails "take grants" (failures [ "guest:sbx-x" ]);
        assert fails "no workloads.host.services.nope" (failures [ "host:nope" ]);
        assert fails "expected host:" (failures [ "bogus" ]);
        assert fails "ports lie between" (failures [ "service:web:70000" ]);
        assert fails "is not among the service's ports" (failures [ "host:api:7001" ]);
        assert fails "unknown kind" (failures [ "disk:web" ]);
        assert fails "no workloads.guests.nope" (failures [ "guest:nope" ]);
        assert fails "declares no ports" (failures [ "service:web" ]);
        assert fails "reach host services through grants only" (failuresAs "untrusted" [ "host:api" ]);
        pkgs.runCommand "workloads-sharing-eval" { } "touch $out";
    };
}
