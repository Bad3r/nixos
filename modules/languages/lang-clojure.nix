{ config, ... }:
{
  flake.modules.nixos.lang.clojure.imports = with config.flake.modules.nixos.apps; [
    clojure-cli
    clojure-lsp
    leiningen
    babashka
  ];
}
