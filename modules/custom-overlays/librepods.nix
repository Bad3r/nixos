# Bump librepods to v0.2.5 (nixpkgs pins v0.2.0). v0.2.5 swaps
# qtquick3d for qtdeclarative + qttools and adds Widgets/DBus.
# Dep lookups go through `final` so any later overlay (e.g. an `openssl`
# CVE patch) feeds into this build instead of being silently bypassed.
# The Max-2 patch backports https://github.com/kavishdevar/librepods/pull/519
# so AirPods Max 2 (BLE 0x2D20 / model A3454) is recognised; without it
# the device falls through to the unknown-model defaults. Drop the patch
# once upstream merges PR #519 and a release pinning it ships.
#
# librepods is a pure QtQuick.Controls 2 app and Stylix exports
# `QT_STYLE_OVERRIDE=kvantum` in the session env. Kvantum ships only
# a `QStyle`, not a QtQuick.Controls module, so QML loading fails with
# `module "kvantum" is not installed`. `--set-default` is a no-op
# because the session already exports the broken value, and
# `wrapQtAppsHook`'s `makeCWrapper` does not support `--run` for
# conditional rewrites. `--set` unconditionally forces Fusion before
# exec, so the broken value is always replaced. Fusion is palette-aware
# and picks up the Stylix Base16 colors via the qt6ct color scheme
# that Stylix's qt target generates.
_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs.librepods.extended;
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: prev: {
            librepods = prev.librepods.overrideAttrs (old: rec {
              version = "0.2.5";
              src = final.fetchFromGitHub {
                owner = "kavishdevar";
                repo = "librepods";
                tag = "v${version}";
                hash = "sha256-6l1WjwjDbv5e3tDaWo9+XSEjr9ge/hKysIkeUqyiO4U=";
              };
              patches = (old.patches or [ ]) ++ [
                ../../packages/librepods/airpods-max-2.patch
              ];
              buildInputs = [
                final.libpulseaudio
                final.openssl
                final.qt6.qtbase
                final.qt6.qtconnectivity
                final.qt6.qtdeclarative
                final.qt6.qttools
              ];
              qtWrapperArgs = (old.qtWrapperArgs or [ ]) ++ [
                "--set"
                "QT_STYLE_OVERRIDE"
                "Fusion"
              ];
            });
          })
        ];
      };
    };
in
{
  flake.customOverlays.librepods = Overlay;
}
