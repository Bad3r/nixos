{
  flake.nixosModules.apps."kmod" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.kmod ];
    };
}
