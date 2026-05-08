_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs."source-map-explorer".extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            "source-map-explorer" = final.callPackage ../../packages/source-map-explorer { };
          })
        ];
      };
    };
in
{
  flake.customOverlays."source-map-explorer" = Overlay;
}
