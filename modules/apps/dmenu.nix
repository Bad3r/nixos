/*
  Package: dmenu
  Description: Generic, highly customizable, and efficient X11 menu for launching commands and selecting items.
  Homepage: https://tools.suckless.org/dmenu/
  Documentation: https://tools.suckless.org/dmenu/
  Repository: https://git.suckless.org/dmenu

  Summary:
    * Provides a minimal stdin-driven menu and launcher designed to integrate with scripts and window manager workflows.
    * Supports fuzzy matching, vertical lists, and prompt customization through command-line flags and configuration patches.

  Options:
    -p <prompt>: Set a custom prompt string displayed before the input field.
    -l <lines>: Use a vertical list with the specified number of lines.
    -b: Position the menu at the bottom of the screen instead of the top.
    -i: Enable case-insensitive item matching.
    -fn <font>: Override the font used to render menu entries.

  Example Usage:
    * `dmenu_run` — Launch dmenu to execute commands found on your `$PATH`.
    * `ls | dmenu -p "Open file:"` — Select a file from the current directory and print the choice to stdout.
    * `printf 'yes\nno' | dmenu -i -l 2` — Present a two-line selection, matching case-insensitively.
*/

{
  flake.nixosModules.apps.dmenu =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.dmenu ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.dmenu ];
    };
}
