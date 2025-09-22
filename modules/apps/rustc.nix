{
  flake.nixosModules.apps.rustc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.rustc ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.rustc ];
    };
}
