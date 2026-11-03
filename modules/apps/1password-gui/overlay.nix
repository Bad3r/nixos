_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs."1password-gui".extended;
      onePasswordTemplate = builtins.readFile ../../stylix/icons/1password-outline.svg.mustache;
      onePasswordIcon = config.lib.stylix.colors {
        template = onePasswordTemplate;
        extension = ".svg";
      };
      # Tray glyph in the bar's status text color.
      onePasswordTrayIcon = config.lib.stylix.colors {
        template = builtins.replaceStrings [ "{{base05-hex}}" ] [ "{{base04-hex}}" ] onePasswordTemplate;
        extension = ".svg";
      };
      iconSizes = [
        32
        64
        256
        512
      ];
      colors = config.lib.stylix.colors.withHashtag;
      accent = "#3994bc"; # focusBorder
      shade = percent: base: "color-mix(in srgb, ${accent} ${toString percent}%, ${base})";
      # VS Code layering: content on base00, sidebar and popups on base01.
      themeTokens = {
        "[data-theme=dark]" = {
          "--color-grayscale-black" = colors.base01;
          "--color-grayscale-almost-black" = colors.base00;
          "--fill-01-02" = colors.base01;
          "--fill-01-03" = colors.base00;
          "--modal-bg" = colors.base01;
          "--move-menu-bg" = colors.base01;
          "--color-extras-window-splitter" = colors.base02;
          "--text-color-on-dark-primary" = colors.base05;
          "--text-color-01-02" = colors.base05;
          "--color-branding-bits-blue" = accent;
          "--color-bright-blue" = accent;
          "--color-readable-on-dark-blue" = colors.base0D;
          "--color-specifics-on-dark-focus-ring" = shade 60 "transparent";
          "--color-tints-on-dark-blue" = shade 24 "transparent";
          "--border-on-dark-blue" = accent;
        };
        ".knox-dark-mode.base" = {
          "--knox-background-neutral" = colors.base00;
          "--knox-background-neutral-high" = colors.base01;
          "--knox-background-neutral-low" = colors.base00;
          "--knox-background-overlay" = "color-mix(in srgb, ${colors.base00} 70%, transparent)";
          "--knox-background-brand" = accent;
          "--knox-background-brand-hover" = shade 85 "black";
          "--knox-background-brand-pressed" = shade 70 "black";
          "--knox-background-brand-weak" = shade 20 colors.base00;
          "--knox-background-row" = "color-mix(in srgb, ${colors.base07} 13%, ${colors.base01})";
          "--knox-border-neutral-weak" = colors.base02;
          "--knox-border-brand" = accent;
          "--knox-border-focus" = accent;
          "--knox-text-icon-neutral" = colors.base05;
          "--knox-text-icon-neutral-weak" = colors.base04;
          "--knox-text-icon-brand" = colors.base0D;
        };
      };
      themeCss = builtins.toFile "1password-stylix.css" (
        lib.concatStrings (
          lib.mapAttrsToList (
            selector: tokens:
            "${selector}{${lib.concatStrings (lib.mapAttrsToList (name: value: "${name}:${value};") tokens)}}\n"
          ) themeTokens
        )
      );
      themeTokenNames = lib.concatMap lib.attrNames (lib.attrValues themeTokens);
      patchOnePasswordGui =
        final: package:
        package.overrideAttrs (old: {
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
            final.asar
            final.librsvg
          ];
          postInstall = (old.postInstall or "") + ''
            renderOnePasswordIcon() {
              local source="$1"
              local size="$2"
              local output="$3"
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
                "$source" > "$output"
            }

            for size in ${lib.escapeShellArgs (map toString iconSizes)}; do
              for iconRoot in "$out/share/icons/hicolor" "$out/share/1password/resources/icons/hicolor"; do
                iconDir="$iconRoot/''${size}x''${size}/apps"
                mkdir -p "$iconDir"
                renderOnePasswordIcon ${onePasswordIcon} "$size" "$iconDir/1password.png"
              done
            done

            asarRoot="$(mktemp -d)"
            ${final.asar}/bin/asar extract "$out/share/1password/resources/app.asar" "$asarRoot/app"

            renderOnePasswordIcon ${onePasswordTrayIcon} 256 "$asarRoot/tray.png"
            for trayIcon in tray_locked tray_prompt tray_unlocked; do
              install -m 444 "$asarRoot/tray.png" "$asarRoot/app/images/$trayIcon.png"
            done

            for stylesheet in "$asarRoot"/app/*Renderer.css; do
              for token in ${lib.escapeShellArgs themeTokenNames}; do
                if ! grep -qF -- "$token:" "$stylesheet"; then
                  echo "1Password theme: $token is not defined in $(basename "$stylesheet")" >&2
                  exit 1
                fi
              done
              cat ${themeCss} >> "$stylesheet"
            done
            # Window background before the first paint.
            substituteInPlace "$asarRoot/app/main.js" \
              --replace-fail '"#333":"#f7f7f7"' '"${colors.base00}":"#f7f7f7"'

            # Asar's `*.node` glob matches every native addon at any depth,
            # so a future 1Password release that ships additional native
            # modules (e.g. a keytar binding) still lands in
            # `.asar.unpacked/` and stays dlopen-able. Without that
            # widening the bindings would silently repack inside the
            # asar and crash on first use.
            ${final.asar}/bin/asar pack \
              --unpack "{*.node,CREDITS.html}" \
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
          })
        ];
      };
    };
in
{
  flake.customOverlays."1password-gui" = Overlay;
}
