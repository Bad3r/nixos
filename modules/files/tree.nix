{
  flake.homeManagerModules.base =
    { pkgs, ... }:
    {
      home.packages = [
        pkgs.tree
      ];
    };
}
