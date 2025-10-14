{
  flake.nixosModules.apps."libvirt" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."libvirt" ];
    };
}
