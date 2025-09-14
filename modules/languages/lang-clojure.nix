{ config, ... }:
let
  inherit (config.flake.lib.nixos) getApps;
in
{
  flake.nixosModules.lang.clojure.imports = getApps [
    "clojure-cli"
    "clojure-lsp"
    "leiningen"
    "babashka"
  ];
}
