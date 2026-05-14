{
  inputs,
  lib,
  ...
}:
let
  baseTheme = {
    enable = true;
    base16Scheme = lib.mkDefault "${inputs.tinted-schemes}/base16/onedark.yaml";
    polarity = lib.mkDefault "dark";
  };

  monoLisaFonts = pkgs: popupSize: {
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
      popups = popupSize;
      terminal = 12;
    };
  };
in
{
  flake = {
    nixosModules = {
      base = {
        imports = [ inputs.stylix.nixosModules.stylix ];
        stylix = baseTheme // {
          homeManagerIntegration.autoImport = false;
          targets = {
            gnome.enable = false;
            regreet.enable = false;
            # Enable Chromium theming (applies to Google Chrome via browser policies)
            chromium.enable = true;
          };
        };
      };

      workstation =
        { pkgs, ... }:
        {
          stylix = {
            # Opacity settings for desktop systems
            opacity = lib.genAttrs [ "applications" "desktop" "popups" "terminal" ] (_n: 1.0);

            # Font configuration for desktop systems
            fonts = monoLisaFonts pkgs 12;
          };
          fonts.fontconfig.enable = true;
        };

      # end of nixosModules
    };

    homeManagerModules = {
      base = {
        imports = [ inputs.stylix.homeModules.stylix ];
        stylix = baseTheme // {
          targets = {
            kde.enable = false;
            gnome.enable = false;
            sway.enable = false;
            river.enable = false;
            swaylock.enable = false;
          };
        };
      };

      apps.stylix-gui =
        {
          config,
          osConfig,
          pkgs,
          ...
        }:
        let
          # Check which apps are enabled at NixOS level
          firefoxEnabled = lib.attrByPath [ "programs" "firefox" "extended" "enable" ] false osConfig;
          librewolfEnabled = lib.attrByPath [ "programs" "librewolf" "extended" "enable" ] false osConfig;
          mpvEnabled = lib.attrByPath [ "programs" "mpv" "extended" "enable" ] false osConfig;
          zathuraEnabled = lib.attrByPath [ "programs" "zathura" "extended" "enable" ] false osConfig;
          qogirDarkFixedIconSizes = {
            "16/apps" = 16;
            "22/apps" = 22;
            "32/apps" = 32;
            "48/apps" = 48;
            "16@2x/apps" = 32;
            "22@2x/apps" = 44;
            "32@2x/apps" = 64;
            "48@2x/apps" = 96;
          };
          qogirDarkPanelFixedIconSizes = {
            "16/panel" = 16;
            "22/panel" = 22;
            "24/panel" = 24;
            "16@2x/panel" = 32;
            "22@2x/panel" = 44;
            "24@2x/panel" = 48;
          };
          qogirDarkScalableIconDirs = [
            "scalable/apps"
            "scalable@2x/apps"
          ];
          qogirDarkPanelScalableIconDirs = [
            "scalable/panel"
            "scalable@2x/panel"
          ];
          qogirDarkIconDefinitions = [
            {
              id = "onepassword";
              source = ./icons/1password-outline.svg;
              names = [
                "1password"
                "appimagekit-1password"
                "com.onepassword.OnePassword"
              ];
            }
            {
              id = "electron-mail";
              source = ./icons/electron-mail-outline.svg;
              names = [ "electron-mail" ];
            }
            {
              id = "protonvpn-tray";
              source = ./icons/protonvpn-tray.svg;
              names = [ "protonvpn-tray" ];
              fixedIconSizes = qogirDarkPanelFixedIconSizes;
              scalableIconDirs = qogirDarkPanelScalableIconDirs;
            }
            {
              id = "teams-for-linux";
              source = ./icons/teams-for-linux.svg;
              names = [ "teams-for-linux" ];
            }
            {
              id = "udiskie-tray";
              source = ./icons/udiskie-tray.svg;
              names = [ "drive-removable-media-usb-panel" ];
              fixedIconSizes = qogirDarkPanelFixedIconSizes;
              scalableIconDirs = qogirDarkPanelScalableIconDirs;
            }
          ];
          qogirDarkIconSet =
            {
              id,
              source,
              names,
              fixedIconSizes ? qogirDarkFixedIconSizes,
              scalableIconDirs ? qogirDarkScalableIconDirs,
            }:
            pkgs.runCommand "qogir-dark-${id}-icons"
              {
                nativeBuildInputs = [ pkgs.librsvg ];
              }
              ''
                renderIcon() {
                  local size="$1"
                  local input="$2"
                  local output="$3"
                  local glyphSize="$((size * 11 / 16))"
                  local offset="$(((size - glyphSize) / 2))"

                  rsvg-convert \
                    --page-width "$size" \
                    --page-height "$size" \
                    --width "$glyphSize" \
                    --height "$glyphSize" \
                    --left "$offset" \
                    --top "$offset" \
                    --keep-aspect-ratio \
                    "$input" > "$output"
                }

                for iconName in ${lib.escapeShellArgs names}; do
                  ${lib.concatMapStringsSep "\n" (iconDir: ''
                    mkdir -p "$out/${iconDir}"
                    install -m 444 ${source} "$out/${iconDir}/$iconName.svg"
                  '') scalableIconDirs}

                  ${lib.concatStringsSep "\n" (
                    lib.mapAttrsToList (iconDir: size: ''
                      mkdir -p "$out/${iconDir}"
                      renderIcon ${toString size} ${source} "$out/${iconDir}/$iconName.png"
                    '') fixedIconSizes
                  )}
                done
              '';
          qogirDarkIconFiles =
            {
              id,
              source,
              names,
              fixedIconSizes ? qogirDarkFixedIconSizes,
              scalableIconDirs ? qogirDarkScalableIconDirs,
            }:
            let
              renderedIcons = qogirDarkIconSet {
                inherit
                  fixedIconSizes
                  id
                  names
                  scalableIconDirs
                  source
                  ;
              };
              scalableFiles = lib.concatMap (
                iconName:
                map (iconDir: {
                  name = "icons/Qogir-Dark/${iconDir}/${iconName}.svg";
                  value.source = "${renderedIcons}/${iconDir}/${iconName}.svg";
                }) scalableIconDirs
              ) names;
              fixedFiles = lib.concatMap (
                iconName:
                lib.mapAttrsToList (iconDir: _size: {
                  name = "icons/Qogir-Dark/${iconDir}/${iconName}.png";
                  value.source = "${renderedIcons}/${iconDir}/${iconName}.png";
                }) fixedIconSizes
              ) names;
            in
            scalableFiles ++ fixedFiles;
          qogirDarkThemedIconFiles = lib.listToAttrs (
            lib.concatMap qogirDarkIconFiles qogirDarkIconDefinitions
          );
        in
        {
          stylix = {
            # Opacity settings for GUI applications
            opacity = lib.genAttrs [ "applications" "desktop" "popups" "terminal" ] (_n: 1.0);

            # Font configuration for GUI applications
            fonts = monoLisaFonts pkgs 11;

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
              gtk.flatpakSupport.enable = true;

              # Qt theming (Kvantum + qtct)
              qt.enable = true;

              # Firefox profile theming (only if enabled)
              firefox = lib.mkIf firefoxEnabled {
                profileNames = [
                  "primary"
                  "pentesting"
                  "work"
                ];
                colorTheme.enable = true; # uses Firefox Color extension from NUR
                firefoxGnomeTheme.enable = false;
                fonts.enable = false;
              };

              # LibreWolf profile theming (only if enabled)
              librewolf = lib.mkIf librewolfEnabled {
                profileNames = [
                  "primary"
                  "pentesting"
                  "work"
                ];
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

          xdg.dataFile = lib.mkIf (
            (config.gtk.iconTheme.name or null) == "Qogir-Dark"
          ) qogirDarkThemedIconFiles;

          programs = {
            mpv.scriptOpts.modernz =
              lib.mkIf (mpvEnabled && config.stylix.enable && config.stylix.targets.mpv.enable)
                (
                  with config.lib.stylix.colors.withHashtag;
                  {
                    middle_buttons_color = lib.mkForce base00;
                    playpause_color = lib.mkForce base00;
                    seekbarfg_color = lib.mkForce base00;
                    seek_handle_color = lib.mkForce base00;
                    seek_handle_border_color = lib.mkForce base00;
                  }
                );

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

          # Legacy GTK3 apps still use this key for dark theme variants
          gtk.gtk3.extraConfig.gtk-application-prefer-dark-theme = true;
          # GTK settings.ini drives plain GTK apps that do not consume GNOME dconf
          gtk.colorScheme = "dark";
        };
    };

    lib.nixvim.astrea = nixvimArgs: {
      # https://github.com/danth/stylix/pull/415#issuecomment-2832398958
      imports = lib.optional (nixvimArgs ? homeConfig) nixvimArgs.homeConfig.lib.stylix.nixvim.config;
    };
  };
}
