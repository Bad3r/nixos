{
  flake.nixosModules.apps."texinfo-interactive" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.texinfoInteractive ];
    };
}
