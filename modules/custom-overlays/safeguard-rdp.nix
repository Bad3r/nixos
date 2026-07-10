_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs."safeguard-rdp".extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            "safeguard-rdp" = final.callPackage ../../packages/safeguard-rdp { };
          })
        ];
      };
    };
in
{
  flake.customOverlays."safeguard-rdp" = Overlay;
}
