{
  flake.nixosModules.apps."shared-mime-info" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."shared-mime-info" ];
    };
}
