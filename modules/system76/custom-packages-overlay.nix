_: {
  configurations.nixos.system76.module = {
    nixpkgs.overlays = [
      (final: prev: {
        # Add custom packages to nixpkgs
        raindrop = final.callPackage ../../packages/raindrop { };
        electron-mail = final.callPackage ../../packages/electron-mail { };
        wappalyzer-next = final.callPackage ../../packages/wappalyzer-next { };
        age-plugin-fido2prf = final.callPackage ../../packages/age-plugin-fido2prf { };
        azd = final.callPackage ../../packages/azd { };
        charles = final.callPackage ../../packages/charles { };
        dnsleak = final.callPackage ../../packages/dnsleak { };
        opendirectorydownloader = final.callPackage ../../packages/opendirectorydownloader { };
        malimite = final.callPackage ../../packages/malimite { };
        claude-wpa = final.callPackage ../../packages/claude-wpa { };
        rg-fzf = final.callPackage ../../packages/rg-fzf { };
        sss-nix-repair = final.callPackage ../../packages/sss-nix-repair { };
        webcrack = final.callPackage ../../packages/webcrack { };
        wakaru = final.callPackage ../../packages/wakaru { };
        restringer = final.callPackage ../../packages/restringer { };
        tweakcc = final.callPackage ../../packages/tweakcc { };
        video-cache = final.callPackage ../../packages/video-cache { };

        # Workaround: dwarfs 0.12.4 currently fails with boost 1.89
        # (`boost_system` no longer resolves during CMake configure).
        dwarfs = prev.dwarfs.override {
          boost = prev.boost187;
        };

        # Workaround: marktext 0.17.0's native module rebuild can fail with
        # `node-gyp: not found` under the current Node 24 toolchain.
        marktext = prev.marktext.overrideAttrs (old: {
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
            prev."node-gyp"
          ];
          npm_config_node_gyp = "${prev."node-gyp"}/bin/node-gyp";
          NODE_GYP = "${prev."node-gyp"}/bin/node-gyp";
        });

        # i3 window manager utilities
        i3-focus-or-launch = final.callPackage ../../packages/i3-focus-or-launch { };
        i3-scratchpad-show-or-create = final.callPackage ../../packages/i3-scratchpad-show-or-create { };
        monitor-query = import ../../lib/shell/monitor-query.nix { inherit (final) writeText; };
        # toggle-logseq is created in modules/apps/i3wm/config.nix (needs config.gui.scratchpad)
      })
    ];
  };
}
