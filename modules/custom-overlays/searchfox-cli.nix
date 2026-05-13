_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs."searchfox-cli".extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            "searchfox-cli" = final.callPackage ../../packages/searchfox-cli { };
          })
        ];
      };
    };
in
{
  flake.customOverlays."searchfox-cli" = Overlay;
}
