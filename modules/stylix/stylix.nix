{
  inputs,
  config,
  lib,
  ...
}:
let
  baseTheme = {
    enable = true;
    enableReleaseChecks = false;
    base16Scheme = lib.mkDefault "${inputs.tinted-schemes}/base16/onedark.yaml";
    polarity = lib.mkDefault "dark";
  };

  fontPackages = config.flake.lib.fonts.packages;
  monoLisaFonts =
    pkgs:
    let
      monolisa = (fontPackages pkgs).monolisa or pkgs.emptyDirectory;
    in
    {
      sansSerif = lib.mkDefault {
        package = monolisa;
        name = "MonoLisaText";
      };
      serif = lib.mkDefault {
        package = monolisa;
        name = "MonoLisaText";
      };
      monospace = lib.mkDefault {
        package = monolisa;
        name = "MonoLisaCode";
      };
      emoji = lib.mkDefault {
        package = pkgs.noto-fonts-color-emoji;
        name = "Noto Color Emoji";
      };
      sizes = lib.mkDefault {
        applications = 11;
        desktop = 12;
        popups = 11;
        terminal = 12;
      };
    };
in
{
  flake = {
    nixosModules = {
      base =
        { pkgs, ... }:
        {
          imports = [ inputs.stylix.nixosModules.stylix ];
          stylix = baseTheme // {
            fonts = monoLisaFonts pkgs;
            homeManagerIntegration.autoImport = false;
            targets = {
              gnome.enable = false;
              regreet.enable = false;
              grub.enable = false;
              # Enable Chromium theming (applies to Google Chrome via browser policies)
              chromium.enable = true;
              # The NixOS-scope target only enables a nixpkgs overlay that
              # patches gtksourceview 2/3/4/5 with the generated color scheme.
              # The hash change forces gtksourceview and every consumer
              # (planify, inkscape, ...) to rebuild from source on each nixpkgs
              # bump. The Home Manager target ships the same scheme as
              # user-scope data files, keeping the theming without rebuilds.
              gtksourceview.enable = false;
            };
          };
        };

      # end of nixosModules
    };

    homeManagerModules = {
      base =
        { pkgs, ... }:
        {
          imports = [ inputs.stylix.homeModules.stylix ];
          # Stylix's nixvim home-manager target adds a back-compat setter
          # `lib.stylix.nixvim.config = ... config.stylix.targets.nixvim.exportedModule`
          # whose value graph reaches `cfg.enable`, defined as
          # `config.lib.stylix.mkEnableTargetWith ...`. Evaluating
          # `home-manager.users.<u>.lib` therefore loops through itself.
          # Targets under modules/neovim/ (neovim, neovide, nixvim, nvf, vim) are
          # all unused in this configuration (nixvim theming uses onedark.nvim),
          # so disabling the whole hm.nix target group is safe and breaks the
          # cycle without losing functionality.
          disabledModules = [ "${inputs.stylix}/modules/neovim/hm.nix" ];
          stylix = baseTheme // {
            fonts = monoLisaFonts pkgs;
            overlays.enable = false;
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
          graphicalDesktop = osConfig != null && osConfig.services.graphical-desktop.enable;
          # Check which apps are enabled at NixOS level
          firefoxEnabled = lib.attrByPath [ "programs" "firefox" "extended" "enable" ] false osConfig;
          librewolfEnabled = lib.attrByPath [ "programs" "librewolf" "extended" "enable" ] false osConfig;
          mpvEnabled = lib.attrByPath [ "programs" "mpv" "extended" "enable" ] false osConfig;
          nushellEnabled = lib.attrByPath [ "programs" "nushell" "extended" "enable" ] false osConfig;
          zathuraEnabled = lib.attrByPath [ "programs" "zathura" "extended" "enable" ] false osConfig;
          geckoProfileNames = [
            "primary"
            "pentesting"
            "work"
          ];
          # Sidebery maps only a few Firefox theme colors (none on its settings
          # page) and hardcodes the rest: status, badge, and named colors, and
          # neutral white/black hover, selection, and scrollbar overlays.
          sideberyUserContent = with config.lib.stylix.colors.withHashtag; ''
            @-moz-document regexp("moz-extension://[^/]+/(sidebar|sidebery|page\\.[a-z]+|popup\\.[a-z-]+)/[a-z-]+\\.html.*") {
            	#root {
            		--status-ok: ${base0B} !important;
            		--status-err: ${base08} !important;
            		--status-active: ${base0D} !important;
            		--status-notice: ${base0C} !important;
            		--badge-bg: ${base0D} !important;
            		--badge-fg: ${base00} !important;
            		--badge-urgent-bg: ${base08} !important;
            		--badge-urgent-fg: ${base00} !important;
            		--frame-bg: ${base00} !important;
            		--frame-fg: ${base05} !important;
            		--frame-el-overlay-hover-bg: ${base01} !important;
            		--frame-el-overlay-clicked-bg: ${base02} !important;
            		--frame-el-overlay-selected-bg: ${base02} !important;
            		--frame-scrollbar-color: ${base03} !important;
            		--toolbar-bg: ${base00} !important;
            		--toolbar-fg: ${base05} !important;
            		--toolbar-fg-active: ${base0D} !important;
            		--toolbar-el-overlay-hover-bg: ${base01} !important;
            		--toolbar-el-overlay-clicked-bg: ${base02} !important;
            		--toolbar-el-overlay-active-bg: ${base02} !important;
            		--toolbar-el-overlay-selected-bg: ${base02} !important;
            		--toolbar-scrollbar-color: ${base03} !important;
            		--active-el-bg: ${base02} !important;
            		--active-el-fg: ${base05} !important;
            		--active-el-overlay-hover-bg: ${base03} !important;
            		--active-el-overlay-clicked-bg: ${base04} !important;
            		--popup-bg: ${base01} !important;
            		--popup-fg: ${base05} !important;
            		--popup-scrollbar-color: ${base03} !important;
            		--scroll-color: ${base03} !important;
            		--scroll-progress-bg: ${base0D} !important;
            		--tabs-progress-bg: ${base02} !important;
            		--tabs-notification-badge-dot-bg: ${base08} !important;
            		--tabs-notification-badge-count-bg: ${base08} !important;
            		--tabs-notification-badge-count-fg: ${base00} !important;
            		--btn-fg: ${base05} !important;
            	}

            	/* Bookmarks, history, and bottom-bar buttons share --frame-el-shadow;
            	   colorized tabs redeclare --tabs-activated-shadow on .Tab. */
            	.Tab {
            		--frame-el-shadow: inset 0 0 0 1px ${base00} !important;
            		--tabs-activated-shadow: inset 0 0 0 1px ${base03} !important;
            	}

            	#root.Setup {
            		--popup-shadow: 0 0 0 1px ${base02}, 0 1px 16px 0 #00000048 !important;
            		--border: ${base01} !important;
            	}

            	[data-color="inactive"] { --color: color-mix(in oklab, ${base05} 75%, ${base00}) !important; }
            	[data-color="blue"] { --color: ${base0D} !important; }
            	[data-color="turquoise"], [data-color="cyan"] { --color: ${base0C} !important; }
            	[data-color="green"] { --color: ${base0B} !important; }
            	[data-color="yellow"] { --color: ${base0A} !important; }
            	[data-color="orange"] { --color: ${base09} !important; }
            	[data-color="red"] { --color: ${base08} !important; }
            	[data-color="purple"] { --color: ${base0E} !important; }
            	/* Base16 has no pink; base0F is brown in most schemes and collides with red. */
            	[data-color="pink"] { --color: color-mix(in oklab, ${base08}, ${base0E}) !important; }

            	.ToggleInput .opt.-false::after,
            	.SelectInput .opt[data-none="true"]::after,
            	.btn.-warn::after {
            		background-color: ${base08} !important;
            	}

            	.ToggleInput .opt.-true::after {
            		background-color: ${base0B} !important;
            	}

            	/* The neutral underlay greys out the status tint. */
            	.ToggleInput .opt::before {
            		opacity: 0 !important;
            	}

            	.ToggleInput[data-active="true"] .opt.-true {
            		color: ${base0B} !important;
            	}

            	.ToggleInput[data-active="false"] .opt.-false {
            		color: ${base08} !important;
            	}

            	/* GitHub's black favicon as Gecko inlines it; CI-status variants differ and keep
            	   their colors. The mask is mark-github-16 from @primer/octicons (MIT). */
            	.Tab img.fav-icon[src^="data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMzIiIGhlaWdodD0iMzIiIHZpZXdCb3g9IjAgMCAzMiAzMiIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj4KPHBhdGggZmlsbC1ydWxlPSJldmVub2RkIiBjbGlwLXJ1bGU9ImV2ZW5vZGQiIGQ9Ik0xNiAwQzcuMTYgMCAwIDcuMTYgMCAxNkMwIDIzLjA4"] {
            		object-position: -100vw 0 !important;
            		background-color: ${base05} !important;
            		mask:
            			url('data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"%3E%3Cpath d="M6.766 11.328c-2.063-.25-3.516-1.734-3.516-3.656 0-.781.281-1.625.75-2.188-.203-.515-.172-1.609.063-2.062.625-.078 1.468.25 1.968.703.594-.187 1.219-.281 1.985-.281.765 0 1.39.094 1.953.265.484-.437 1.344-.765 1.969-.687.218.422.25 1.515.046 2.047.5.593.766 1.39.766 2.203 0 1.922-1.453 3.375-3.547 3.64.531.344.89 1.094.89 1.954v1.625c0 .468.391.734.86.547C13.781 14.359 16 11.53 16 8.03 16 3.61 12.406 0 7.984 0 3.563 0 0 3.61 0 8.031a7.88 7.88 0 0 0 5.172 7.422c.422.156.828-.125.828-.547v-1.25c-.219.094-.5.156-.75.156-1.031 0-1.64-.562-2.078-1.609-.172-.422-.36-.672-.719-.719-.187-.015-.25-.093-.25-.187 0-.188.313-.328.625-.328.453 0 .844.281 1.25.86.313.452.64.655 1.031.655s.641-.14 1-.5c.266-.265.47-.5.657-.656"/%3E%3C/svg%3E')
            			center / contain no-repeat !important;
            	}
            }

            @-moz-document regexp("moz-extension://[^/]+/sidebery/group\\.html.*") {
            	.tab,
            	.new-tab,
            	.pinned-tab {
            		background-color: ${base01} !important;
            		box-shadow: 0 0 0 1px ${base02} !important;
            	}

            	.tab:hover,
            	.new-tab:hover,
            	.pinned-tab:hover {
            		box-shadow: 0 0 0 1px ${base03} !important;
            	}
            }
          '';
          # Nova tints URL bar boxes (identity label, page and extension actions)
          # with currentColor, which reads lighter than the field.
          urlbarUserChrome = with config.lib.stylix.colors.withHashtag; ''
            :root {
            	--urlbar-box-background-color: ${base02} !important;
            	--urlbar-box-background-color-focus: ${base02} !important;
            	--urlbar-box-background-color-hover: ${base03} !important;
            	--urlbar-box-background-color-active: ${base04} !important;
            }
          '';
          mkThemeColor = name: {
            r = config.lib.stylix.colors."${name}-rgb-r";
            g = config.lib.stylix.colors."${name}-rgb-g";
            b = config.lib.stylix.colors."${name}-rgb-b";
          };
          # Base16 has no slot darker than base00; mix it 12% toward black.
          urlbarFill = lib.mapAttrs (_: c: toString ((lib.toInt c * 88 + 50) / 100)) (mkThemeColor "base00");
          geckoProfiles = lib.genAttrs geckoProfileNames (_: {
            extensions.settings."FirefoxColor@mozilla.com".settings.theme.colors = {
              # Sidebery paints its background with the theme's frame color, not its sidebar color.
              frame = lib.mkForce (mkThemeColor "base00");
              toolbar_field = lib.mkForce urlbarFill;
              toolbar_field_focus = lib.mkForce urlbarFill;
              toolbar_field_border = lib.mkForce (mkThemeColor "base00");
              toolbar_field_border_focus = lib.mkForce (mkThemeColor "base00");
              # Nova outlines #sidebar-box in this color under a theme.
              sidebar_border = lib.mkForce (mkThemeColor "base00");
              # Sidebery outlines its menus and draws their separators in this color.
              popup_border = lib.mkForce (mkThemeColor "base02");
            };
            userChrome = lib.mkAfter urlbarUserChrome;
            userContent = lib.mkAfter sideberyUserContent;
          });
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
              id = "remmina-tray";
              source = ./icons/remmina-tray.svg;
              names = [ "org.remmina.Remmina-status" ];
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
          config = lib.mkIf graphicalDesktop {
            stylix = {
              # Opacity settings for GUI applications
              opacity = lib.genAttrs [ "applications" "desktop" "popups" "terminal" ] (_n: 1.0);

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
                  profileNames = geckoProfileNames;
                  colorTheme.enable = true; # uses Firefox Color extension from NUR
                  firefoxGnomeTheme.enable = false;
                  fonts.enable = false;
                };

                # LibreWolf profile theming (only if enabled)
                librewolf = lib.mkIf librewolfEnabled {
                  profileNames = geckoProfileNames;
                  colorTheme.enable = true; # uses Firefox Color extension from NUR
                  firefoxGnomeTheme.enable = false;
                  fonts.enable = false;
                };

                # Zathura PDF viewer theming (only if enabled)
                zathura.enable = zathuraEnabled;

                # Nushell theming (only if enabled)
                nushell.enable = nushellEnabled;
              };
            };

            # Keep Dunst icon size centralized with Stylix icon theme settings.
            services.dunst.iconTheme.size = "32x32";

            xdg.dataFile = lib.mkIf (
              (config.gtk.iconTheme.name or null) == "Qogir-Dark"
            ) qogirDarkThemedIconFiles;

            programs = {
              firefox.profiles = lib.mkIf firefoxEnabled geckoProfiles;
              librewolf.profiles = lib.mkIf librewolfEnabled geckoProfiles;

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
                # Track the shared terminal size so a host re-picking
                # stylix.fonts.sizes.terminal is not silently overridden here.
                settings.font_size = config.stylix.fonts.sizes.terminal;
                extraConfig = "modify_font cell_height 100%";
              };
            };

            # Additional font packages
            home.packages = [
              pkgs.google-fonts
              pkgs.maple-mono.NF
            ];

            # Set dark mode preference for GNOME/libadwaita apps
            dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";

            gtk = {
              # Legacy GTK3 apps still use this key for dark theme variants
              gtk3.extraConfig.gtk-application-prefer-dark-theme = true;
              # Read-only at runtime: bookmarks added from a file chooser do not persist.
              gtk3.bookmarks = [
                "file:///data/Docs Docs"
                "file:///data data"
                "file:///data/Projects Projects"
              ];
              # GTK settings.ini drives plain GTK apps that do not consume GNOME dconf
              colorScheme = "dark";
            };
          };
        };
    };

    lib.nixvim.astrea = nixvimArgs: {
      # https://github.com/danth/stylix/pull/415#issuecomment-2832398958
      imports = lib.optional (nixvimArgs ? homeConfig) nixvimArgs.homeConfig.lib.stylix.nixvim.config;
    };
  };
}
