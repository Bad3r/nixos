_: {
  configurations.nixos.tec.module =
    { pkgs, ... }:
    {
      fonts = {
        enableDefaultPackages = true;
        packages = with pkgs; [
          noto-fonts
          noto-fonts-cjk-sans
          noto-fonts-emoji
          liberation_ttf
          fira-code
          fira-code-symbols
          jetbrains-mono
          font-awesome
          nerd-fonts.jetbrains-mono
          nerd-fonts.fira-code
          ubuntu_font_family
        ];

        fontconfig = {
          defaultFonts = {
            serif = [ "JetBrainsMono Nerd Font" ];
            sansSerif = [ "JetBrainsMono Nerd Font" ];
            monospace = [ "JetBrainsMono Nerd Font Mono" ];
            emoji = [ "Noto Color Emoji" ];
          };
        };
      };
    };
}
