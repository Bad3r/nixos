{
  flake.nixosModules.apps.yq =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.yq ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.yq ];
    };
}
