{
  flake.nixosModules.apps."ventoy" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."ventoy" ];
    };
}
