{
  flake.nixosModules.apps."xlsclients" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."xlsclients" ];
    };
}
