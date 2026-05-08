_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs."i3-focus-or-launch".extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            "i3-focus-or-launch" = final.callPackage ../../packages/i3-focus-or-launch { };
          })
        ];
      };
    };
in
{
  flake.customOverlays."i3-focus-or-launch" = Overlay;
}
