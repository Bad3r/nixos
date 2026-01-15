{
  inputs,
  lib,
  ...
}:
let
  mkMonolisaPlaceholder =
    pkgs:
    pkgs.runCommand "monolisa-placeholder-fonts" { } ''
      mkdir -p "$out/share/fonts/truetype"
    '';
in
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
        let
          monolisaPackage = mkMonolisaPlaceholder pkgs;
        in
        {
          stylix = {
            # Opacity settings for desktop systems
            opacity = lib.genAttrs [ "applications" "desktop" "popups" "terminal" ] (_n: 1.0);

            # Font configuration for desktop systems
            fonts = {
              sansSerif = lib.mkDefault {
                package = monolisaPackage;
                name = "MonoLisa";
              };
              serif = lib.mkDefault {
                package = monolisaPackage;
                name = "MonoLisa";
              };
              monospace = {
                package = monolisaPackage;
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
        let
          monolisaPackage = mkMonolisaPlaceholder pkgs;
        in
        {
          stylix = {
            # Opacity settings for GUI applications
            opacity = lib.genAttrs [ "applications" "desktop" "popups" "terminal" ] (_n: 1.0);

            # Font configuration for GUI applications
            fonts = {
              sansSerif = lib.mkDefault {
                package = monolisaPackage;
                name = "MonoLisa";
              };
              serif = lib.mkDefault {
                package = monolisaPackage;
                name = "MonoLisa";
              };
              monospace = {
                package = monolisaPackage;
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

            # Firefox profile theming
            targets.firefox = {
              profileNames = [ "primary" ];
              colorTheme.enable = true; # uses Firefox Color extension from NUR
              firefoxGnomeTheme.enable = false; # disabled for testing
            };
          };

          programs = {
            firefox = {
              profiles = {
                primary = {
                  settings = {
                    "font.name-list.monospace.x-western" =
                      "MonoLisa, Symbols Nerd Font Mono, Symbols Nerd Font, Font Awesome 6 Free, Font Awesome 6 Brands";
                    "font.name-list.sans-serif.x-western" =
                      "MonoLisa, Symbols Nerd Font, Symbols Nerd Font Mono, Font Awesome 6 Free, Font Awesome 6 Brands";
                    "font.name-list.serif.x-western" =
                      "MonoLisa, Symbols Nerd Font, Symbols Nerd Font Mono, Font Awesome 6 Free, Font Awesome 6 Brands";
                    "font.size.variable.x-western" = lib.mkForce 12;
                    "font.size.monospace.x-western" = lib.mkForce 12;
                  };
                  userContent = ''
                    @-moz-document url-prefix(http://), url-prefix(https://), url-prefix(file://), url-prefix(chrome://) {
                      body,
                      button,
                      input,
                      select,
                      textarea {
                        line-height: 1.6 !important;
                      }
                    }
                  '';
                };
              };
            };
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
