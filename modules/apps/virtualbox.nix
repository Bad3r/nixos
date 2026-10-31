/*
  Package: virtualbox
  Description: Type-2 hypervisor for running hardware-virtualized guests.
  Homepage: https://www.virtualbox.org/
  Documentation: https://www.virtualbox.org/wiki/Documentation
  Repository: https://github.com/VirtualBox/virtualbox

  Summary:
    * Ships the VirtualBox Manager UI, headless tools, and VBoxManage CLI.
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
        (lib.mkIf (cfg.enable && !cfg.enableHost) {
          environment.systemPackages = [ cfg.package ];
        })
        (lib.mkIf cfg.enableHost (
          lib.mkMerge [
            {
              virtualisation.virtualbox.host = {
                enable = true;
                inherit (cfg) package;
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
  flake.nixosModules.apps.virtualbox = VirtualboxModule;
}
