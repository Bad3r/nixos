{
  flake.nixosModules.apps."xfsprogs" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."xfsprogs" ];
    };
}
