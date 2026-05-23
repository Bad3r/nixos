/*
  Package: lychee
  Description: Fast, async, stream-based link checker written in Rust.
  Homepage: https://lychee.cli.rs/
  Documentation: https://lychee.cli.rs/guides/cli/
  Repository: https://github.com/lycheeverse/lychee

  Summary:
    * Checks broken URLs and mail addresses in Markdown, HTML, reStructuredText, websites, and plain text inputs.
    * Supports CI-friendly local and remote link validation with caching, exclusions, and structured output.

  Options:
    -c, --config: Load a lychee.toml configuration file.
    --offline: Check local files only and block network requests.
    --exclude: Exclude URLs and mail addresses using regular expressions.
    -f, --format: Select compact, detailed, JSON, Markdown, or raw report output.
    --github-token: Use a GitHub API token, or GITHUB_TOKEN, for GitHub link checks.
    --require-https: Treat HTTP links as errors when HTTPS is available.
*/
_:
let
  LycheeModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.lychee.extended;
    in
    {
      options.programs.lychee.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable lychee.";
        };

        package = lib.mkPackageOption pkgs "lychee" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.lychee = LycheeModule;
}
