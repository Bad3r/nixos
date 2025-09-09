{
  flake.nixosModules.apps.vim =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.vim ];
    };
}
