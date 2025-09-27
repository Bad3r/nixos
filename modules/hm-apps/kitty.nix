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
    --config <file>: Launch kitty with an alternate configuration file.
    --session <file>: Restore a saved layout containing tabs and splits on startup.
    +kitten themes: Browse and apply color schemes interactively using the themes kitten.
    --single-instance: Reuse the existing kitty instance, creating new windows within it.
    +kitten ssh <host>: Initiate SSH sessions that inherit kitty’s graphics protocol extensions.

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
