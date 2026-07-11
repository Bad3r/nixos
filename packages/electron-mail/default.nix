{
  appimageTools,
  lib,
  fetchurl,
  asar,
  librsvg,
  stdenvNoCC,
  makeWrapper,
  undmg,
  themedTrayIcon ? null,
  # Strip the in-app logged-out indicator and the unread-mail counter
  # overlay so the themed tray glyph renders cleanly. The two upstream
  # behaviours print text and a coloured dot on top of the icon, which
  # defeats a Stylix-driven outline glyph. Set to false to keep the
  # upstream indicators when using a custom icon.
  disableTrayIndicators ? true,
}:

let
  pname = "electron-mail";
  version = "5.3.8";
  passthru = {
    updateScript = ./update.py;
  };

  sources = {
    x86_64-linux = fetchurl {
      url = "https://github.com/vladimiry/ElectronMail/releases/download/v${version}/electron-mail-${version}-linux-x86_64.AppImage";
      hash = "sha256-twqB1D3zLlZJuxQWD4dGF70w57yYv6i3abGBidERsss=";
    };
    aarch64-darwin = fetchurl {
      url = "https://github.com/vladimiry/ElectronMail/releases/download/v${version}/electron-mail-${version}-mac-arm64.dmg";
      hash = "sha256-V32Wi0oCU9dLfzqxg3OdseiILX7wPiBGNz7KuG0vlZY=";
    };
    x86_64-darwin = fetchurl {
      url = "https://github.com/vladimiry/ElectronMail/releases/download/v${version}/electron-mail-${version}-mac-x64.dmg";
      hash = "sha256-I1UvFMSdAwkqgkhn+mkBGslA8v+VTajO/Za0lJ5uYZ8=";
    };
  };

  src = sources.${stdenvNoCC.hostPlatform.system};

  linuxIconSizes = [
    16
    24
    32
    48
    64
    128
    256
    512
    1024
  ];

  appimageContents = appimageTools.extract {
    inherit src pname version;
    postExtract = lib.optionalString (themedTrayIcon != null) (
      ''
        renderThemedIcon() {
          local size="$1"
          local output="$2"
          local glyphSize="$((size * 11 / 16))"
          local offset="$(((size - glyphSize) / 2))"

          ${librsvg}/bin/rsvg-convert \
            --page-width "$size" \
            --page-height "$size" \
            --width "$glyphSize" \
            --height "$glyphSize" \
            --left "$offset" \
            --top "$offset" \
            --keep-aspect-ratio \
            ${themedTrayIcon} > "$output"
        }

        for size in ${lib.escapeShellArgs (map toString linuxIconSizes)}; do
          iconDir="$out/usr/share/icons/hicolor/''${size}x''${size}/apps"
          mkdir -p "$iconDir"
          renderThemedIcon "$size" "$iconDir/${pname}.png"
        done

        asarRoot="$(mktemp -d)"
        ${asar}/bin/asar extract "$out/resources/app.asar" "$asarRoot/app"
      ''
      + lib.optionalString disableTrayIndicators ''
        substituteInPlace "$asarRoot/app/app/electron-main/index.cjs" \
          --replace-fail \
            'const canvas = !disableNotLoggedInTrayIndication && hasLoggedOut ? state.loggedOutIcon : state.defaultIcon;' \
            'const canvas = state.defaultIcon;' \
          --replace-fail \
            'if (unread > 0) {' \
            'if (false && unread > 0) {'
      ''
      + ''
        renderThemedIcon 128 "$asarRoot/app/app/assets/icons/icon.png"
        for size in ${lib.escapeShellArgs (map toString linuxIconSizes)}; do
          renderThemedIcon "$size" "$asarRoot/app/app/assets/icons/png/''${size}x''${size}.png"
        done

        ${asar}/bin/asar pack \
          --unpack-dir "{node_modules/sodium-native,node_modules/keytar}" \
          "$asarRoot/app" \
          "$asarRoot/app.asar"
        cp "$asarRoot/app.asar" "$out/resources/app.asar"
      ''
    );
  };

  meta = {
    description = "Unofficial Electron-based ProtonMail desktop client";
    mainProgram = "electron-mail";
    homepage = "https://github.com/vladimiry/ElectronMail";
    license = lib.licenses.gpl3;
    maintainers = with lib.maintainers; [
      princemachiavelli
      BatteredBunny
    ];
    platforms = [
      "x86_64-linux"
      "aarch64-darwin"
      "x86_64-darwin"
    ];
    changelog = "https://github.com/vladimiry/ElectronMail/releases/tag/v${version}";
  };

  linux = appimageTools.wrapAppImage {
    inherit
      pname
      version
      meta
      passthru
      ;
    src = appimageContents;

    extraInstallCommands = ''
      install -m 444 -D ${appimageContents}/${pname}.desktop -t $out/share/applications
      substituteInPlace $out/share/applications/${pname}.desktop \
        --replace-fail 'Exec=AppRun' 'Exec=${pname}'
      cp -r ${appimageContents}/usr/share/icons $out/share
    '';

    extraPkgs = pkgs: [
      pkgs.libsecret
      pkgs.libappindicator-gtk3
    ];

  };

  darwin = stdenvNoCC.mkDerivation {
    inherit
      src
      pname
      version
      meta
      passthru
      ;

    sourceRoot = ".";
    nativeBuildInputs = [
      undmg
      makeWrapper
    ];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/Applications
      cp -r *.app $out/Applications/
      makeWrapper "$out/Applications/electron-mail.app/Contents/MacOS/electron-mail" $out/bin/${pname}

      runHook postInstall
    '';
  };
in
if stdenvNoCC.hostPlatform.isDarwin then darwin else linux
