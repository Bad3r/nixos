/*
  Package: nikto
  Description: Web server scanner for dangerous files, outdated components, and misconfigurations.
  Homepage: https://cirt.net/Nikto2
  Documentation: https://github.com/sullo/nikto/wiki
  Repository: https://github.com/sullo/nikto

  Summary:
    * Scans web servers for thousands of potentially dangerous files/CGIs, outdated server versions, and version-specific problems.
    * Checks server configuration items such as index files, permitted HTTP methods, and TLS/certificate issues.

  Options:
    -h, -host <target>: Target host, IP, URL, or file of hosts to scan.
    -p, -port <ports>: Port(s) to scan (default 80).
    -ssl: Force a TLS/SSL connection.
    -Tuning <value>: Restrict tests to the selected scan-category classes.
    -Format <value>: Report output format (csv, htm, json, txt, xml).
    -output <file>: Write the report to the specified file.
    -Plugins <value>: Select which plugins to run.

  Notes:
    * Prefer nuclei for template-based vulnerability coverage: its actively updated
      corpus (nuclei-templates) supersedes most of nikto's checks. Keep nikto for
      its built-in default-file and outdated-server signature scans and quick,
      zero-config server triage.
*/
_:
let
  NiktoModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.nikto.extended;
    in
    {
      options.programs.nikto.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable nikto.";
        };

        package = lib.mkPackageOption pkgs "nikto" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.nikto = NiktoModule;
}
