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
*/
_:
let
  WeztermModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.wezterm.extended;
    in
    {
      options.programs.wezterm.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable wezterm.";
        };

        package = lib.mkPackageOption pkgs "wezterm" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.wezterm = WeztermModule;
}
