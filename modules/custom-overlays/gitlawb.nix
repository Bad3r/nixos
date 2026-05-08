_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs.gitlawb.extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            gitlawb = final.callPackage ../../packages/gitlawb { };
          })
        ];
      };
    };
in
{
  flake.customOverlays.gitlawb = Overlay;
}
