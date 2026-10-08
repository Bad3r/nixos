/*
  Package: websocat
  Description: Command-line client for WebSockets (like netcat/socat).
  Homepage: nil
  Documentation: nil
  Repository: https://github.com/vi/websocat

  Summary:
    * Connects to or serves ws:// and wss:// endpoints from the command line, acting like netcat/curl for WebSockets.
    * Supports socat-style two-endpoint address specifiers (TCP, Unix sockets, exec, TLS) for piping between arbitrary transports.

  Options:
    -s: Run in simple server mode, listening on the given port or addr:port.
    -t: Send outgoing WebSocket messages as text frames.
    -b: Send outgoing WebSocket messages as binary frames.
    -k: Accept invalid TLS certificates and hostnames when connecting over wss://.
    -H: Add a custom HTTP header to the WebSocket upgrade request.
    -E: Close the data transfer direction once the other side reaches EOF.
*/
_:
let
  WebsocatModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.websocat.extended;
    in
    {
      options.programs.websocat.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable websocat.";
        };

        package = lib.mkPackageOption pkgs "websocat" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.websocat = WebsocatModule;
}
