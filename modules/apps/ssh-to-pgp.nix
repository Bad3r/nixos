{
  flake.nixosModules.apps."ssh-to-pgp" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."ssh-to-pgp" ];
    };
}
