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
    lib.attrByPath path (throw "Missing NixOS app '${name}' while wiring System76 productivity tools.")
      config;

  getApps = config.flake.lib.nixos.getApps or (names: map getAppModule names);

  productivityAppNames = [
    "electron-mail"
    "logseq"
    "marktext"
    "mattermost"
    "obsidian"
    "pandoc"
    "planify"
    "raindrop"
    "tesseract"
  ];
in
{
  configurations.nixos.system76.module.imports = getApps productivityAppNames;
}
