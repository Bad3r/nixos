{
  flake.nixosModules.apps."dosfstools" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.dosfstools ];
    };
}
