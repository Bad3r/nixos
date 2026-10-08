/*
  Package: dnsutils
  Description: DNS lookup and update utilities from ISC BIND, including dig, delv, nslookup, and nsupdate.
  Homepage: https://www.isc.org/bind/
  Documentation: https://bind9.readthedocs.io/en/latest/manpages.html
  Repository: https://gitlab.isc.org/isc-projects/bind9

  Summary:
    * `dig` queries name servers for any record type and prints the full response, while `delv` performs DNSSEC-validating lookups.
    * `nslookup` runs interactive or one-shot queries, and `nsupdate` submits RFC 2136 dynamic DNS updates.

  Options:
    dig @<server> <name>: Query a specific name server instead of the system resolver.
    dig -t <type> <name>: Query one record type, such as `AAAA`, `MX`, or `TXT`.
    dig -x <addr>: Run a reverse lookup for an IPv4 or IPv6 address.
    dig +short <name>: Print only the answer data.
    dig +trace <name>: Follow the delegation from the root servers down to the answer.
    delv <name>: Resolve with DNSSEC validation and report the validation result.

  Notes:
    * `dnsutils` is the `bind.dnsutils` output; `host` ships in `bind.host`, which NixOS installs through `environment.corePackages`.
*/
_:
let
  DnsutilsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.dnsutils.extended;
    in
    {
      options.programs.dnsutils.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable dnsutils.";
        };

        package = lib.mkPackageOption pkgs "dnsutils" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.dnsutils = DnsutilsModule;
}
