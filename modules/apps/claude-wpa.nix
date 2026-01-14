/*
  Package: claude-wpa
  Description: Claude AI Web Progressive App using ungoogled-chromium.
  Homepage: https://claude.ai
  Documentation: https://docs.anthropic.com/

  Summary:
    * Launches Claude AI website in a minimal, app-like Chromium window without browser chrome.
    * Uses an isolated profile directory following XDG Base Directory specification.
    * External links automatically open in the default system browser.
    * Supports custom protocol handler: claude-wpa://path opens https://claude.ai/path

  Chromium Flags (enabled by default):
    --force-dark-mode: Forces dark color scheme for Chromium UI elements.
    --enable-features=OverlayScrollbar: Uses thin overlay scrollbars for a cleaner look.
    --disable-features=OverscrollHistoryNavigation: Prevents accidental back/forward swipe gestures.
    --disable-background-networking: Reduces background network activity.
    --disable-client-side-phishing-detection: Disables phishing detection for privacy.

  Protocol Handler:
    URLs like claude-wpa://chat/abc123 will open https://claude.ai/chat/abc123
*/
_:
let
  ClaudeWpaModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."claude-wpa".extended;

      # Build the customized package with module options
      customizedPackage = cfg.package.override {
        extraExtensionPaths = cfg.extensions;
        inherit (cfg) extraFlags;
        profileName = cfg.profileDirectory;
      };
    in
    {
      options.programs.claude-wpa.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable claude-wpa.";
          example = true;
        };

        package = lib.mkPackageOption pkgs "claude-wpa" {
          example = lib.literalExpression ''
            pkgs.claude-wpa.override {
              extraFlags = [ "--start-maximized" ];
            }
          '';
        };

        extensions = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Chromium extension paths to load via --load-extension flag.
            Paths should be strings pointing to unpacked extension directories.
          '';
          example = lib.literalExpression ''
            [
              "/path/to/unpacked/extension"
              "''${pkgs.some-extension}"
            ]
          '';
        };

        extraFlags = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Additional command-line flags to pass to ungoogled-chromium.
            These are appended to the default flags.
          '';
          example = lib.literalExpression ''
            [
              "--start-maximized"
              "--enable-features=VaapiVideoDecoder"
              "--disable-gpu-compositing"
            ]
          '';
        };

        profileDirectory = lib.mkOption {
          type = lib.types.str;
          default = "claude-wpa";
          description = ''
            Name of the profile directory under XDG_DATA_HOME.
            The full path will be: ''${XDG_DATA_HOME:-$HOME/.local/share}/<profileDirectory>
          '';
          example = "claude-wpa-work";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ customizedPackage ];
      };
    };
in
{
  flake.nixosModules.apps.claude-wpa = ClaudeWpaModule;
}
