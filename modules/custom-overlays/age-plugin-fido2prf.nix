_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs."age-plugin-fido2prf".extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            "age-plugin-fido2prf" = final.callPackage ../../packages/age-plugin-fido2prf { };
          })
        ];
      };
    };
in
{
  flake.customOverlays."age-plugin-fido2prf" = Overlay;
}
