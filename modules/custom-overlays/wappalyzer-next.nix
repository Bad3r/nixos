_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs."wappalyzer-next".extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            "wappalyzer-next" = final.callPackage ../../packages/wappalyzer-next { };
          })
        ];
      };
    };
in
{
  flake.customOverlays."wappalyzer-next" = Overlay;
}
