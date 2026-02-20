/*
  Package: playwright
  Description: Web testing and browser automation framework with a unified API for Chromium, Firefox, and WebKit.
  Homepage: https://playwright.dev
  Documentation: https://playwright.dev/docs/browsers
  Repository: https://github.com/microsoft/playwright

  Summary:
    * Provides the Playwright CLI for running tests, generating scripts, and interactive browser automation.
    * Wraps CLI browser-launch commands to prefer system-installed Google Chrome or Chromium.
    * Uses a dedicated profile directory for automation sessions to avoid polluting daily browser profiles.

  Options:
    test: Run end-to-end tests with Playwright Test.
    open: Launch an interactive browser session for manual inspection.
    codegen: Record interactions and generate Playwright scripts.
    --channel <channel>: Choose a Chromium-based browser channel such as `chrome`.
    --user-data-dir <directory>: Persist session data in a dedicated profile path.

  Notes:
    * Uses `playwright-test` because it provides the `playwright` CLI binary.
    * For `test`, Playwright channel/executable selection is still controlled by `playwright.config.*`.
*/
_:
let
  PlaywrightModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.playwright.extended;
      browserIsChromium = cfg.browser == "chromium";

      browserExecutable =
        if cfg.browser == "google-chrome" then lib.getExe pkgs.google-chrome else lib.getExe pkgs.chromium;

      wrappedPlaywright = pkgs.writeShellApplication {
        name = "playwright";
        runtimeInputs = [
          pkgs.coreutils
          cfg.package
        ];
        text = /* bash */ ''
          set -euo pipefail

          playwright_bin="${lib.getExe cfg.package}"

          command_name=""
          if [ "$#" -gt 0 ]; then
            command_name="$1"
            shift
          fi

          args=("$@")
          extra_args=()

          has_flag() {
            local flag="$1"
            for arg in "''${args[@]}"; do
              if [ "$arg" = "$flag" ]; then
                return 0
              fi
              case "$arg" in
                "$flag"=*)
                  return 0
                  ;;
              esac
            done
            return 1
          }

          ${lib.optionalString browserIsChromium ''
            export PWTEST_CLI_EXECUTABLE_PATH="${browserExecutable}"
          ''}

          case "$command_name" in
            open|codegen|pdf|screenshot)
              if ! has_flag "--browser" && ! has_flag "-b"; then
                extra_args+=("--browser=chromium")
              fi

              ${lib.optionalString (cfg.browser == "google-chrome") ''
                if ! has_flag "--channel"; then
                  extra_args+=("--channel=chrome")
                fi
              ''}

              ${lib.optionalString cfg.useDedicatedProfile ''
                if ! has_flag "--user-data-dir"; then
                  profile_dir="''${XDG_CACHE_HOME:-$HOME/.cache}/${cfg.profileDirectory}"
                  mkdir -p "$profile_dir"
                  extra_args+=("--user-data-dir=$profile_dir")
                fi
              ''}
              ;;
          esac

          if [ -n "$command_name" ]; then
            exec "$playwright_bin" "$command_name" "''${extra_args[@]}" "''${args[@]}"
          fi

          exec "$playwright_bin" "''${args[@]}"
        '';
      };
    in
    {
      options.programs.playwright.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable playwright.";
        };

        package = lib.mkPackageOption pkgs "playwright-test" { };

        browser = lib.mkOption {
          type = lib.types.enum [
            "google-chrome"
            "chromium"
          ];
          default = "google-chrome";
          description = ''
            Browser backend for Playwright CLI browser-launch commands.
            `google-chrome` uses the Chrome channel; `chromium` uses the system
            Chromium binary via `PWTEST_CLI_EXECUTABLE_PATH`.
          '';
        };

        useDedicatedProfile = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Whether to pass `--user-data-dir` for browser-launch commands.
            This keeps automation data in an isolated profile.
          '';
        };

        profileDirectory = lib.mkOption {
          type = lib.types.str;
          default = "ms-playwright/playwright-cli-profile";
          description = ''
            Relative profile directory under ''${XDG_CACHE_HOME:-$HOME/.cache}
            used when `useDedicatedProfile` is enabled.
          '';
          example = "ms-playwright/playwright-work-profile";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ wrappedPlaywright ];
      };
    };
in
{
  flake.nixosModules.apps.playwright = PlaywrightModule;
}
