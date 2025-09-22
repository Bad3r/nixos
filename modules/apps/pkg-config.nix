{
  flake.nixosModules.apps."pkg-config" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.pkg-config ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.pkg-config ];
    };
}
