_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs."proton-vpn".extended;
      trayIconName = "protonvpn-tray";
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (_final: prev: {
            proton-vpn = prev.proton-vpn.overrideAttrs (old: {
              postPatch = (old.postPatch or "") + ''
                substituteInPlace proton/vpn/app/gtk/widgets/main/tray_icon.py \
                  --replace-fail 'TRAY_ICON_NAME = "proton-vpn-sign"' \
                                 'TRAY_ICON_NAME = "${trayIconName}"'

                substituteInPlace proton/vpn/app/gtk/widgets/main/tray_indicator.py \
                  --replace-fail 'ICONS_PATH / f"state-{states.Disconnected.__name__.lower()}.svg"' \
                                 '"${trayIconName}"' \
                  --replace-fail 'ICONS_PATH / f"state-{states.Connected.__name__.lower()}.svg"' \
                                 '"${trayIconName}"' \
                  --replace-fail 'ICONS_PATH / f"state-{states.Error.__name__.lower()}.svg"' \
                                 '"${trayIconName}"'
              '';
            });
          })
        ];
      };
    };
in
{
  flake.customOverlays."proton-vpn" = Overlay;
}
