{
  flake.nixosModules.apps."libva-utils" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."libva-utils" ];
    };
}
