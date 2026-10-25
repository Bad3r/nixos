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
      failuresWith =
        {
          trust ? "trusted",
          links ? [ ],
          grants ? [ ],
          bindLeases ? true,
        }:
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
                        sbx = {
                          id = 3;
                          isolatePeers = true;
                          libvirt = {
                            enable = true;
                            uuid = "00000000-0000-4000-8000-000000000103";
                            dhcp = {
                              start = 2;
                              end = 254;
                            };
                            sessionAttach = true;
                            inherit bindLeases;
                          };
                        };
                      };

                      host.services = {
                        api = {
                          ports = [ 7000 ];
                          bind = "loopback";
                        };
                        dev = {
                          ports = [
                            {
                              from = 8000;
                              to = 8999;
                            }
                          ];
                          bind = "any";
                          grantable = true;
                        };
                      };

                      grants.allow = grants;

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

      failuresAs = trust: links: failuresWith { inherit trust links; };
      failures = failuresAs "trusted";
      grantFailures =
        to:
        failuresWith {
          links = [ "service:web:80" ];
          grants = [
            {
              from = [
                "sbx-*"
                "guest:client"
              ];
              inherit to;
            }
          ];
        };
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
        assert lib.assertMsg (
          grantFailures [
            "host:dev"
            "host:dev:8080"
          ] == [ ]
        ) "a valid grant rule fails";
        assert fails "from lan: expected sbx-*" (failuresWith {
          links = [ "service:web:80" ];
          grants = [
            {
              from = [ "lan" ];
              to = [ "host:dev" ];
            }
          ];
        });
        assert fails "the host service is not grantable" (grantFailures [ "host:api" ]);
        assert fails "not among the target's grantable ports" (grantFailures [ "host:dev:9000" ]);
        assert fails "declares no grantable ports" (grantFailures [ "guest:client" ]);
        assert fails "declares no grantable ports" (grantFailures [ "service:web" ]);
        assert fails "no such workloads.host.services entry" (grantFailures [ "host:nope" ]);
        assert fails "expected host:<service>" (grantFailures [ "10.0.0.1:22" ]);
        assert fails "which needs libvirt.bindLeases" (failuresWith {
          links = [ "service:web:80" ];
          bindLeases = false;
          grants = [
            {
              from = [ "sbx-*" ];
              to = [ "host:dev" ];
            }
          ];
        });
        pkgs.runCommand "workloads-sharing-eval" { } "touch $out";
    };
}
