/*
  Package: dmenu
  Description: Generic, highly customizable, and efficient X11 menu for launching commands and selecting items.
  Homepage: https://tools.suckless.org/dmenu/
  Documentation: https://tools.suckless.org/dmenu/
  Repository: https://git.suckless.org/dmenu

  Summary:
    * Provides a minimal stdin-driven menu and launcher designed to integrate with scripts and window manager workflows.
    * Supports vertical lists, custom prompts, and case-insensitive matching through command-line flags.

  Options:
    -p <prompt>: Set a custom prompt string displayed before the input field.
    -l <lines>: Use a vertical list with the specified number of lines.
    -b: Position the menu at the bottom of the screen instead of the top.
    -i: Enable case-insensitive item matching.
    -fn <font>: Override the font used to render menu entries.
*/
_:
let
  DmenuModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.dmenu.extended;
    in
    {
      options.programs.dmenu.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable dmenu.";
        };

        package = lib.mkPackageOption pkgs "dmenu" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.dmenu = DmenuModule;
}
