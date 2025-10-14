{
  flake.nixosModules.apps."attr" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.attr ];
    };
}
