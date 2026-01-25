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
    * `dlv debug ./cmd/api` -- Build and start debugging the binary produced from `./cmd/api`.
    * `dlv attach $(pgrep myservice)` -- Attach to a running Go process for live inspection.
*/
_:
let
  DelveModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.delve.extended;
    in
    {
      options.programs.delve.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable delve.";
        };

        package = lib.mkPackageOption pkgs "delve" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.delve = DelveModule;
}
