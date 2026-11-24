/*
  Package: delve
  Description: Debugger for the Go programming language.
  Homepage: https://github.com/go-delve/delve
  Documentation: https://github.com/go-delve/delve/tree/master/Documentation/cli
  Repository: https://github.com/go-delve/delve

  Summary:
    * Offers interactive and headless debugging for Go binaries, integrating with editors and IDEs via the DAP protocol.
    * Supports breakpoints, goroutine inspection, expression evaluation, and recording of execution traces.

  Notes:
    * A `NOPASSWD` sudo-rs rule lets `wheel` users run `dlv`, `dlv-dap` as root, which attaches to processes that `kernel.yama.ptrace_scope = 1` shields from the owner.
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

        security.sudo-rs.extraRules = [
          {
            commands = [
              {
                command = "${cfg.package}/bin/dlv";
                options = [ "NOPASSWD" ];
              }
              {
                command = "${cfg.package}/bin/dlv-dap";
                options = [ "NOPASSWD" ];
              }
            ];
            groups = [ "wheel" ];
          }
        ];
      };
    };
in
{
  flake.nixosModules.apps.delve = DelveModule;
}
