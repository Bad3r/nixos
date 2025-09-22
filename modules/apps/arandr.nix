{
  flake.nixosModules.apps.arandr =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.arandr ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.arandr ];
    };
}
