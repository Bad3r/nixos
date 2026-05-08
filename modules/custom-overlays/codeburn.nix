_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs.codeburn.extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            codeburn = final.callPackage ../../packages/codeburn { };
          })
        ];
      };
    };
in
{
  flake.customOverlays.codeburn = Overlay;
}
