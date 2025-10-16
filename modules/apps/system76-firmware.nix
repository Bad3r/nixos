{
  flake.nixosModules.apps."system76-firmware" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."system76-firmware" ];
    };
}
