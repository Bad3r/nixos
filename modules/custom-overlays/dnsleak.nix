_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs.dnsleak.extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            dnsleak = final.callPackage ../../packages/dnsleak { };
          })
        ];
      };
    };
in
{
  flake.customOverlays.dnsleak = Overlay;
}
