/*
  Package: socat
  Description: Utility for bidirectional data transfer between two independent data channels.
  Homepage: http://www.dest-unreach.org/socat/
  Documentation: http://www.dest-unreach.org/socat/

  Summary:
    * Bridges files, pipes, terminals, sockets, and TLS endpoints through a single process.
    * Helps debug network services, protocol translations, and local tunnel plumbing.

  Options:
    -d: Increase logging verbosity for connection setup and teardown.
    -d -d: Emit more detailed debug output about both addresses and transfers.
    TCP-LISTEN:PORT,reuseaddr,fork: Accept TCP connections and forward each client to a target address.
*/
_:
let
  SocatModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.socat.extended;
    in
    {
      options.programs.socat.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable socat.";
        };

        package = lib.mkPackageOption pkgs "socat" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.socat = SocatModule;
}
