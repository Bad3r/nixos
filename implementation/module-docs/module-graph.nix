{
  lib,
  flake,
  rootPath ? ./. ,
  system ? "x86_64-linux",
  pkgsOverride ? null,
  inputsOverride ? null,
  extraSpecialArgs ? { },
  namespaceFilters ? [ "nixosModules" "homeManagerModules" ],
}:
let
  docLib = import ./lib { inherit lib; };

  legacyPackages = flake.legacyPackages or { };
  availableSystems = builtins.attrNames legacyPackages;
  selectedSystem =
    if availableSystems != [ ] then
      if lib.elem system availableSystems then system else builtins.head availableSystems
    else
      system;

  fallbackPkgs =
    if pkgsOverride != null then
      pkgsOverride
    else if legacyPackages != { } && builtins.hasAttr selectedSystem legacyPackages then
      legacyPackages.${selectedSystem}
    else
      import flake.inputs.nixpkgs { inherit selectedSystem; };
