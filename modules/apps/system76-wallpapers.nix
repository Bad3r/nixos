{
  flake.nixosModules.apps."system76-wallpapers" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."system76-wallpapers" ];
    };
}
