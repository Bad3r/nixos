# librepods overlay. Base nixpkgs now pins v0.2.5 with the same src hash, so
# this override only carries what base does not:
#   * the Max-2 patch backporting https://github.com/kavishdevar/librepods/pull/519
#     so AirPods Max 2 (BLE 0x2D20 / model A3454) is recognised; without it the
#     device falls through to the unknown-model defaults. Drop the patch once
#     PR #519 merges and a release pinning it ships.
#   * qtdeclarative + qttools in buildInputs (base pulls qtquick3d); librepods
#     is a QtQuick.Controls 2 app, so the QML runtime comes from qtdeclarative
#     and qtquick3d's 3D stack is not needed.
#   * QT_STYLE_OVERRIDE=Fusion forced at wrap time (rationale below).
# Dep lookups go through `final` so any later overlay (e.g. an `openssl` CVE
# patch) feeds into this build instead of being silently bypassed.
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
#
# That `--set` is injected via `preFixup` shell code instead of a
# `qtWrapperArgs` list attribute because upstream sets
# `__structuredAttrs = true`. Under structured attrs a Nix list attr
# becomes a real bash array before `wrapQtAppsHook` runs, but that
# hook still initializes with `qtWrapperArgs=(${qtWrapperArgs-})`,
# unquoted scalar word-splitting that collapses an array down to just
# its first element. That drops the rest of the flags and misaligns
# every `--prefix` group `qtHostPathHook` appends afterward, which
# surfaces as `makeCWrapper: Unknown argument :`. Mutating the
# already-initialized array with `+=` in `preFixup` sidesteps the
# collapse, matching nixpkgs' own precedent in `pkgs/by-name/ed/eden`
# and `pkgs/by-name/ya/yacreader`.
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
            librepods = prev.librepods.overrideAttrs (old: {
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
              preFixup = (old.preFixup or "") + ''
                qtWrapperArgs+=(--set QT_STYLE_OVERRIDE Fusion)
              '';
            });
          })
        ];
      };
    };
in
{
  flake.customOverlays.librepods = Overlay;
}
