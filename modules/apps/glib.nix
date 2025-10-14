{
  flake.nixosModules.apps."glib" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.glib ];
    };
}
