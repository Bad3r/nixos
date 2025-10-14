{
  flake.nixosModules.apps."e2fsprogs" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.e2fsprogs ];
    };
}
