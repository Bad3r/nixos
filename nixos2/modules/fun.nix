# modules/fun.nix

{
  flake.modules.homeManager.base =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        fastfetch
        lolcat
        bottom-rs
        btop-cuda
        cmatrix
        cowsay
        figlet
      ];
    };
}
