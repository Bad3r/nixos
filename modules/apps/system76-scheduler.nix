{
  flake.nixosModules.apps."system76-scheduler" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."system76-scheduler" ];
    };
}
