_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs.webcrack.extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            webcrack = final.callPackage ../../packages/webcrack { };
          })
        ];
      };
    };
in
{
  flake.customOverlays.webcrack = Overlay;
}
