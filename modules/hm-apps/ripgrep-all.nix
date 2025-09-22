{
  flake.homeManagerModules.apps."ripgrep-all" =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.ripgrep-all ];
    };
}
