/*
  Package: kagi-search
  Description: Search Kagi with the session in browser-fetch's cookie jar.
  Homepage: https://github.com/Bad3r/nixos
  Documentation: https://github.com/Bad3r/nixos/blob/main/docs/apps/kagi-search/README.md
  Repository: https://github.com/Bad3r/nixos

  Summary:
    * Sends the kagi_session cookie of browser-fetch's Camoufox jar through browser-fetch's curl-impersonate, and writes back what Kagi sets.
    * Sign in once with `browser-fetch login https://kagi.com`.
    * Prints Kagi's first results page as numbered hits or JSON.
    * kagi-search-webrun answers Codex's web.run tool in place of OpenAI's search service.

  Options:
    --json: Print JSON instead of text.
    --limit N: Print at most N hits (default 10; 0 prints every hit).
    --allow DOMAIN / --block DOMAIN: Keep or drop hits by domain; repeatable.
*/
_:
let
  KagiSearchModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.kagi-search.extended;
    in
    {
      options.programs.kagi-search.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable the kagi-search command line.";
        };

        package = lib.mkPackageOption pkgs "kagi-search" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
        # The session comes from browser-fetch's cookie jar, which its login fills.
        programs.browser-fetch.extended.enable = lib.mkOverride 1050 true;
      };
    };
in
{
  flake.nixosModules.apps.kagi-search = KagiSearchModule;

  perSystem =
    { pkgs, ... }:
    {
      # run the unit tests in CI
      checks."apps/kagi-search" =
        pkgs.runCommand "kagi-search-check"
          {
            passthru.runtimeCheck = true;
            package = pkgs.callPackage ../../packages/kagi-search { };
          }
          ''
            test -x "$package/bin/kagi-search"
            touch "$out"
          '';
    };
}
