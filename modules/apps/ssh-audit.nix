{
  flake.nixosModules.apps."ssh-audit" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."ssh-audit" ];
    };
}
