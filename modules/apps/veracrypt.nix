{
  nixpkgs.allowedUnfreePackages = [ "veracrypt" ];

  flake.nixosModules.apps.veracrypt =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.veracrypt ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.veracrypt ];
    };
}
