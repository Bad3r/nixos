{
  flake.nixosModules.apps."polkit" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.polkit ];
    };
}
