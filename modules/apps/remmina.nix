/*
  Package: remmina
  Description: GTK remote desktop client for managing saved connection profiles.
  Homepage: https://remmina.org/
  Documentation: https://remmina.gitlab.io/remminadoc.gitlab.io/
  Repository: https://gitlab.com/Remmina/Remmina

  Summary:
    * Provides a tabbed GTK client for RDP, VNC, SPICE, NX, X2Go, SSH, SFTP, and related remote-access workflows.
    * Supports reusable connection profiles, SSH tunneling, and plugin-driven protocol integration from one interface.

  Options:
    -c <file.remmina>: Connect using a saved profile file or a supported URI.
    --set-option key=value --update-profile <file.remmina>: Modify stored profile settings from the command line.
*/
_:
let
  RemminaModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.remmina.extended;
      rdpMimeInfo = pkgs.writeTextDir "share/mime/packages/application-x-rdp.xml" ''
        <?xml version="1.0" encoding="UTF-8"?>
        <mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
          <mime-type type="application/x-rdp">
            <comment>RDP connection file</comment>
            <icon name="application-x-rdp"/>
            <glob-deleteall/>
            <glob pattern="*.rdp"/>
          </mime-type>
        </mime-info>
      '';
    in
    {
      options.programs.remmina.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable remmina.";
        };

        package = lib.mkPackageOption pkgs "remmina" { };

        intelDecodeDevice = lib.mkOption {
          type = lib.types.nullOr (lib.types.strMatching "/dev/dri/.+");
          default = null;
          example = "/dev/dri/by-path/pci-0000:00:02.0-render";
          description = ''
            Render node of an Intel GPU that decodes RDP H.264 streams through
            VA-API and intel-media-driver, whatever LIBVA_DRIVER_NAME the session
            sets. Null leaves FreeRDP on its default node, /dev/dri/renderD128,
            with the session's libva driver.
          '';
        };
      };

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            environment.systemPackages = [
              cfg.package
              rdpMimeInfo
            ];
          }
          # An overlay, so every launcher (safeguard-rdp, 1drdp) starts the
          # same wrapped Remmina.
          (lib.mkIf (cfg.intelDecodeDevice != null) {
            nixpkgs.overlays = [
              (final: prev: {
                remmina = prev.remmina.overrideAttrs (old: {
                  preFixup = (old.preFixup or "") + ''
                    gappsWrapperArgs+=(
                      --set LIBVA_DRIVER_NAME iHD
                      --set LIBVA_DRIVERS_PATH "${final.intel-media-driver}/lib/dri"
                      --set FREERDP_HWCTX_DEVICE "${cfg.intelDecodeDevice}"
                    )
                  '';
                });
              })
            ];
          })
        ]
      );
    };
in
{
  flake.nixosModules.apps.remmina = RemminaModule;
}
