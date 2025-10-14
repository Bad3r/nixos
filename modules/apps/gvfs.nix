{
  flake.nixosModules.apps."gvfs" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gvfs ];
    };
}
