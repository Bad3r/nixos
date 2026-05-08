_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs.malimite.extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            malimite = final.callPackage ../../packages/malimite { };
          })
        ];
      };
    };
in
{
  flake.customOverlays.malimite = Overlay;
}
