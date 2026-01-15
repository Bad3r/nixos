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

        package = lib.mkPackageOption pkgs "firefoxWithTorFonts" { };
      };

      config = {
        # Overlay unconditional: required for package option default resolution.
        # tor-browser is a build-time dependency only (fonts.conf path).
        nixpkgs.overlays = [
          (final: prev: {
            # Firefox with Tor Browser's uniform font set (Arimo, Tinos, Cousine, Noto)
            firefoxWithTorFonts =
              let
                torBrowserFontsConf = "${final.tor-browser}/share/tor-browser/fonts/fonts.conf";
                mkWrapped =
                  firefox:
                  let
                    drv =
                      final.runCommand "firefox-tor-fonts-${firefox.version}"
                        {
                          nativeBuildInputs = [ final.makeWrapper ];
                          inherit (firefox) meta;
                        }
                        ''
                          mkdir -p $out/bin
                          ln -s ${firefox}/share $out/share
                          ln -s ${firefox}/lib $out/lib
                          makeWrapper ${firefox}/bin/firefox $out/bin/firefox \
                            --set FONTCONFIG_FILE "${torBrowserFontsConf}"
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
