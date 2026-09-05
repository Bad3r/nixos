/*
  Package: input-remapper
  Description: Tool to change the mapping of input device buttons and axes: keyboards, mice, and gamepads.
  Homepage: https://github.com/sezanzeb/input-remapper
  Documentation: https://github.com/sezanzeb/input-remapper/blob/main/readme/usage.md
  Repository: https://github.com/sezanzeb/input-remapper

  Summary:
    * Enables the upstream NixOS service: a root daemon that grabs the chosen evdev devices and re-emits the mapped events through uinput, plus the GTK editor and the `input-remapper-control` CLI.
    * Maps gamepad buttons and analog sticks to keys, mouse movement, macros, or other gamepad inputs, per device and per preset.
    * Uses services namespace because the daemon runs as a system service.

  Options:
    input-remapper-gtk: Open the preset editor.
    input-remapper-control --command autoload: Apply every preset flagged for autoload.
    services.input-remapper.enableUdevRules: Upstream keeps the hotplug autoload rule off (sezanzeb/input-remapper#140); left at that default, so a controller plugged in mid-session needs a manual autoload or a service restart.

  Notes:
    * The daemon is wanted by graphical.target (upstream default), so autoload presets apply once a session starts.
    * Presets live in ~/.config/input-remapper-2/.
    * Grabs its source evdev devices exclusively; antimicrox and sc-controller do not coordinate with it, so autoloading a preset for a device one of them also targets leaves only one program receiving events.
*/
_:
let
  InputRemapperModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.input-remapper.extended;
    in
    {
      options.services.input-remapper.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable input-remapper.";
        };

        package = lib.mkPackageOption pkgs "input-remapper" { };
      };

      config = lib.mkIf cfg.enable {
        services.input-remapper = {
          enable = true;
          inherit (cfg) package;
        };
      };
    };
in
{
  flake.nixosModules.apps.input-remapper = InputRemapperModule;
}
