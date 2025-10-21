{ inputs, ... }:
{
  flake.nixosModules.base.imports = [
    (inputs.import-tree ./../roles)
  ];
}
