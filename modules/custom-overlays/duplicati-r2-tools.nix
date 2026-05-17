_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs.duplicati-r2-tools.extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            duplicati-r2-tools = final.callPackage ../../packages/duplicati-r2-tools { };
          })
        ];
      };
    };
in
{
  flake.customOverlays."duplicati-r2-tools" = Overlay;
}
