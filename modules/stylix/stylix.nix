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
          # Enable Chromium theming (applies to Google Chrome via browser policies)
          targets.chromium.enable = true;
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
                applications = 11;
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

      apps.stylix-gui =
        { osConfig, pkgs, ... }:
        let
          # Check which apps are enabled at NixOS level
          firefoxEnabled = lib.attrByPath [ "programs" "firefox" "extended" "enable" ] false osConfig;
          floorpEnabled = lib.attrByPath [ "programs" "floorp" "extended" "enable" ] false osConfig;
          zathuraEnabled = lib.attrByPath [ "programs" "zathura" "extended" "enable" ] false osConfig;
        in
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
                applications = 11;
                desktop = 12;
                popups = 11;
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
              # GTK theming (adw-gtk3 theme + CSS)
              gtk.enable = true;

              # Qt theming (Kvantum + qtct)
              qt.enable = true;

              # Firefox profile theming (only if enabled)
              firefox = lib.mkIf firefoxEnabled {
                profileNames = [ "primary" ];
                colorTheme.enable = true; # uses Firefox Color extension from NUR
                firefoxGnomeTheme.enable = false;
                fonts.enable = false;
              };

              # Floorp profile theming (only if enabled)
              floorp = lib.mkIf floorpEnabled {
                profileNames = [ "primary" ];
                colorTheme.enable = true; # uses Firefox Color extension from NUR
                firefoxGnomeTheme.enable = false;
                fonts.enable = false;
              };

              # Zathura PDF viewer theming (only if enabled)
              zathura.enable = zathuraEnabled;
            };
          };

          # Keep Dunst icon size centralized with Stylix icon theme settings.
          services.dunst.iconTheme.size = "32x32";

          programs = {
            kitty = {
              settings.font_size = 12;
              extraConfig = "modify_font cell_height 100%";
            };
          };

          # Additional font packages
          home.packages = [
            pkgs.google-fonts
            pkgs.gucharmap
          ];

          # Set dark mode preference for GNOME/libadwaita apps
          dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";

          # Legacy GTK3 apps still use this key for dark theme variants.
          gtk.gtk3.extraConfig.gtk-application-prefer-dark-theme = true;
        };
    };

    lib.nixvim.astrea = nixvimArgs: {
      # https://github.com/danth/stylix/pull/415#issuecomment-2832398958
      imports = lib.optional (nixvimArgs ? homeConfig) nixvimArgs.homeConfig.lib.stylix.nixvim.config;
    };
  };
}
