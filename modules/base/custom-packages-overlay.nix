# Shared nixpkgs overlay surfaced as `config.flake.lib.overlays.customPackages`.
# This module only *defines* the overlay; hosts opt in by composing it into
# `nixpkgs.overlays` (see `modules/system76/custom-packages-overlay.nix` for an
# example that prepends this overlay and then layers a hardware-specific patch
# on top).
#
# Resolution rules:
# - `final.callPackage` for in-tree derivations under `packages/`.
# - `prev.<pkg>.overrideAttrs` for upstream packages that need patching, version
#   bumps, or dependency tweaks until the upstream issue is resolved.
_: {
  flake.lib.overlays.customPackages = final: prev: {
    # In-tree custom packages from `packages/`.
    brave-origin = final.callPackage ../../packages/brave-origin { };
    raindrop = final.callPackage ../../packages/raindrop { };
    electron-mail = final.callPackage ../../packages/electron-mail { };
    wappalyzer-next = final.callPackage ../../packages/wappalyzer-next { };
    age-plugin-fido2prf = final.callPackage ../../packages/age-plugin-fido2prf { };
    azd = final.callPackage ../../packages/azd { };
    charles = final.callPackage ../../packages/charles { };
    dnsleak = final.callPackage ../../packages/dnsleak { };
    gitlawb = final.callPackage ../../packages/gitlawb { };
    opendirectorydownloader = final.callPackage ../../packages/opendirectorydownloader { };
    malimite = final.callPackage ../../packages/malimite { };
    claude-wpa = final.callPackage ../../packages/claude-wpa { };
    codeburn = final.callPackage ../../packages/codeburn { };
    rg-fzf = final.callPackage ../../packages/rg-fzf { };
    sss-nix-repair = final.callPackage ../../packages/sss-nix-repair { };
    source-map-explorer = final.callPackage ../../packages/source-map-explorer { };
    webcrack = final.callPackage ../../packages/webcrack { };
    wakaru = final.callPackage ../../packages/wakaru { };
    restringer = final.callPackage ../../packages/restringer { };
    tweakcc = final.callPackage ../../packages/tweakcc { };
    video-cache = final.callPackage ../../packages/video-cache { };

    # nixpkgs wfuzz silently drops the `screenshot` plugin on Python 3.13
    # (removed `pipes` stdlib module) and ships netaddr as a test-only dep,
    # leaving iprange/ipnet payloads broken with a misleading "pip install"
    # message. Patches are pending upstream review at xmendez/wfuzz#380 and
    # nixpkgs PR; remove this override once they land.
    wfuzz = final.python3Packages.toPythonApplication (
      final.python3Packages.callPackage ../../packages/wfuzz { }
    );

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
    # (see `modules/stylix/qt6ct-colors.nix`).
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

    # Workaround: marktext 0.17.0's native module rebuild can fail with
    # `node-gyp: not found` under the current Node 24 toolchain. Pull
    # `node-gyp` from `final` for the same fixpoint reason as `librepods`.
    marktext = prev.marktext.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
        final."node-gyp"
      ];
      npm_config_node_gyp = "${final."node-gyp"}/bin/node-gyp";
      NODE_GYP = "${final."node-gyp"}/bin/node-gyp";
    });

    # i3 window manager utilities
    i3-focus-or-launch = final.callPackage ../../packages/i3-focus-or-launch { };
    i3-scratchpad-show-or-create = final.callPackage ../../packages/i3-scratchpad-show-or-create { };
    monitor-query = import ../../lib/shell/monitor-query.nix { inherit (final) writeText; };
    # toggle-logseq is created in modules/apps/i3wm/config.nix (needs config.gui.scratchpad)
  };
}
