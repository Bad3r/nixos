/*
  Package: torsocks
  Description: Wrapper to safely torify applications by redirecting network traffic through Tor SOCKS proxy.
  Homepage: https://github.com/dgoulet/torsocks/
  Documentation: https://gitlab.torproject.org/tpo/core/torsocks/-/wikis/home
  Repository: https://gitlab.torproject.org/tpo/core/torsocks

  Summary:
    * Transparently routes TCP connections through Tor using LD_PRELOAD to intercept network calls.
    * Prevents DNS leaks by forcing DNS resolution through Tor's SOCKS interface.

  Options:
    torsocks --shell: Start a shell where all commands are automatically torified.
    torsocks -i, --isolate: Isolate each connection on its own Tor circuit.
    torsocks -u, --user NAME: Username for SOCKS5 authentication.
    torsocks -P, --port PORT: Use the Tor SOCKS proxy on a custom port (default: 9050).
*/
_:
let
  TorsocksModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.torsocks.extended;
    in
    {
      options.programs.torsocks.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable torsocks.";
        };

        package = lib.mkPackageOption pkgs "torsocks" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

        # Configure torsocks to use Tor on localhost:9050
        environment.etc."torsocks.conf".text = ''
          # Tor SOCKS proxy
          TorAddress 127.0.0.1
          TorPort 9050

          # Tor DNS
          OnionAddrRange 127.42.42.0/24

          # Allow inbound connections (for services)
          AllowInbound 1

          # Allow outbound connections
          AllowOutboundLocalhost 1
        '';
      };
    };
in
{
  flake.nixosModules.apps.torsocks = TorsocksModule;
}
