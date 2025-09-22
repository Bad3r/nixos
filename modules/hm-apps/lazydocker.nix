{
  flake.homeManagerModules.apps.lazydocker =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.lazydocker ];
    };
}
