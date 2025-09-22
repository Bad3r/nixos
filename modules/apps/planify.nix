{
  flake.nixosModules.apps.planify =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.planify ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.planify ];
    };
}
