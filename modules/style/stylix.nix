{
  inputs,
  lib,
  ...
}:
{
  flake.modules = {
    nixos.base = {
      imports = [ inputs.stylix.nixosModules.stylix ];
      stylix = {
        enable = true;
        homeManagerIntegration.autoImport = false;
        # Consolidated stylix configuration
        base16Scheme = lib.mkDefault "${inputs.tinted-schemes}/base16/gruvbox-dark-medium.yaml";
        polarity = lib.mkDefault "dark";
        targets.grub.enable = false;
      };
    };

    nixos.pc =
      { pkgs, ... }:
      {
        stylix = {
          # Opacity settings for desktop systems
          opacity = lib.genAttrs [ "applications" "desktop" "popups" "terminal" ] (n: 0.85);

          # Font configuration for desktop systems
          fonts = {
            sansSerif = lib.mkDefault {
              package = pkgs.open-dyslexic;
              name = "OpenDyslexic";
            };
            serif = lib.mkDefault {
              package = pkgs.open-dyslexic;
              name = "OpenDyslexic";
            };
            monospace = {
              package = pkgs.nerd-fonts.open-dyslexic;
              name = "OpenDyslexicM Nerd Font Mono";
            };
            emoji = {
              package = pkgs.google-fonts;
              name = "Noto Color Emoji";
            };
            sizes = {
              applications = 12;
              desktop = 12;
              popups = 12;
              terminal = 12;
            };
          };
        };
        fonts.fontconfig.enable = true;
      };

    homeManager.base = {
      imports = [ inputs.stylix.homeModules.stylix ];
      stylix = {
        enable = true;
        # Consolidated stylix configuration
        base16Scheme = lib.mkDefault "${inputs.tinted-schemes}/base16/gruvbox-dark-medium.yaml";
        polarity = lib.mkDefault "dark";
      };
    };

    homeManager.gui =
      { pkgs, ... }:
      {
        stylix = {
          # Opacity settings for GUI applications
          opacity = lib.genAttrs [ "applications" "desktop" "popups" "terminal" ] (n: 0.85);

          # Font configuration for GUI applications
          fonts = {
            sansSerif = lib.mkDefault {
              package = pkgs.open-dyslexic;
              name = "OpenDyslexic";
            };
            serif = lib.mkDefault {
              package = pkgs.open-dyslexic;
              name = "OpenDyslexic";
            };
            monospace = {
              package = pkgs.nerd-fonts.open-dyslexic;
              name = "OpenDyslexicM Nerd Font Mono";
            };
            emoji = {
              package = pkgs.google-fonts;
              name = "Noto Color Emoji";
            };
            sizes = {
              applications = 12;
              desktop = 12;
              popups = 12;
              terminal = 12;
            };
          };

          # Firefox profile theming
          targets.firefox.profileNames = [ "primary" ];
        };

        # Additional font packages
        home.packages = [
          pkgs.google-fonts
          pkgs.gucharmap
          pkgs.nerd-fonts.jetbrains-mono
        ];
      };

    nixOnDroid.base = {
      imports = [ inputs.stylix.nixOnDroidModules.stylix ];
      stylix = {
        enable = true;
        base16Scheme = lib.mkDefault "${inputs.tinted-schemes}/base16/gruvbox-dark-medium.yaml";
        polarity = lib.mkDefault "dark";
      };
    };

    nixvim.astrea = nixvimArgs: {
      # https://github.com/danth/stylix/pull/415#issuecomment-2832398958
      imports = lib.optional (nixvimArgs ? homeConfig) nixvimArgs.homeConfig.lib.stylix.nixvim.config;
    };
  };
}
