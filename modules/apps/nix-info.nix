{
  flake.nixosModules.apps."nix-info" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."nix-info" ];
    };
}
