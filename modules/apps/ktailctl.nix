/*
  Package: ktailctl
  Description: GUI to monitor and manage Tailscale on the Linux desktop.
  Homepage: https://github.com/f-koehler/KTailctl
  Documentation: https://github.com/f-koehler/KTailctl#readme
  Repository: https://github.com/f-koehler/KTailctl

  Summary:
    * Lists tailnet peers and their addresses, and switches accounts and exit nodes.
    * Toggles Tailscale and edits its preferences from the system tray.

  Notes:
    * Changing preferences needs `tailscale up --operator=$USER` first.
*/
_:
let
  KtailctlModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.ktailctl.extended;
    in
    {
      options.programs.ktailctl.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable ktailctl.";
        };

        package = lib.mkPackageOption pkgs "ktailctl" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.ktailctl = KtailctlModule;
}
