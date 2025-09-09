{
  flake.modules.nixos.apps.neovim =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.neovim ];
    };
}
