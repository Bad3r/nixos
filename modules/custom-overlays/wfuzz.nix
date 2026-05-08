# nixpkgs wfuzz silently drops the `screenshot` plugin on Python 3.13
# (removed `pipes` stdlib module) and ships netaddr as a test-only dep,
# leaving iprange/ipnet payloads broken with a misleading "pip install"
# message. Patches are pending upstream review at xmendez/wfuzz#380 and
# nixpkgs PR; remove this override once they land.
_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs.wfuzz.extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            wfuzz = final.python3Packages.toPythonApplication (
              final.python3Packages.callPackage ../../packages/wfuzz { }
            );
          })
        ];
      };
    };
in
{
  flake.customOverlays.wfuzz = Overlay;
}
