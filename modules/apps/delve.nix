/*
  Package: delve
  Description: Debugger for the Go programming language.
  Homepage: https://github.com/go-delve/delve
  Documentation: https://github.com/go-delve/delve/tree/master/Documentation/cli
  Repository: https://github.com/go-delve/delve

  Summary:
    * Offers interactive and headless debugging for Go binaries, integrating with editors and IDEs via the DAP protocol.
    * Supports breakpoints, goroutine inspection, expression evaluation, and recording of execution traces.

  Example Usage:
    * `dlv debug ./cmd/api` — Build and start debugging the binary produced from `./cmd/api`.
    * `dlv attach $(pgrep myservice)` — Attach to a running Go process for live inspection.
*/

{
  flake.nixosModules.apps.delve =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.delve ];
    };

}
