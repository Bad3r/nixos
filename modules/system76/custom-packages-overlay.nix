_: {
  configurations.nixos.system76.module = {
    nixpkgs.overlays = [
      (final: _prev: {
        # Add custom packages to nixpkgs
        raindrop = final.callPackage ../../packages/raindrop { };
        wappalyzer-next = final.callPackage ../../packages/wappalyzer-next { };
        age-plugin-fido2prf = final.callPackage ../../packages/age-plugin-fido2prf { };
        charles = final.callPackage ../../packages/charles { };
        dnsleak = final.callPackage ../../packages/dnsleak { };
        opendirectorydownloader = final.callPackage ../../packages/opendirectorydownloader { };
        malimite = final.callPackage ../../packages/malimite { };
        claude-wpa = final.callPackage ../../packages/claude-wpa { };
        rg-fzf = final.callPackage ../../packages/rg-fzf { };
        webcrack = final.callPackage ../../packages/webcrack { };
        wakaru = final.callPackage ../../packages/wakaru { };

        # i3 window manager utilities
        i3-focus-or-launch = final.callPackage ../../packages/i3-focus-or-launch { };
        i3-scratchpad-show-or-create = final.callPackage ../../packages/i3-scratchpad-show-or-create { };
        monitor-query = import ../../lib/shell/monitor-query.nix { inherit (final) writeText; };
        # toggle-logseq is created in modules/apps/i3wm/config.nix (needs config.gui.scratchpad)
      })
    ];
  };
}
