{
  flake.nixosModules.apps."desktop-file-utils" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.desktop-file-utils ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.desktop-file-utils ];
    };
}
