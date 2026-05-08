_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs.restringer.extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            restringer = final.callPackage ../../packages/restringer { };
          })
        ];
      };
    };
in
{
  flake.customOverlays.restringer = Overlay;
}
