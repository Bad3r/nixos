{
  flake.nixosModules.apps."lynis" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.lynis ];
    };
}
