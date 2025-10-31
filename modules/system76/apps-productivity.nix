{ config, ... }:
let
  helpers =
    config._module.args.nixosAppHelpers
      or (throw "nixosAppHelpers not available - ensure meta/nixos-app-helpers.nix is imported");
  inherit (helpers) getApps;

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
