{
  configurations.nixos.system76.module =
    { pkgs, lib, ... }:
    {
      stylix.base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark-medium.yaml";
      stylix.fonts = {
        serif = lib.mkForce {
          package = pkgs.dejavu_fonts;
          name = "DejaVu Serif";
        };
        sansSerif = lib.mkForce {
          package = pkgs.dejavu_fonts;
          name = "DejaVu Sans";
        };
        monospace = lib.mkForce {
          package = pkgs.nerd-fonts.jetbrains-mono;
          name = "JetBrainsMono Nerd Font";
        };
        emoji = lib.mkForce {
          package = pkgs.noto-fonts-emoji;
          name = "Noto Color Emoji";
        };
      };
    };
}
