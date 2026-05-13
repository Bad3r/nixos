_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs.john.extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: prev: {
            john = prev.john.overrideAttrs (_old: {
              version = "1.9.0-Jumbo-1-unstable-2026-04-13";

              src = final.fetchFromGitHub {
                owner = "openwall";
                repo = "john";
                rev = "f514ece8ec4ae5e38ad75aaa322eac86d73dcd76";
                hash = "sha256-zO1/KUJe3LvYCGlwVpNg5uDwPRD0ql/7anErb7tywC0=";
              };
            });
          })
        ];
      };
    };
in
{
  flake.customOverlays.john = Overlay;
}
