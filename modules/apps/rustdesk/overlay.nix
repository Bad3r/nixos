_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs.rustdesk.extended;
      trayIcon = ../../stylix/icons/rustdesk-tray.svg;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: prev: {
            # The tray loads data/flutter_assets/assets/icon.png beside the
            # resolved executable before its built-in icon. A repack instead of
            # overrideAttrs keeps the Rust and Flutter build substitutable.
            rustdesk-flutter =
              final.runCommand prev.rustdesk-flutter.name
                {
                  nativeBuildInputs = [
                    final.librsvg
                    final.patchelf
                  ];
                  inherit (prev.rustdesk-flutter) meta passthru version;
                }
                ''
                  original=${prev.rustdesk-flutter}
                  cp -rs "$original" "$out"
                  chmod -R u+w "$out"

                  app="$out/app/rustdesk"
                  rm "$app/rustdesk" "$out/bin/rustdesk" "$out/bin/.rustdesk-wrapped"
                  install -m 755 "$original/app/rustdesk/rustdesk" "$app/rustdesk"
                  # nix-store --optimise would hard-link a byte-identical copy to the original.
                  patchelf --add-rpath "$app/lib" "$app/rustdesk"
                  ln -s ../app/rustdesk/rustdesk "$out/bin/.rustdesk-wrapped"
                  substitute "$original/bin/rustdesk" "$out/bin/rustdesk" \
                    --replace-fail "$original/" "$out/"
                  chmod 555 "$out/bin/rustdesk"

                  rsvg-convert \
                    --page-width 256 \
                    --page-height 256 \
                    --width 176 \
                    --height 176 \
                    --left 40 \
                    --top 40 \
                    --keep-aspect-ratio \
                    ${trayIcon} > "$app/data/flutter_assets/assets/icon.png"
                '';
          })
        ];
      };
    };
in
{
  flake.customOverlays.rustdesk = Overlay;
}
