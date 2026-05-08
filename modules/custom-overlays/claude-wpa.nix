_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs."claude-wpa".extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            "claude-wpa" = final.callPackage ../../packages/claude-wpa { };
          })
        ];
      };
    };
in
{
  flake.customOverlays."claude-wpa" = Overlay;
}
