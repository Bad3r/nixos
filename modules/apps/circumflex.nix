{
  flake.nixosModules.apps.circumflex =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.circumflex ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.circumflex ];
    };
}
