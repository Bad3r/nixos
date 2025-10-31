/*
  Package: httpie
  Description: Human-friendly command line HTTP client for testing and debugging APIs.
  Homepage: https://httpie.io/cli
  Documentation: https://httpie.io/docs/cli
  Repository: https://github.com/httpie/httpie

  Summary:
    * Provides expressive request syntax with colorized, formatted output for API responses.
    * Supports sessions, plugins, and downloads to streamline repetitive HTTP workflows.

  Options:
    -v: Show both the request and response for detailed debugging.
    --json: Default to JSON payload handling with appropriate headers.
    --form: Submit data as application/x-www-form-urlencoded form fields.
    --session=NAME: Persist cookies and headers between related requests.
    --check-status: Exit with error codes that mirror HTTP status classes.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  HttpieModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.httpie.extended;
    in
    {
      options.programs.httpie.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable httpie.";
        };

        package = lib.mkPackageOption pkgs "httpie" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.httpie = HttpieModule;
}
