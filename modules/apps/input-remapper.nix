/*
  Package: input-remapper
  Description: Tool to change the mapping of input device buttons and axes: keyboards, mice, and gamepads.
  Homepage: https://github.com/sezanzeb/input-remapper
  Documentation: https://github.com/sezanzeb/input-remapper/blob/main/readme/usage.md
  Repository: https://github.com/sezanzeb/input-remapper

  Summary:
    * Maps gamepad buttons and analog sticks to keys, mouse movement, macros, or other gamepad inputs, per device and per preset.

  Options:
    input-remapper-control --command autoload: Apply every preset flagged for autoload.

  Notes:
    * Autoload presets apply once a graphical session starts.
    * Hotplugged devices need a manual autoload or a service restart.
    * Presets live in ~/.config/input-remapper-2/.
    * Grabs devices exclusively; conflicts with antimicrox and sc-controller on the same device.
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
