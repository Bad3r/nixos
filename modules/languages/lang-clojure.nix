{ config, ... }:
{
  flake.nixosModules.lang.clojure.imports =
    let
      inherit (config.flake.nixosModules) apps;
    in
    [
      apps.clojure-cli
      apps.clojure-lsp
      apps.leiningen
      apps.babashka
    ];
}
