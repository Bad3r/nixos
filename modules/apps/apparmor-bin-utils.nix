{
  flake.nixosModules.apps."apparmor-bin-utils" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."apparmor-bin-utils" ];
    };
}
