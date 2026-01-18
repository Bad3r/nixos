{
  inputs,
  lib,
  ...
}:
{
  flake = {
    nixosModules = {
      base = {
        imports = [ inputs.stylix.nixosModules.stylix ];
        stylix = {
          enable = true;
          homeManagerIntegration.autoImport = false;
          # Use OneDark theme by default
          base16Scheme = lib.mkDefault "${inputs.tinted-schemes}/base16/onedark.yaml";
          polarity = lib.mkDefault "dark";
          targets.grub.enable = false;
        };
      };

      workstation =
        { pkgs, ... }:
        {
          stylix = {
            # Opacity settings for desktop systems
            opacity = lib.genAttrs [ "applications" "desktop" "popups" "terminal" ] (_n: 1.0);

            # Font configuration for desktop systems
            fonts = {
              sansSerif = lib.mkDefault {
                package = pkgs.emptyDirectory;
                name = "MonoLisa";
              };
              serif = lib.mkDefault {
                package = pkgs.emptyDirectory;
                name = "MonoLisa";
              };
              monospace = {
                package = pkgs.emptyDirectory;
                name = "MonoLisa";
              };
              emoji = {
                package = pkgs.noto-fonts-color-emoji;
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

      # end of nixosModules
    };

    homeManagerModules = {
      base = {
        imports = [ inputs.stylix.homeModules.stylix ];
        stylix = {
          enable = true;
          # Use OneDark theme by default
          base16Scheme = lib.mkDefault "${inputs.tinted-schemes}/base16/onedark.yaml";
          polarity = lib.mkDefault "dark";

        };
      };

      gui =
        { pkgs, ... }:
        {
          stylix = {
            # Opacity settings for GUI applications
            opacity = lib.genAttrs [ "applications" "desktop" "popups" "terminal" ] (_n: 1.0);

            # Font configuration for GUI applications
            fonts = {
              sansSerif = lib.mkDefault {
                package = pkgs.emptyDirectory;
                name = "MonoLisa";
              };
              serif = lib.mkDefault {
                package = pkgs.emptyDirectory;
                name = "MonoLisa";
              };
              monospace = {
                package = pkgs.emptyDirectory;
                name = "MonoLisa";
              };
              emoji = {
                package = pkgs.noto-fonts-color-emoji;
                name = "Noto Color Emoji";
              };
              sizes = {
                applications = 12;
                desktop = 12;
                popups = 12;
                terminal = 12;
              };
            };

            # Icon theme configuration
            icons = {
              enable = true;
              package = pkgs.qogir-icon-theme;
              dark = "Qogir-Dark";
              light = "Qogir-Light";
            };

            # Application theming targets
            targets = {
              # Firefox profile theming
              firefox = {
                profileNames = [ "primary" ];
                colorTheme.enable = true; # uses Firefox Color extension from NUR
                firefoxGnomeTheme.enable = false;
                fonts.enable = false;
              };

              # Floorp profile theming (same as Firefox)
              floorp = {
                profileNames = [ "primary" ];
                colorTheme.enable = true; # uses Firefox Color extension from NUR
                firefoxGnomeTheme.enable = false;
                fonts.enable = false;
              };

              # Zathura PDF viewer theming
              zathura.enable = true;
            };
          };

          programs = {
            kitty = {
              settings = {
                font_size = 12;
                line_height = 1.6;
              };
            };
          };

          # Additional font packages
          home.packages = [
            pkgs.google-fonts
            pkgs.gucharmap
          ];
        };
    };

    lib.nixvim.astrea = nixvimArgs: {
      # https://github.com/danth/stylix/pull/415#issuecomment-2832398958
      imports = lib.optional (nixvimArgs ? homeConfig) nixvimArgs.homeConfig.lib.stylix.nixvim.config;
    };
  };
}
