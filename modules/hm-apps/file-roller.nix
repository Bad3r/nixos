{
  flake.homeManagerModules.apps."file-roller" =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.file-roller ];
    };
}
