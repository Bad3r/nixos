{
  flake.homeManagerModules.base =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        docker-compose
      ];
    };
}
