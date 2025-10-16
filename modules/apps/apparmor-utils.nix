{
  flake.nixosModules.apps."apparmor-utils" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."apparmor-utils" ];
    };
}
