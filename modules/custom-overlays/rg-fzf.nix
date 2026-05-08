_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs."rg-fzf".extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            "rg-fzf" = final.callPackage ../../packages/rg-fzf { };
          })
        ];
      };
    };
in
{
  flake.customOverlays."rg-fzf" = Overlay;
}
