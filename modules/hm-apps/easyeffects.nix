/*
  Package: easyeffects
  Description: Audio effects for PipeWire applications.
  Homepage: https://github.com/wwmm/easyeffects
  Documentation: https://github.com/wwmm/easyeffects/wiki
  Repository: https://github.com/wwmm/easyeffects

  Summary:
    * Runs EasyEffects as a user service (`easyeffects --hide-window --service-mode`) so the effects chain stays active without the window open.
    * `services.easyeffects.preset` and `services.easyeffects.extraPresets` load and ship presets declaratively once a chain has been tuned in the GUI.

  Options:
    -q, --quit: Quit Easy Effects. Useful when running in service mode.
    -r, --reset: Reset Easy Effects.
    -w, --hide-window: Hide the window.
    -b, --bypass <bypass-state>: Global bypass. 1 to enable, 2 to disable and 3 to get the current state.
    --bypass-toggle: Toggle the state of the global bypass.
    -l, --load-preset <preset-name>: Load a preset. Example: easyeffects -l music.
    -p, --presets: Show available presets.
    -a, --last-loaded-preset <preset-type>: Get the last loaded preset for `input` or `output`.
    -s, --last-loaded-presets: Get the last loaded input and output presets.
    --service-mode: Start the application with service mode turned on.
    --debug: Enable debug messages.

  Notes:
    * Follows `programs.easyeffects.extended.enable` from the NixOS module.
    * HM services.easyeffects does not support nullable package, so HM installs the same store path NixOS does.
*/

_: {
  flake.homeManagerModules.apps.easyeffects =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "easyeffects" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        services.easyeffects.enable = true;
      };
    };
}
