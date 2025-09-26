/*
  Package: alacritty
  Description: GPU-accelerated cross-platform terminal emulator focused on speed and simplicity.
  Homepage: https://alacritty.org/
  Documentation: https://alacritty.org/config-alacritty.html
  Repository: https://github.com/alacritty/alacritty

  Summary:
    * Renders terminal sessions through OpenGL for low-latency text, ligatures, and emoji on Linux, macOS, Windows, and BSD.
    * Integrates tightly with external tools—IPC via `alacritty msg`, live config reloads, and shell key bindings—while avoiding built-in tabs or splits.

  Options:
    alacritty --config-file <path>: Launch with an alternate TOML configuration file.
    alacritty --hold: Keep the window open after the child process exits.
    alacritty --embed <window-id>: Reparent the terminal into an existing X11 window.
    alacritty --option key=value: Override configuration fields from the CLI.
    alacritty msg create-window: Spawn an additional window in the running daemon.

  Example Usage:
    * `alacritty` — Start a fresh terminal using the default configuration file.
    * `alacritty --config-file ~/.config/alacritty/presentation.toml` — Open a profile tailored for presentations.
    * `alacritty msg create-window -o 'window.opacity=0.9'` — Ask the running instance to open a translucent window.
*/

{
  flake.homeManagerModules.apps.alacritty =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.alacritty ];
    };
}
