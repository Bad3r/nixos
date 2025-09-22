{
  flake.nixosModules.apps.nemo =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.nemo ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.nemo ];
    };
}
