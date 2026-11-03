/*
  Package: thunderbird
  Description: Home Manager integration for Thunderbird profile and account settings.
  Homepage: https://thunderbird.net/
  Documentation: https://nix-community.github.io/home-manager/options.xhtml#opt-programs.thunderbird.enable
  Repository: https://github.com/nix-community/home-manager

  Notes:
    * Declares a default `main` profile to support declarative Thunderbird state.
    * Themes the profile like VS Code Dark 2026 by remapping Thunderbird's own
      layout tokens in userChrome.css; a static theme add-on cannot be enabled
      declaratively, since Thunderbird installs every theme disabled.
*/
_: {
  flake.homeManagerModules.apps.thunderbird =
    {
      config,
      osConfig,
      lib,
      pkgs,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "thunderbird" "extended" "enable" ] false osConfig;
      colors = config.lib.stylix.colors.withHashtag;

      # VS Code Dark 2026 colors with no base16 slot.
      palette = {
        focusBorder = "#3994bc"; # focusBorder, tab.activeBorderTop
        link = "#48a0c7"; # textLink.foreground
        listSelection = "#297aa0"; # quickInputList.focusBackground
        listSelectionText = "#ffffff"; # quickInputList.focusForeground
        quickInput = "#202122"; # quickInput.background
        activeItem = "#313233"; # activityBar.activeBackground
      };

      # Message list and reader on base00 like the editor; folder pane,
      # toolbars, and tabs on base01 like the sidebar and title bar.
      layoutTokens = with colors; ''
        :root {
        	--lwt-accent-color: ${base01} !important;
        	--layout-background-0: ${base00} !important;
        	--layout-background-1: ${base01} !important;
        	--layout-background-2: ${base01} !important;
        	--layout-background-3: ${base02} !important;
        	--layout-background-4: ${palette.activeItem} !important;
        	--layout-color-0: ${base07} !important;
        	--layout-color-1: ${base05} !important;
        	--layout-color-2: ${base04} !important;
        	--layout-color-3: ${base03} !important;
        	--layout-border-0: ${base02} !important;
        	--layout-border-1: ${base02} !important;
        	--layout-border-2: ${base03} !important;
        	--color-surface-base: ${base00} !important;
        	--color-surface-subtle: ${palette.quickInput} !important;
        	--color-surface-lower: ${base01} !important;
        	--color-surface-border: ${base02} !important;
        	--color-surface-border-intense: ${base02} !important;
        	--toolbar-background-color: ${base01} !important;
        	--toolbar-field-background-color: ${base00} !important;
        	--toolbar-field-border-color: ${base02} !important;
        	--toolbar-field-focus-border-color: ${palette.focusBorder} !important;
        	--chrome-content-separator-color: ${base02} !important;
        	--sidebar-background-color: ${base01} !important;
        	--sidebar-border-color: ${base02} !important;
        	--selected-item-color: ${palette.listSelection} !important;
        	--selected-item-text-color: ${palette.listSelectionText} !important;
        	--focus-outline-color: ${palette.focusBorder} !important;
        	--link-color: ${palette.link} !important;
        	--tree-view-bg: ${base00} !important;
        	--tree-pane-background: ${base00} !important;
        	--tree-card-border-focus: ${palette.focusBorder} !important;
        	--listbox-selected-bg: ${palette.activeItem} !important;
        	--folderpane-unread-count-background: ${base02} !important;
        	--folderpane-unread-count-text: ${base05} !important;
        	--folderpane-unread-new-count-background: ${palette.focusBorder} !important;
        	--tabline-color: ${palette.focusBorder} !important;
        	--tabs-toolbar-background-color: ${base01} !important;
        	--tabs-toolbar-box-shadow: none !important;
        	scrollbar-color: ${base03} transparent;
        }

        :is(menupopup, panel) {
        	--panel-background-color: ${palette.quickInput} !important;
        	--panel-text-color: ${base05} !important;
        	--panel-border-color: ${base02} !important;
        }
      '';

      userChrome = with colors; ''
        ${layoutTokens}
        /* Linux paints the title bar in the GTK headerbar color. */
        #navigation-toolbox {
        	background-color: ${base01} !important;
        	color: ${base05} !important;
        }

        /* The active tab joins the surface below it. */
        .tabmail-tab .tab-background[selected] {
        	background-color: ${base00} !important;
        }

        #spacesToolbar {
        	--spaces-bg-image: none !important;
        }

        /* The reader is one surface, header included. */
        @-moz-document url("about:message") {
        	:root {
        		--layout-background-1: ${base00} !important;
        	}
        }
      '';

      # Settings and the address book load in content tabs. Message bodies
      # take the editor colors while Thunderbird's dark reader is on.
      userContent = with colors; ''
        @-moz-document url-prefix("about:") {
        ${layoutTokens}
        }

        @-moz-document url-prefix("mailbox:"), url-prefix("imap:"), url-prefix("news:"), url-prefix("x-moz-ews:") {
        	@media (prefers-color-scheme: dark) and -moz-pref("mail.dark-reader.enabled") {
        		html {
        			background-color: ${base00} !important;
        			color: ${base05} !important;
        		}

        		:link {
        			color: ${palette.link} !important;
        		}
        	}
        }

        @-moz-document url("about:blank?compose") {
        	body {
        		background-color: ${base00} !important;
        		color: ${base05} !important;
        	}
        }
      '';
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.thunderbird = {
          enable = true;
          package = lib.attrByPath [
            "programs"
            "thunderbird"
            "extended"
            "package"
          ] pkgs.thunderbird osConfig;
          profiles.main = {
            isDefault = true;
            withExternalGnupg = true;
            inherit userChrome userContent;
            settings = {
              "mailnews.start_page.enabled" = false;
              # Load userChrome.css and userContent.css.
              "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
              # The palette is dark-only.
              "ui.systemUsesDarkTheme" = 1;
              # Inputs, compose fields included, inset on base00.
              "ui.-moz-field" = colors.base00;
              # Default tags in the palette's accents.
              "mailnews.tags.$label1.color" = colors.base08;
              "mailnews.tags.$label2.color" = colors.base09;
              "mailnews.tags.$label3.color" = colors.base0B;
              "mailnews.tags.$label4.color" = colors.base0D;
              "mailnews.tags.$label5.color" = colors.base0E;
            };
          };
        };
      };
    };
}
