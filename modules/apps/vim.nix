{
  flake.modules.nixos.apps.vim =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.vim ];
    };
}
