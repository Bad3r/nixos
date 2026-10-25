# Evaluates drop selection and service share assertions; nothing is built or booted.
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
  owner = metaOwner.username;
in
{
  perSystem =
    { pkgs, ... }:
    let
      guest = name: attrs: {
        ${name} = {
          uuid = "00000000-0000-4000-8000-${builtins.substring 0 12 (builtins.hashString "sha256" name)}";
          kind = "linux";
          trust = "trusted";
          memory = 256;
          vcpus = 1;
        }
        // attrs;
      };

      evaluate =
        workloads:
        (inputs.nixpkgs.lib.nixosSystem {
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
                  users.users = {
                    ${owner} = {
                      isNormalUser = true;
                      inherit (metaOwner) uid;
                    };
                    floating.isNormalUser = true;
                  };

                  workloads = lib.recursiveUpdate {
                    networks.svc = {
                      id = 2;
                      podman.enable = true;
                    };
                  } workloads;
                };
              }
            )
          ];
        }).config;

      failures =
        system:
        map (assertion: assertion.message) (lib.filter (assertion: !assertion.assertion) system.assertions);

      service =
        attrs:
        {
          image = "web";
          network = "svc";
          address = 10;
        }
        // attrs;

      selection = evaluate {
        guests =
          guest "desk" { }
          // guest "lab" { trust = "untrusted"; }
          // guest "quiet" { shares.drop.enable = false; }
          // guest "gone" { ensure = "absent"; };
        services = {
          web = service { };
          inbox = service {
            address = 11;
            shares.drop.enable = true;
          };
        };
      };
      dropDirs = map baseNameOf (
        lib.attrNames (
          removeAttrs selection.systemd.tmpfiles.settings.workloads-drops [ "/var/lib/workloads/shares" ]
        )
      );

      shareFailures =
        share:
        lib.filter (lib.hasPrefix "workloads.services.") (
          failures (evaluate {
            services.web = service {
              shares.data = {
                hostPath = "/srv/data";
              }
              // share;
            };
          })
        );
    in
    {
      checks.workloads-sharing-drops =
        assert lib.assertMsg (
          failures selection == [ ]
        ) "drop selection fails: ${toString (failures selection)}";
        assert lib.assertMsg (
          dropDirs == [
            "desk"
            "inbox"
          ]
        ) "drop directories: ${toString dropDirs}";
        assert lib.assertMsg
          (selection.workloads.guests.desk.mounts ? drop && selection.workloads.guests.quiet.mounts == { })
          "trusted guest mounts: ${
            builtins.toJSON (lib.mapAttrs (_: g: g.mounts) selection.workloads.guests)
          }";
        assert lib.assertMsg (
          shareFailures { } == [ ]
        ) "an owner share fails: ${toString (shareFailures { })}";
        assert lib.assertMsg (lib.all
          (
            owner:
            lib.length (shareFailures {
              inherit owner;
            }) == 1
          )
          [
            "root"
            "floating"
            "nobody-here"
          ]
        ) "a root, floating, or undeclared share owner passes";
        pkgs.runCommand "workloads-sharing-drops" { } "touch $out";
    };
}
