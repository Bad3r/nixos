{
  flake.nixosModules.apps."autotiling-rs" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.autotiling-rs ];
    };
}
