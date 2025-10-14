{
  flake.nixosModules.apps."keepassxc" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.keepassxc ];
    };
}
