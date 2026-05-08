_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs."electron-mail".extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            "electron-mail" = final.callPackage ../../packages/electron-mail { };
          })
        ];
      };
    };
in
{
  flake.customOverlays."electron-mail" = Overlay;
}
