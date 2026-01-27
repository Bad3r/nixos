/*
  Package: virtualbox
  Description: Type-2 hypervisor for running hardware-virtualized guests.
  Homepage: https://www.virtualbox.org/
  Documentation: https://www.virtualbox.org/wiki/Documentation

  Summary:
    * Ships the VirtualBox Manager UI, headless tools, and VBoxManage CLI.
    * Provides kernel module tooling via dkms-style helpers packaged in nixpkgs.
    * Optionally enables VirtualBox host services and user groups.

  Example Usage:
    * `VirtualBox` -- Launch the Qt management UI for creating and managing VMs.
    * `vboxmanage list vms` -- Enumerate registered guests from the CLI.
*/
_:
let
  VirtualboxModule =
    {
      config,
      lib,
      pkgs,
      metaOwner,
      ...
    }:
    let
      cfg = config.programs.virtualbox.extended;
      owner = metaOwner.username;
    in
    {
      options.programs.virtualbox.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable virtualbox.";
        };

        enableHost = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable VirtualBox host services.";
        };

        package = lib.mkPackageOption pkgs "virtualbox" { };
      };

      config = lib.mkMerge [
        (lib.mkIf cfg.enable {
          environment.systemPackages = [ cfg.package ];
        })
        (lib.mkIf cfg.enableHost (
          lib.mkMerge [
            {
              virtualisation.virtualbox.host = {
                enable = true;
                package = pkgs.virtualbox;
              };
            }
            {
              users.users.${owner}.extraGroups = lib.mkAfter [ "vboxusers" ];
            }
          ]
        ))
      ];
    };
in
{
  nixpkgs.allowedUnfreePackages = [
    "virtualbox"
    "virtualbox-extpack"
  ];
  flake.nixosModules.apps.virtualbox = VirtualboxModule;
}
