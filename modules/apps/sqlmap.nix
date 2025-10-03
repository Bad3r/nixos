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

  Example Usage:
    * `sqlmap -u "https://example.com/item.php?id=1" --risk=3 --level=5` — Perform thorough testing on a GET parameter.
    * `sqlmap -r request.txt --dbs` — Enumerate databases from a saved authenticated request.
    * `sqlmap -u <url> --os-shell` — Attempt to spawn an interactive OS shell where supported.
*/

{
  flake.nixosModules.apps.sqlmap =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.sqlmap ];
    };

}
