/*
  Package: i3-focus-or-launch
  Description: Repo-local i3 helper that focuses an existing window matching a
    class/name, or launches the program if no match is found.
  Repository: https://github.com/Bad3r/nixos

  Notes:
    * Built from packages/i3-focus-or-launch via the overlay in
      modules/custom-overlays/i3-focus-or-launch.nix.
    * Consumed by modules/apps/i3wm/config.nix to bind focus-or-launch shortcuts.
*/
_:
let
  I3FocusOrLaunchModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."i3-focus-or-launch".extended;
    in
    {
      options.programs."i3-focus-or-launch".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable i3-focus-or-launch.";
        };

        package = lib.mkPackageOption pkgs "i3-focus-or-launch" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."i3-focus-or-launch" = I3FocusOrLaunchModule;
}
