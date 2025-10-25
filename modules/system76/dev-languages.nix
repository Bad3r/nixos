{ config, lib, ... }:
let
  getAppModule =
    name:
    let
      path = [
        "flake"
        "nixosModules"
        "apps"
        name
      ];
    in
    lib.attrByPath path (throw "Missing app module ${name} while wiring System76 dev languages.")
      config;

  appNames = [
    "python"
    "uv"
    "ruff"
    "pyright"
    "go"
    "gopls"
    "golangci-lint"
    "delve"
    "rustc"
    "cargo"
    "rust-analyzer"
    "rustfmt"
    "rust-clippy"
    "clojure-cli"
    "clojure-lsp"
    "leiningen"
    "babashka"
    "pixman"
  ];

  getApps = config.flake.lib.nixos.getApps or (names: map getAppModule names);
in
{
  configurations.nixos.system76.module.imports = getApps appNames;
}
