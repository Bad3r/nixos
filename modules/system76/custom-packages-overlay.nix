{ config, ... }:
{
  configurations.nixos.system76.module = {
    nixpkgs.overlays = [
      (final: prev: {
        # Add custom packages to nixpkgs
        raindrop = final.callPackage ../../packages/raindrop { };
        yaak = final.callPackage ../../packages/yaak { };
        codex = final.callPackage ../../packages/codex { };
        coderabbit-cli = final.callPackage ../../packages/coderabbit-cli { };
        wappalyzer-next = final.callPackage ../../packages/wappalyzer-next { };
        age-plugin-fido2prf = final.callPackage ../../packages/age-plugin-fido2prf { };
        charles = final.callPackage ../../packages/charles { };
      })
    ];
  };
}