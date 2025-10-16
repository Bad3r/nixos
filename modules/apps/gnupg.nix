{
  flake.nixosModules.apps."gnupg" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gnupg ];
    };
}
