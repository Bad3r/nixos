{
  config,
  ...
}:
{
  perSystem =
    { pkgs, ... }:
    {
      packages.yaak = pkgs.callPackage ../../packages/yaak/package.nix {
        wasmPack = pkgs.wasm-pack;
        inherit (pkgs) jq;
        inherit (pkgs.llvmPackages_latest) lld;
        wasmBindgenPrebuilt = pkgs.fetchurl {
          url = "https://github.com/rustwasm/wasm-bindgen/releases/download/0.2.100/wasm-bindgen-0.2.100-x86_64-unknown-linux-musl.tar.gz";
          sha256 = "sha256-Y9ajjetlvXAjwCvfOCq2aw0sAkHIWC/TQTtagIuK61s=";
        };
      };
    };

  flake.nixosModules.apps.yaak =
    { pkgs, ... }:
    {
      environment.systemPackages = [ config.flake.packages.${pkgs.system}.yaak ];
    };

  flake.homeManagerModules.apps.yaak =
    { pkgs, ... }:
    {
      home.packages = [ config.flake.packages.${pkgs.system}.yaak ];
    };
}
