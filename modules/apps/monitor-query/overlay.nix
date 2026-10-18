_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs."monitor-query".extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            "monitor-query" = import ./_script.nix {
              inherit (final) writeText;
            };
          })
        ];
      };
    };
in
{
  flake.customOverlays."monitor-query" = Overlay;
}
