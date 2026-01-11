/*
  Package: pamixer
  Description: PulseAudio/pipewire-pulse command-line mixer with human-friendly controls.
  Homepage: https://github.com/cdemoulins/pamixer
  Documentation: https://github.com/cdemoulins/pamixer#usage
  Repository: https://github.com/cdemoulins/pamixer

  Summary:
    * Offers easy CLI access to PulseAudio volume controls, mute toggles, and sink/source selection for scripting or keybindings.
    * Supports incremental adjustments, setting absolute levels, listing sinks, and managing default devices.

  Options:
    pamixer --get-volume: Print the current volume of the default sink.
    pamixer --set-volume <percent>: Set volume to a specific level.
    pamixer --increase/--decrease <value>: Adjust volume relative to current level.
    pamixer --toggle-mute [--source]: Toggle mute status for sinks or sources.
    pamixer --list-sinks/--list-sources: Enumerate available audio devices.

  Example Usage:
    * `pamixer --increase 5` — Raise the default sink volume by 5%.
    * `pamixer --set-volume 30 --sink 1` — Set sink #1 to 30% volume explicitly.
    * `pamixer --toggle-mute` — Toggle mute state via a keybinding script.
*/
_:
let
  PamixerModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.pamixer.extended;
    in
    {
      options.programs.pamixer.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable pamixer.";
        };

        package = lib.mkPackageOption pkgs "pamixer" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.pamixer = PamixerModule;
}
