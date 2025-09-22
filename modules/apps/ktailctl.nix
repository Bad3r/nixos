{
  flake.nixosModules.apps.ktailctl =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.ktailctl ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.ktailctl ];
    };
}
