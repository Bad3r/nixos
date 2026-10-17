/*
  Package: pwvucontrol
  Description: GTK volume control for PipeWire, modelled on pavucontrol.
  Homepage: https://github.com/saivert/pwvucontrol
  Documentation: https://github.com/saivert/pwvucontrol#readme
  Repository: https://github.com/saivert/pwvucontrol

  Summary:
    * Sets volume and mute per application stream and per device, and picks the default output and input.
    * Talks to PipeWire directly rather than through the PulseAudio compatibility layer.

  Options:
    pwvucontrol: Open the volume control window.
*/
_:
let
  PwvucontrolModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.pwvucontrol.extended;
    in
    {
      options.programs.pwvucontrol.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable pwvucontrol.";
        };

        package = lib.mkPackageOption pkgs "pwvucontrol" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.pwvucontrol = PwvucontrolModule;
}
