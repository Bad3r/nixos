/*
  Package: i3-scratchpad-show-or-create
  Description: Repo-local i3 helper that toggles a named scratchpad window or
    spawns the configured command when none exists.
  Repository: https://github.com/Bad3r/nixos

  Notes:
    * Built from packages/i3-scratchpad-show-or-create via the overlay in
      modules/custom-overlays/i3-scratchpad-show-or-create.nix.
    * Consumed by modules/apps/i3wm/config.nix and keybindings.nix to wire
      scratchpad toggles for terminal/nvim/Logseq.
*/
_:
let
  I3ScratchpadShowOrCreateModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."i3-scratchpad-show-or-create".extended;
    in
    {
      options.programs."i3-scratchpad-show-or-create".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable i3-scratchpad-show-or-create.";
        };

        package = lib.mkPackageOption pkgs "i3-scratchpad-show-or-create" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."i3-scratchpad-show-or-create" = I3ScratchpadShowOrCreateModule;
}
