{
  flake.nixosModules.apps."kbd" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.kbd ];
    };
}
