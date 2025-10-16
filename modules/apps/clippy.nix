{
  flake.nixosModules.apps."clippy" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."clippy" ];
    };
}
