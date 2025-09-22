{
  flake.nixosModules.apps."nix-prefetch-github" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.nix-prefetch-github ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.nix-prefetch-github ];
    };
}
