_:
let
  Overlay = _: {
    nixpkgs.overlays = [
      (_: prev: {
        pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
          (_: python-prev: {
            curl-cffi = python-prev.curl-cffi.overridePythonAttrs (_: {
              doCheck = false;
              doInstallCheck = false;
              pytestCheckPhase = "true";
            });
          })
        ];
      })
    ];
  };
in
{
  flake.customOverlays.curl-cffi-fix = Overlay;
}
