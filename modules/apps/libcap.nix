{
  flake.nixosModules.apps."libcap" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.libcap ];
    };
}
