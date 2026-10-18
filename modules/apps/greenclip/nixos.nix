/*
  Package: greenclip
  Description: Simple clipboard manager to be integrated with rofi.
  Homepage: https://github.com/erebe/greenclip
  Documentation: https://github.com/erebe/greenclip#readme
  Repository: https://github.com/erebe/greenclip

  Summary:
    * Tracks clipboard history for quick switching between selections via rofi, dmenu, or fzf.
    * Supports static history entries, primary selection merging, application blacklisting, and small image storage.

  Options:
    daemon: Start the clipboard monitoring daemon (required for history capture).
    print: Output clipboard history for rofi/dmenu consumption.
    clear: Clear the clipboard history (daemon must be stopped first).

  Example Usage:
    * `greenclip daemon &` -- Start the daemon in the background.
    * `rofi -modi "clipboard:greenclip print" -show clipboard` -- Launch rofi clipboard selector.
    * `pkill greenclip && greenclip clear && greenclip daemon &` -- Clear history and restart.
*/
_:
let
  GreenclipModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.greenclip.extended;
    in
    {
      options.programs.greenclip.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable greenclip.";
        };

        package = lib.mkPackageOption pkgs.haskellPackages "greenclip" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.greenclip = GreenclipModule;
}
