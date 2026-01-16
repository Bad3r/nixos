/*
  Package: firefox
  Description: Mozilla Firefox web browser with security, privacy, and developer tooling features.
  Homepage: https://www.mozilla.org/firefox/
  Documentation: https://support.mozilla.org/
  Repository: https://hg.mozilla.org/mozilla-central/

  Summary:
    * Delivers a multi-process web browser with tracking protection, container tabs, integrated devtools, and broad web standards support.
    * Supports headless automation, dedicated profiles, and enterprise policies for tailored deployments.

  Options:
    --private-window <url>: Open a URL directly in a new private browsing window.
    --ProfileManager: Launch the profile manager to create or select profiles.
    --new-window <url>: Open a new window with the provided URL.
    --headless: Run Firefox without a visible UI for automated testing or printing.
    --safe-mode: Start Firefox with extensions disabled for troubleshooting.

  Example Usage:
    * `firefox https://example.com` — Launch Firefox and navigate to a website.
    * `firefox --profile ~/.mozilla/firefox/work --private-window https://intranet.local` — Use a dedicated profile and private window for sensitive browsing.
    * `firefox --headless --screenshot page.png https://example.com` — Capture a screenshot via the headless renderer.
*/
_:
let
  FirefoxModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.firefox.extended;
    in
    {
      options.programs.firefox.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable firefox.";
        };

        package = lib.mkPackageOption pkgs "firefoxPrivacyFonts" { };
      };

      config = {
        # Overlay unconditional: required for package option default resolution.
        nixpkgs.overlays = [
          (final: prev: {
            # Privacy-focused font set: Arimo, Tinos, Cousine (Croscore fonts)
            firefoxPrivacyFonts =
              let
                # Collect only the fonts we need for fingerprinting resistance
                privacyFonts = final.runCommand "firefox-privacy-fonts" { } ''
                  mkdir -p $out/fonts

                  # Croscore fonts (metrically compatible with Arial, Times, Courier)
                  for f in ${final.google-fonts}/share/fonts/truetype/Arimo*; do
                    ln -s "$f" $out/fonts/
                  done
                  for f in ${final.google-fonts}/share/fonts/truetype/Tinos*; do
                    ln -s "$f" $out/fonts/
                  done
                  for f in ${final.google-fonts}/share/fonts/truetype/Cousine*; do
                    ln -s "$f" $out/fonts/
                  done

                  # STIX Two Math for mathematical content
                  ln -s ${final.stix-two}/share/fonts/opentype/STIXTwoMath-Regular.otf $out/fonts/

                  # Noto Color Emoji
                  ln -s ${final.noto-fonts-color-emoji}/share/fonts/noto/NotoColorEmoji.ttf $out/fonts/
                '';

                # Custom fonts.conf restricting available fonts and setting substitutions
                fontsConf = final.writeText "firefox-privacy-fonts.conf" ''
                  <?xml version="1.0"?>
                  <!DOCTYPE fontconfig SYSTEM "fonts.dtd">
                  <!--
                    Privacy-focused fontconfig for Firefox.
                    Restricts available fonts to a uniform set for fingerprinting resistance.
                  -->
                  <fontconfig>

                    <!-- Font directory: only privacy fonts are available -->
                    <dir>${privacyFonts}/fonts</dir>

                    <!-- Alias substitutions for system UI fonts (must come before generic families) -->
                    <alias binding="same">
                      <family>system-ui</family>
                      <prefer><family>Arimo</family></prefer>
                    </alias>
                    <alias binding="same">
                      <family>-apple-system</family>
                      <prefer><family>Arimo</family></prefer>
                    </alias>
                    <alias binding="same">
                      <family>BlinkMacSystemFont</family>
                      <prefer><family>Arimo</family></prefer>
                    </alias>
                    <alias binding="same">
                      <family>Segoe UI</family>
                      <prefer><family>Arimo</family></prefer>
                    </alias>

                    <!-- Normalize generic family aliases -->
                    <alias binding="same">
                      <family>mono</family>
                      <prefer><family>monospace</family></prefer>
                    </alias>
                    <alias binding="same">
                      <family>sans serif</family>
                      <prefer><family>sans-serif</family></prefer>
                    </alias>
                    <alias binding="same">
                      <family>sans</family>
                      <prefer><family>sans-serif</family></prefer>
                    </alias>

                    <!-- Map generic families to Croscore fonts -->
                    <alias binding="same">
                      <family>sans-serif</family>
                      <prefer><family>Arimo</family></prefer>
                    </alias>
                    <alias binding="same">
                      <family>serif</family>
                      <prefer><family>Tinos</family></prefer>
                    </alias>
                    <alias binding="same">
                      <family>monospace</family>
                      <prefer><family>Cousine</family></prefer>
                    </alias>

                    <!-- Map common web fonts to Croscore equivalents -->
                    <alias binding="same">
                      <family>Arial</family>
                      <prefer><family>Arimo</family></prefer>
                    </alias>
                    <alias binding="same">
                      <family>Helvetica</family>
                      <prefer><family>Arimo</family></prefer>
                    </alias>
                    <alias binding="same">
                      <family>Helvetica Neue</family>
                      <prefer><family>Arimo</family></prefer>
                    </alias>
                    <alias binding="same">
                      <family>Times New Roman</family>
                      <prefer><family>Tinos</family></prefer>
                    </alias>
                    <alias binding="same">
                      <family>Times</family>
                      <prefer><family>Tinos</family></prefer>
                    </alias>
                    <alias binding="same">
                      <family>Courier New</family>
                      <prefer><family>Cousine</family></prefer>
                    </alias>
                    <alias binding="same">
                      <family>Courier</family>
                      <prefer><family>Cousine</family></prefer>
                    </alias>

                    <!-- Map emoji requests to Noto Color Emoji -->
                    <alias binding="same">
                      <family>emoji</family>
                      <prefer><family>Noto Color Emoji</family></prefer>
                    </alias>
                    <alias binding="same">
                      <family>Apple Color Emoji</family>
                      <prefer><family>Noto Color Emoji</family></prefer>
                    </alias>

                    <!-- Font cache directory -->
                    <cachedir prefix="xdg">fontconfig</cachedir>

                    <config>
                      <rescan><int>30</int></rescan>
                    </config>

                    <!-- Standardize rendering settings -->
                    <match target="pattern">
                      <edit name="antialias" mode="assign"><bool>true</bool></edit>
                      <edit name="autohint" mode="assign"><bool>false</bool></edit>
                      <edit name="hinting" mode="assign"><bool>true</bool></edit>
                      <edit name="hintstyle" mode="assign"><const>hintfull</const></edit>
                      <edit name="lcdfilter" mode="assign"><const>lcddefault</const></edit>
                      <edit name="rgba" mode="assign"><const>none</const></edit>
                    </match>

                  </fontconfig>
                '';

                mkWrapped =
                  firefox:
                  let
                    drv =
                      final.runCommand "firefox-privacy-fonts-${firefox.version}"
                        {
                          nativeBuildInputs = [ final.makeWrapper ];
                          inherit (firefox) meta;
                        }
                        ''
                          mkdir -p $out/bin
                          ln -s ${firefox}/share $out/share
                          ln -s ${firefox}/lib $out/lib
                          makeWrapper ${firefox}/bin/firefox $out/bin/firefox \
                            --set FONTCONFIG_FILE "${fontsConf}"
                        '';
                  in
                  drv
                  // {
                    # Preserve Firefox-specific attributes for Home Manager compatibility
                    inherit (firefox) version;
                    passthru = firefox.passthru // {
                      unwrapped = firefox.passthru.unwrapped or firefox;
                    };
                    override = args: mkWrapped (firefox.override args);
                  };
              in
              mkWrapped prev.firefox;
          })
        ];

        environment.systemPackages = lib.mkIf cfg.enable [ cfg.package ];
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [
    "firefox-bin"
    "firefox-bin-unwrapped"
  ];

  flake.nixosModules.apps.firefox = FirefoxModule;
}
