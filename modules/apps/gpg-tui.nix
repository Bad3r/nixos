{
  flake.nixosModules.apps."gpg-tui" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gpg-tui ];
    };

  flake.nixosModules.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gpg-tui ];
    };
}
