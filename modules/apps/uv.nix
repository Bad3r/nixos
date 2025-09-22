{
  flake.nixosModules.apps.uv =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.uv ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.uv ];
    };
}
