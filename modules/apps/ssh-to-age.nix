{
  flake.nixosModules.apps."ssh-to-age" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."ssh-to-age" ];
    };
}
