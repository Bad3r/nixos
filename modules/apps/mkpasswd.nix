{
  flake.nixosModules.apps."mkpasswd" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.mkpasswd ];
    };
}
