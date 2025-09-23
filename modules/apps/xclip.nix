{
  flake.nixosModules.apps.xclip =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.xclip ];
    };
}
