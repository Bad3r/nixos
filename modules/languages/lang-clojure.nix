{ lib, ... }:
{
  flake.nixosModules.lang.clojure = {
    programs = {
      "clojure-cli".extended.enable = lib.mkOverride 1050 true;
      "clojure-lsp".extended.enable = lib.mkOverride 1050 true;
      leiningen.extended.enable = lib.mkOverride 1050 true;
      babashka.extended.enable = lib.mkOverride 1050 true;
    };
  };
}
