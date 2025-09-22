{
  flake.homeManagerModules.apps."docker-compose" =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.docker-compose ];
    };
}
