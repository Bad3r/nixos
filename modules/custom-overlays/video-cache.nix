_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs."video-cache".extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            "video-cache" = final.callPackage ../../packages/video-cache { };
          })
        ];
      };
    };
in
{
  flake.customOverlays."video-cache" = Overlay;
}
