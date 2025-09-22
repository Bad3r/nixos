{
  nixpkgs.allowedUnfreePackages = [ "brave" ];

  flake.nixosModules.apps.brave =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.brave ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.brave ];
    };
}
