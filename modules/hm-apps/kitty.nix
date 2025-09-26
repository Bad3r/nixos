/*
  Package: kitty
  Description: GPU-accelerated cross-platform terminal emulator with tiling, tabs, and remote control.
  Homepage: https://sw.kovidgoyal.net/kitty/
  Documentation: https://sw.kovidgoyal.net/kitty/conf/
  Repository: https://github.com/kovidgoyal/kitty

  Summary:
    * Renders text via OpenGL for high-performance terminal sessions with ligatures, Unicode support, and graphics protocol features.
    * Provides layout splits, session management, kitten subcommands, and remote control sockets for automation.

  Options:
    kitty --config <file>: Launch with a custom configuration file.
    kitty --session <file>: Restore a saved layout with tabs and splits.
    kitty +kitten themes: Browse and apply color schemes interactively.
    kitty @ <command>: Send remote control commands to a running kitty instance.
    kitty +kitten ssh <host>: Start an SSH session leveraging kitty’s graphics protocol.

  Example Usage:
    * `kitty` — Start the terminal emulator with the default configuration.
    * `kitty --config ~/.config/kitty/presentation.conf` — Apply an alternate profile on launch.
    * `kitty @ set-font-size 14` — Adjust the font size of a running instance via remote control.
*/

{
  flake.homeManagerModules.apps.kitty = _: {
    programs.kitty.enable = true;
  };
}
