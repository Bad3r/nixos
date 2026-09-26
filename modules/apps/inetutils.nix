/*
  Package: inetutils
  Description: GNU collection of common networking clients and servers.
  Homepage: https://www.gnu.org/software/inetutils/
  Documentation: https://www.gnu.org/software/inetutils/manual/
  Repository: https://git.savannah.gnu.org/cgit/inetutils.git

  Summary:
    * Provides `traceroute`, `ifconfig`, `telnet`, `ftp`, `tftp`, `talk`, and the r-commands (`rsh`, `rlogin`, `rcp`, `rexec`).
    * Also ships `ping`, `ping6`, `whois`, `hostname`, `dnsdomainname`, and `logger`.

  Options:
    traceroute -I <host>: Probe with ICMP ECHO instead of UDP.
    traceroute -m <num> <host>: Set the maximum hop count (default 64).
    ifconfig -a: Display all interfaces, including those that are down.
    telnet <host> <port>: Open an interactive TCP session for protocol testing.
    ping6 <host>: Send ICMPv6 echo requests.

  Notes:
    * nixpkgs sets `meta.priority = 7`, so in the system profile iputils `ping`, the whois app's `whois`, and util-linux `logger` take precedence over the inetutils builds.
*/
_:
let
  InetutilsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.inetutils.extended;
    in
    {
      options.programs.inetutils.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable inetutils.";
        };

        package = lib.mkPackageOption pkgs "inetutils" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.inetutils = InetutilsModule;
}
