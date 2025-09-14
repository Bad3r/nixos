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
          # Use gruvbox dark theme by default
          base16Scheme = lib.mkDefault "${inputs.tinted-schemes}/base16/gruvbox-dark-medium.yaml";
          polarity = lib.mkDefault "dark";
          targets.grub.enable = false;
        };
      };

      pc =
        { pkgs, ... }:
        {
          stylix = {
            # Opacity settings for desktop systems
            opacity = lib.genAttrs [ "applications" "desktop" "popups" "terminal" ] (_n: 1.0);

            # Font configuration for desktop systems
            fonts = {
              sansSerif = lib.mkDefault {
                package = pkgs.nerd-fonts.fira-code;
                name = "Fira Code Nerd Font";
              };
              serif = lib.mkDefault {
                package = pkgs.nerd-fonts.fira-code;
                name = "Fira Code Nerd Font";
              };
              monospace = {
                package = pkgs.nerd-fonts.fira-code;
                name = "Fira Code Nerd Font";
              };
              emoji = {
                package = pkgs.fira-code-symbols;
                name = "Fira Code Symbols";
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
          # Use gruvbox dark theme by default
          base16Scheme = lib.mkDefault "${inputs.tinted-schemes}/base16/gruvbox-dark-medium.yaml";
          polarity = lib.mkDefault "dark";
          targets.kde.enable = false;
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
                package = pkgs.fira-code;
                name = "Fira Code";
              };
              serif = lib.mkDefault {
                package = pkgs.fira-code;
                name = "Fira Code";
              };
              monospace = {
                package = pkgs.nerd-fonts.fira-code;
                name = "Fira Code Nerd Font";
              };
              emoji = {
                package = pkgs.fira-code-symbols;
                name = "Fira Code symbols";
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
            targets.firefox.firefoxGnomeTheme.enable = true;
          };

          # Additional font packages
          home.packages = [
            pkgs.google-fonts
            pkgs.gucharmap
            pkgs.nerd-fonts.jetbrains-mono
          ];
        };
    };

    lib.nixvim.astrea = nixvimArgs: {
      # https://github.com/danth/stylix/pull/415#issuecomment-2832398958
      imports = lib.optional (nixvimArgs ? homeConfig) nixvimArgs.homeConfig.lib.stylix.nixvim.config;
    };
  };
}
