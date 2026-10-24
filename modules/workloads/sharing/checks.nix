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
      failures =
        links:
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

                      services.web = {
                        image = "web";
                        network = "svc";
                        address = 10;
                      };

                      guests.client = {
                        uuid = "00000000-0000-4000-8000-000000000102";
                        kind = "linux";
                        trust = "trusted";
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

      linked = failures [ "service:web:80" ];
      unlinked = failures [ ];
    in
    {
      checks.workloads-sharing-eval =
        assert lib.assertMsg (linked == [ ]) "a linked service in resolve fails: ${toString linked}";
        assert lib.assertMsg (lib.any (lib.hasInfix "web is a service") unlinked)
          "an unlinked service in resolve passes: ${toString unlinked}";
        pkgs.runCommand "workloads-sharing-eval" { } "touch $out";
    };
}
