_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs.subjack.extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            subjack = final.callPackage ../../packages/subjack { };
          })
        ];
      };
    };
in
{
  flake.customOverlays.subjack = Overlay;
}
