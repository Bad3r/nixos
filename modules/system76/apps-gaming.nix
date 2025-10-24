{ config, lib, ... }:
let
  helpers = config.flake.lib.nixos or { };
  hasApp =
    name:
    let
      path = [
        "flake"
        "nixosModules"
        "apps"
        name
      ];
    in
    (helpers.hasApp or (n: lib.hasAttrByPath [ "flake" "nixosModules" "apps" n ] config)) name
    || lib.hasAttrByPath path config;

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
    lib.attrByPath path (throw "Missing NixOS app '${name}' while wiring System76 gaming tools.")
      config;

  getApps = helpers.getApps or (names: map getAppModule names);

  desiredAppNames = [
    "steam"
    "wine-tools"
    "mangohud"
  ];

  availableAppNames = lib.filter hasApp desiredAppNames;
in
{
  configurations.nixos.system76.module.imports = getApps availableAppNames;
}
