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
            john = (prev.john.override { withOpenCL = true; }).overrideAttrs (_old: {
              version = "1.9.0-Jumbo-1-unstable-2026-04-13";

              src = final.fetchFromGitHub {
                owner = "openwall";
                repo = "john";
                rev = "f514ece8ec4ae5e38ad75aaa322eac86d73dcd76";
                hash = "sha256-zO1/KUJe3LvYCGlwVpNg5uDwPRD0ql/7anErb7tywC0=";
              };

              # nixpkgs ships opencl.patch keyed to the rolling-2604 layout
              # (libOpenCL.so.1 first); the locked input still pins
              # rolling-2404, so inherit-via-overrideAttrs would try to apply
              # the old patch context against the bumped source and fail.
              patches = [
                (final.replaceVars ./john-opencl.patch { ocl_icd = final.ocl-icd; })
              ];
            });
          })
        ];
      };
    };
in
{
  flake.customOverlays.john = Overlay;
}
