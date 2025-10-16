{
  flake.nixosModules.apps."du-dust" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."du-dust" ];
    };
}
