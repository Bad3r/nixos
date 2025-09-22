{
  flake.homeManagerModules.apps.ripgrep =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.ripgrep ];
    };
}
