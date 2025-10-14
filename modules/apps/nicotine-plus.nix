{
  flake.nixosModules.apps."nicotine-plus" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."nicotine-plus" ];
    };
}
