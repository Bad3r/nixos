/*
  Package: browser-fetch
  Description: Fetch a web page with a browser's TLS fingerprint and LibreWolf's cookies.
  Homepage: https://github.com/Bad3r/nixos
  Documentation: https://github.com/Bad3r/nixos/blob/main/docs/apps/browser-fetch/README.md
  Repository: https://github.com/Bad3r/nixos

  Summary:
    * Requests the page through curl-impersonate's Firefox profile with the cookies of LibreWolf's default profile.
    * Renders bot challenges and script-built pages in Camoufox on a private display, with one persistent profile and fingerprint.
    * Prints the page as Markdown, or the WebFetch record as JSON.

  Options:
    --json: Print the WebFetch record as JSON instead of the page text.
    --offset N / --max-chars N: Print the text from code unit N, at most N code units.
    --browser auto|never|always: When to render in Camoufox (default auto).
    --deadline SECONDS: How long the whole fetch may take (default 240).
    --no-cookies: Send no LibreWolf cookies.
*/
_:
let
  BrowserFetchModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.browser-fetch.extended;
    in
    {
      options.programs.browser-fetch.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable the browser-fetch command line.";
        };

        package = lib.mkPackageOption pkgs "browser-fetch" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
        # The cookies come from LibreWolf.
        programs.librewolf.extended.enable = lib.mkOverride 1050 true;
      };
    };
in
{
  flake.nixosModules.apps.browser-fetch = BrowserFetchModule;

  perSystem =
    { pkgs, ... }:
    {
      # run the unit tests in CI
      checks."apps/browser-fetch" =
        pkgs.runCommand "browser-fetch-check"
          {
            passthru.runtimeCheck = true;
            package = pkgs.callPackage ../../packages/browser-fetch { };
          }
          ''
            test -x "$package/bin/browser-fetch"
            touch "$out"
          '';
    };
}
