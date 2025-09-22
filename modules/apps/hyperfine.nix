{
  flake.nixosModules.apps.hyperfine =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.hyperfine ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.hyperfine ];
    };
}
