_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs."sss-nix-repair".extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            "sss-nix-repair" = final.callPackage ../../packages/sss-nix-repair { };
          })
        ];
      };
    };
in
{
  flake.customOverlays."sss-nix-repair" = Overlay;
}
