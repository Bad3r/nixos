_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs.captive-portal.extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            captive-portal = final.callPackage ../../packages/captive-portal { };
          })
        ];
      };
    };
in
{
  flake.customOverlays.captive-portal = Overlay;
}
