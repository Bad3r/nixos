{ config, ... }:
{
  flake.nixosModules.lang.clojure.imports = with config.flake.nixosModules.apps; [
    clojure-cli
    clojure-lsp
    leiningen
    babashka
  ];
}
