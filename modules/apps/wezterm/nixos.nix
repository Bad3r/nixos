/*
  Package: wezterm
  Description: GPU-accelerated cross-platform terminal emulator and multiplexer written in Rust.
  Homepage: https://wezterm.org/
  Documentation: https://wezfurlong.org/wezterm/
  Repository: https://github.com/wezterm/wezterm

  Summary:
    * Terminal emulator, multiplexer, and SSH client with GPU rendering, ligatures, and Lua configuration.
    * Multiplexes tabs and panes locally or over `wezterm ssh`.

  Options:
    --config-file <path>: Use an alternate configuration file.
    --cwd <path>: Set the working directory for `wezterm start`.
    --ssh-domain <name>: Target a configured SSH domain when spawning remote tabs.
    --log-level <trace|debug|info>: Set diagnostic verbosity.
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
