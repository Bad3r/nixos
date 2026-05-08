_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs.wakaru.extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            wakaru = final.callPackage ../../packages/wakaru { };
          })
        ];
      };
    };
in
{
  flake.customOverlays.wakaru = Overlay;
}
