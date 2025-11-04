/*
  Package: wezterm
  Description: GPU-accelerated cross-platform terminal emulator and multiplexer written in Rust.
  Homepage: https://wezterm.org/
  Documentation: https://wezfurlong.org/wezterm/
  Repository: https://github.com/wez/wezterm

  Summary:
    * Combines a terminal emulator, multiplexer, and SSH client with OpenGL/Metal acceleration, ligatures, and extensive configuration via Lua.
    * Provides multiplexing tabs/panes, font fallback, SSH multiplexer with `wezterm ssh`, and nightly features like background tasks.

  Options:
    --config-file <path>: Launch wezterm with an alternate configuration file.
    --cwd <path>: Specify the working directory for new tabs via `wezterm start --cwd`.
    --ssh-domain <name>: Target a configured SSH domain when spawning remote tabs.
    --log-level <trace|debug|info>: Adjust diagnostic verbosity for troubleshooting.

  Example Usage:
    * `wezterm` — Start the GPU-accelerated terminal and multiplexer.
    * `wezterm start --cwd ~/projects` — Open a new tab ready to work in a project directory.
    * `wezterm ssh prod` — Launch an SSH session that inherits wezterm’s key handling and multiplexing.
*/

{
  flake.homeManagerModules.apps.wezterm =
    { lib, ... }:
    {
      # Enable Stylix theming for wezterm
      stylix.targets.wezterm.enable = lib.mkDefault true;

      programs.wezterm.enable = true;
    };
}
