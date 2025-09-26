{
  flake.nixosModules.apps."nix-tree" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."nix-tree" ];
    };
}
