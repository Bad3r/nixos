_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs."brave-origin".extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            "brave-origin" = final.callPackage ../../packages/brave-origin { };
          })
        ];
      };
    };
in
{
  flake.customOverlays."brave-origin" = Overlay;
}
