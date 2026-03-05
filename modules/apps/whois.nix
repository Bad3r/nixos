/*
  Package: whois
  Description: Command-line client for WHOIS directory queries across domain, IP, and related network object types.
  Homepage: https://github.com/rfc1036/whois
  Documentation: https://manpages.debian.org/bookworm/whois/whois.1.en.html
  Repository: https://github.com/rfc1036/whois

  Summary:
    * Resolves objects via the WHOIS (RFC 3912) protocol with automatic server selection where supported.
    * Includes the companion `mkpasswd` utility from the same upstream package set.

  Options:
    -h, --host=HOST: Query a specific WHOIS server directly.
    -p, --port=PORT: Use a specific TCP port when connecting.
    -q KEYWORD: Query for supported keyword and return matching information.
    -t TYPE: Show query/help output for a WHOIS object type.
    -v TYPE: Display verbose details for a WHOIS object type.
    -H: Omit legal disclaimers in the server response.
    --version: Show version and licensing details.
    --help: Show built-in usage text.
*/
_:
let
  WhoisModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.whois.extended;
    in
    {
      options.programs.whois.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable whois.";
        };

        package = lib.mkPackageOption pkgs "whois" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.whois = WhoisModule;
}
