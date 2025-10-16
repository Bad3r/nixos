{
  flake.nixosModules.apps."tlp" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.tlp ];
    };
}
