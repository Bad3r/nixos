{
  flake.nixosModules.apps.git-filter-repo =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.git-filter-repo ];
    };
}
