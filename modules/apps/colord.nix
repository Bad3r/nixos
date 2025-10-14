{
  flake.nixosModules.apps."colord" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.colord ];
    };
}
