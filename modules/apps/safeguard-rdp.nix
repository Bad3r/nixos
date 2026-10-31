/*
  Package: safeguard-rdp
  Description: rdp:// URI handler for OneIdentity Safeguard "Start RDP Session" launches.
  Homepage: https://github.com/OneIdentity/SCALUS
  Repository: https://github.com/Bad3r/nixos

  Summary:
    * Registers a native handler for the rdp:// URI scheme (x-scheme-handler/rdp).
    * Rebuilds a temporary .rdp from Safeguard's SCALUS launch URI and opens it with Remmina at once,
      before the one-time launch token expires.

  Notes:
    * Needs Safeguard's URI launch mode.
    * Replaces Remmina as the rdp:// handler; `.rdp` files still open in Remmina.
*/
_:
let
  SafeguardRdpModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.safeguard-rdp.extended;
      desktop = "safeguard-rdp.desktop";
    in
    {
      options.programs.safeguard-rdp.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable the Safeguard rdp:// URI handler.";
        };

        package = lib.mkPackageOption pkgs "safeguard-rdp" { };
      };

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            programs.remmina.extended.enable = lib.mkOverride 1050 true;
            environment.systemPackages = [ cfg.package ];
            xdg.mime.defaultApplications."x-scheme-handler/rdp" = desktop;
            xdg.mime.addedAssociations."x-scheme-handler/rdp" = desktop;
          }
          {
            home-manager.sharedModules = [
              {
                xdg.mimeApps = {
                  enable = true;
                  defaultApplications."x-scheme-handler/rdp" = desktop;
                  associations.added."x-scheme-handler/rdp" = desktop;
                };
              }
            ];
          }
        ]
      );
    };
in
{
  flake.nixosModules.apps.safeguard-rdp = SafeguardRdpModule;
}
