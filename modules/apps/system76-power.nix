{
  flake.nixosModules.apps."system76-power" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."system76-power" ];
    };
}
