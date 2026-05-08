_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs.azd.extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            azd = final.callPackage ../../packages/azd { };
          })
        ];
      };
    };
in
{
  flake.customOverlays.azd = Overlay;
}
