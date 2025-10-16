{
  flake.nixosModules.apps."wireplumber" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.wireplumber ];
    };
}
