_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs."1password-gui-beta".extended;
      onePasswordIcon = ../stylix/icons/1password-outline.svg;
      iconSizes = [
        32
        64
        256
        512
      ];
      patchOnePasswordGui =
        final: package:
        package.overrideAttrs (old: {
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
            final.asar
            final.librsvg
          ];
          postInstall = (old.postInstall or "") + ''
            renderOnePasswordIcon() {
              local size="$1"
              local output="$2"
              local glyphSize="$((size * 11 / 16))"
              local offset="$(((size - glyphSize) / 2))"

              ${final.librsvg}/bin/rsvg-convert \
                --page-width "$size" \
                --page-height "$size" \
                --width "$glyphSize" \
                --height "$glyphSize" \
                --left "$offset" \
                --top "$offset" \
                --keep-aspect-ratio \
                ${onePasswordIcon} > "$output"
            }

            for size in ${lib.escapeShellArgs (map toString iconSizes)}; do
              for iconRoot in "$out/share/icons/hicolor" "$out/share/1password/resources/icons/hicolor"; do
                iconDir="$iconRoot/''${size}x''${size}/apps"
                mkdir -p "$iconDir"
                renderOnePasswordIcon "$size" "$iconDir/1password.png"
              done
            done

            asarRoot="$(mktemp -d)"
            ${final.asar}/bin/asar extract "$out/share/1password/resources/app.asar" "$asarRoot/app"

            renderOnePasswordIcon 256 "$asarRoot/tray.png"
            for trayIcon in tray_locked tray_prompt tray_unlocked; do
              install -m 444 "$asarRoot/tray.png" "$asarRoot/app/images/$trayIcon.png"
            done

            ${final.asar}/bin/asar pack \
              --unpack "{index.node,CREDITS.html}" \
              "$asarRoot/app" \
              "$asarRoot/app.asar"
            cp "$asarRoot/app.asar" "$out/share/1password/resources/app.asar"
          '';
        });
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: prev: {
            _1password-gui = patchOnePasswordGui final prev._1password-gui;
            _1password-gui-beta = patchOnePasswordGui final prev._1password-gui-beta;
          })
        ];
      };
    };
in
{
  flake.customOverlays."1password-gui-beta" = Overlay;
}
