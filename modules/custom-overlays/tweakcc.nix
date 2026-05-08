_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs.tweakcc.extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            tweakcc = final.callPackage ../../packages/tweakcc { };
          })
        ];
      };
    };
in
{
  flake.customOverlays.tweakcc = Overlay;
}
