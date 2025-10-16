{
  flake.nixosModules.apps."fontconfig" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.fontconfig ];
    };
}
