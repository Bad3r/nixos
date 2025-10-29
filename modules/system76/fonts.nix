_: {
  configurations.nixos.system76.module =
    { pkgs, ... }:
    {
      fonts = {
        enableDefaultPackages = true;
        packages = with pkgs; [
          noto-fonts
          noto-fonts-cjk-sans
          noto-fonts-color-emoji
          liberation_ttf
          fira-code
          fira-code-symbols
          jetbrains-mono
          font-awesome
          nerd-fonts.jetbrains-mono
          nerd-fonts.fira-code
          ubuntu-classic
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
