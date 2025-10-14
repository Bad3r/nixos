{
  flake.nixosModules.apps."foremost" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.foremost ];
    };
}
