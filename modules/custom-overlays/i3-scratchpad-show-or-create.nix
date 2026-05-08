_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs."i3-scratchpad-show-or-create".extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            "i3-scratchpad-show-or-create" = final.callPackage ../../packages/i3-scratchpad-show-or-create { };
          })
        ];
      };
    };
in
{
  flake.customOverlays."i3-scratchpad-show-or-create" = Overlay;
}
