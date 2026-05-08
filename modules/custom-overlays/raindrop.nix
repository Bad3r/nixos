_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs.raindrop.extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            raindrop = final.callPackage ../../packages/raindrop { };
          })
        ];
      };
    };
in
{
  flake.customOverlays.raindrop = Overlay;
}
