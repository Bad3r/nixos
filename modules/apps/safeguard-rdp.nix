/*
  Package: safeguard-rdp
  Description: rdp:// URI handler for OneIdentity Safeguard "Start RDP Session" launches.
  Homepage: https://github.com/OneIdentity/SCALUS

  Summary:
    * Registers a native handler for the rdp:// URI scheme (x-scheme-handler/rdp).
    * Reconstructs a temporary .rdp from Safeguard's SCALUS launch URI and opens
      it with Remmina, so a session starts the instant it is requested instead of
      after downloading and double-clicking a file.
    * Removing that delay wins the race against Safeguard's short-lived one-time
      launch token, which otherwise expires and the session logs off with
      ERRINFO_LOGOFF_BY_USER.

  Ownership:
    * Overrides the default x-scheme-handler/rdp handler (Remmina's own desktop
      file claims the scheme but only parses native rdp://user:pass@host URIs).
      The `application/x-rdp` file association stays owned by
      host.defaults.remoteDesktopClient (Remmina) and is untouched here.

  Requirements:
    * The Safeguard side must be configured for URI launch (the "Start RDP
      Session" button / SCALUS registration). In file-download mode Safeguard
      never emits an rdp:// URI and this handler is simply unused.
    * programs.remmina.extended must be enabled (the launcher opens the
      reconstructed .rdp through Remmina).

  Options:
    programs.safeguard-rdp.extended.enable: Install the launcher and register it
      as the default x-scheme-handler/rdp handler.
*/
_:
let
  SafeguardRdpModule =
    {
      config,
      lib,
      pkgs,
      options,
      ...
    }:
    let
      cfg = config.programs.safeguard-rdp.extended;
      desktop = "safeguard-rdp.desktop";
      hasHomeManager = options ? home-manager;
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
            environment.systemPackages = [ cfg.package ];
            xdg.mime.defaultApplications."x-scheme-handler/rdp" = desktop;
            xdg.mime.addedAssociations."x-scheme-handler/rdp" = desktop;
          }
          (lib.optionalAttrs hasHomeManager {
            home-manager.sharedModules = [
              {
                xdg.mimeApps = {
                  enable = true;
                  defaultApplications."x-scheme-handler/rdp" = desktop;
                  associations.added."x-scheme-handler/rdp" = desktop;
                };
              }
            ];
          })
        ]
      );
    };
in
{
  flake.nixosModules.apps.safeguard-rdp = SafeguardRdpModule;
}
