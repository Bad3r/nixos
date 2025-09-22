{
  flake.nixosModules.apps."cosmic-term" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.cosmic-term ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.cosmic-term ];
    };
}
