/*
  Package: sqlmap
  Description: Automated SQL injection and database takeover tool.
  Homepage: https://sqlmap.org/
  Documentation: https://github.com/sqlmapproject/sqlmap/wiki
  Repository: https://github.com/sqlmapproject/sqlmap

  Summary:
    * Detects and exploits SQL injection flaws across numerous databases with extensive tamper scripts.
    * Supports database fingerprinting, data extraction, OS command execution, and privilege escalation.

  Options:
    sqlmap -u <url> --batch: Run non-interactive detection using defaults.
    sqlmap -r <request.txt>: Load a captured HTTP request for testing.
    sqlmap -u <url> --dump-all: Dump entire database contents when possible.
*/
_:
let
  SqlmapModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.sqlmap.extended;
    in
    {
      options.programs.sqlmap.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable sqlmap.";
        };

        package = lib.mkPackageOption pkgs "sqlmap" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.sqlmap = SqlmapModule;
}
