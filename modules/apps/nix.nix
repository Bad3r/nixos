{
  flake.nixosModules.apps."nix" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.nix ];
    };
}
