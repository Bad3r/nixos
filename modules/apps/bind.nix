{
  flake.nixosModules.apps."bind" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.bind ];
    };
}
