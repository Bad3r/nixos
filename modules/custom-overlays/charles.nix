_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs.charles.extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            charles = final.callPackage ../../packages/charles { };
          })
        ];
      };
    };
in
{
  flake.customOverlays.charles = Overlay;
}
