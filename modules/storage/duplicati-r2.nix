{ inputs, ... }:
let
  newModule = import ../services/duplicati-r2.nix { inherit inputs; };
in
{
  flake.nixosModules.storage.duplicati-r2 = newModule.flake.nixosModules."duplicati-r2";
}
