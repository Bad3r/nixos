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
  flake.nixosModules.apps.httpie =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.httpie ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.httpie ];
    };
}
