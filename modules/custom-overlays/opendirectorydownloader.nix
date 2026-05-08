_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs.opendirectorydownloader.extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            opendirectorydownloader = final.callPackage ../../packages/opendirectorydownloader { };
          })
        ];
      };
    };
in
{
  flake.customOverlays.opendirectorydownloader = Overlay;
}
