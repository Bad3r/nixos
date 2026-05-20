/*
  Package: lazyjournal
  Description: TUI for journalctl, file system logs, as well as Docker and Podman containers.
  Homepage: https://github.com/Lifailon/lazyjournal
  Documentation: https://github.com/Lifailon/lazyjournal
  Repository: https://github.com/Lifailon/lazyjournal

  Summary:
    * Browses systemd journal entries, filesystem logs, and container logs from one terminal UI.
    * Filters and searches logs interactively for local service diagnostics.
    * Supports Docker and Podman container log inspection alongside host logs.
*/
_:
let
  LazyjournalModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.lazyjournal.extended;
    in
    {
      options.programs.lazyjournal.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable lazyjournal.";
        };

        package = lib.mkPackageOption pkgs "lazyjournal" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.lazyjournal = LazyjournalModule;
}
