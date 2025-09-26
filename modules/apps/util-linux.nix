{
  flake.nixosModules.apps."util-linux" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."util-linux" ];
    };
}
