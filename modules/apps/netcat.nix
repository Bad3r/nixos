/*
  Package: netcat
  Description: Utility which reads and writes data across network connections, using the LibreSSL implementation.
  Homepage: https://www.libressl.org
  Documentation: https://www.libressl.org
  Repository: https://github.com/libressl/portable

  Summary:
    * Opens raw TCP or UDP connections for debugging, banner grabbing, and simple protocol testing.
    * Works as both a client and a listener for piping data between local stdin/stdout and sockets.

  Options:
    -l: Listen for an incoming connection instead of initiating one.
    -k: Keep the listener open for multiple inbound connections.
    -u: Use UDP instead of TCP.
*/
_:
let
  NetcatModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.netcat.extended;
    in
    {
      options.programs.netcat.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable netcat.";
        };

        package = lib.mkPackageOption pkgs "netcat" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.netcat = NetcatModule;
}
