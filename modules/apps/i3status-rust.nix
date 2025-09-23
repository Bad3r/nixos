{
  flake.nixosModules.apps."i3status-rust" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.i3status-rust ];
    };
}
