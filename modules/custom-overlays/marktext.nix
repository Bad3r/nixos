# Workaround: marktext 0.17.0's native module rebuild can fail with
# `node-gyp: not found` under the current Node 24 toolchain. Pull
# `node-gyp` from `final` for the same fixpoint reason as `librepods`.
_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs.marktext.extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: prev: {
            marktext = prev.marktext.overrideAttrs (old: {
              nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
                final."node-gyp"
              ];
              npm_config_node_gyp = "${final."node-gyp"}/bin/node-gyp";
              NODE_GYP = "${final."node-gyp"}/bin/node-gyp";
            });
          })
        ];
      };
    };
in
{
  flake.customOverlays.marktext = Overlay;
}
