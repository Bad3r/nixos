_: {
  configurations.nixos.system76.module = {
    nixpkgs.overlays = [
      (final: _prev: {
        # Add custom packages to nixpkgs
        raindrop = final.callPackage ../../packages/raindrop { };
        yaak = final.callPackage ../../packages/yaak { };
        # codex = final.callPackage ../../packages/codex { }; # DEPRECATED: using upstream nixpkgs
        coderabbit-cli = final.callPackage ../../packages/coderabbit-cli { };
        wappalyzer-next = final.callPackage ../../packages/wappalyzer-next { };
        age-plugin-fido2prf = final.callPackage ../../packages/age-plugin-fido2prf { };
        charles = final.callPackage ../../packages/charles { };
        dnsleak = final.callPackage ../../packages/dnsleak { };
        opendirectorydownloader = final.callPackage ../../packages/opendirectorydownloader { };
        malimite = final.callPackage ../../packages/malimite { };
        system76-ectool = final.callPackage ../../packages/system76-ectool { };
      })
    ];
  };
}
