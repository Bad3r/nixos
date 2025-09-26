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
    wezterm: Launch the terminal GUI with the default configuration.
    wezterm start --cwd <path>: Open a new tab rooted at a specific directory.
    wezterm ssh <target>: Connect to remote hosts using the built-in SSH client.
    wezterm ls-fonts: Inspect font fallback and shaping support.
    wezterm cli set-tab-title <title>: Control tab titles programmatically.

  Example Usage:
    * `wezterm` — Start the GPU-accelerated terminal and multiplexer.
    * `wezterm start --cwd ~/projects` — Open a new tab ready to work in a project directory.
    * `wezterm ssh prod` — Launch an SSH session that inherits wezterm’s key handling and multiplexing.
*/

{
  flake.homeManagerModules.apps.wezterm = _: {
    programs.wezterm = {
      enable = true;
    };
  };
}
