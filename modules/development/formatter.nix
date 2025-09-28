{ inputs, lib, ... }:
{
  perSystem =
    {
      system,
      ...
    }:
    lib.mkIf (system == "x86_64-linux") {
      formatter = inputs.nixpkgs.legacyPackages."x86_64-linux".nixfmt-tree;
    };
}
