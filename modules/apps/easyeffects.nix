/*
  Package: easyeffects
  Description: Audio effects for PipeWire applications.
  Homepage: https://github.com/wwmm/easyeffects
  Documentation: https://github.com/wwmm/easyeffects/wiki
  Repository: https://github.com/wwmm/easyeffects

  Summary:
    * Inserts an effects chain (equalizer, bass enhancer, limiter, compressor, crossfeed, convolver, noise reduction) between PipeWire clients and the output device or microphone.
    * Saves chains as JSON presets under ~/.local/share/easyeffects and autoloads a preset per device.

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
    * Requires PipeWire; `modules/hosts/common/pipewire.nix` enables it for every shared host.
    * `modules/hm-apps/easyeffects.nix` runs the user service through Home Manager `services.easyeffects`.
*/
_:
let
  EasyeffectsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.easyeffects.extended;
    in
    {
      options.programs.easyeffects.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable easyeffects.";
        };

        package = lib.mkPackageOption pkgs "easyeffects" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.easyeffects = EasyeffectsModule;
}
