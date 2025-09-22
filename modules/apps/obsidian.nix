{
  nixpkgs.allowedUnfreePackages = [ "obsidian" ];

  flake.nixosModules.apps.obsidian =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.obsidian ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.obsidian ];
    };
}
