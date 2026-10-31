/*
  Package: cosmic-term
  Description: POP!_OS COSMIC desktop terminal emulator with GPU-accelerated rendering and ligature support.
  Homepage: https://github.com/pop-os/cosmic-term
  Documentation: https://github.com/pop-os/cosmic-term#readme
  Repository: https://github.com/pop-os/cosmic-term

  Summary:
    * Profiles, color schemes, and theme import from the settings UI.
    * Falls back to CPU rendering when the GPU is unavailable.
*/
_:
let
  CosmicTermModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."cosmic-term".extended;
    in
    {
      options.programs.cosmic-term.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable cosmic-term.";
        };

        package = lib.mkPackageOption pkgs "cosmic-term" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.cosmic-term = CosmicTermModule;
}
