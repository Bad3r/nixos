{
  flake.nixosModules.apps."bcache-tools" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."bcache-tools" ];
    };
}
