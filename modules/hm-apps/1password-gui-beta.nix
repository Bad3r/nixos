_: {
  flake.homeManagerModules.apps."1password-gui-beta" =
    {
      config,
      osConfig,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."1password-gui-beta".extended;
      nixosEnabled = lib.attrByPath [
        "programs"
        "1password-gui-beta"
        "extended"
        "enable"
      ] false osConfig;
      settingsFormat = pkgs.formats.json { };
      settingsFile = pkgs.writeText "1password-settings.json" (builtins.toJSON cfg.settings);
      emptyJsonFile = pkgs.writeText "empty-json.json" "{}";
    in
    {
      options.programs."1password-gui-beta".extended.settings = lib.mkOption {
        inherit (settingsFormat) type;
        default = {
          version = 1;
          "appearance.interfaceDensity" = "compact";
          "browsers.extension.enabled" = true;
          "developers.cliSharedLockState.enabled" = true;
          "developers.experience.defaultTerminalApplication" = "Kitty";
          "developers.experience.dismissed" = true;
          "developers.experience.enabled" = true;
          "developers.sdkSharedLockState.enabled" = true;
          "devWatchtower.localDiskScanning" = true;
          "itemDetails.showWebFormDetails" = true;
          "keybinds.autoFill" = "CommandOrControl+Shift+[l]L";
          "keybinds.lock" = "CommandOrControl+[/]/";
          "keybinds.open" = "CommandOrControl+Shift+[p]P";
          "privacy.checkHibp" = true;
          "security.authenticatedUnlock.enabled" = true;
          "security.autolock.minutes" = 60;
          "security.holdToggleReveal" = true;
          "sidebar.showCategories" = true;
          "sshAgent.enabled" = true;
          "sshAgent.storeKeyTitles" = true;
          "sshAgent.storeSshKeyTitlesResponseGiven" = true;
          "sshAgent.syncBookmarksToFilesystem" = true;
        };
        description = "1Password settings.json values managed by Home Manager.";
      };

      config = lib.mkIf nixosEnabled {
        home.activation.configure1PasswordSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          settings_dir="$HOME/.config/1Password/settings"
          settings_path="$settings_dir/settings.json"
          settings_tmp="$(mktemp)"
          trap 'rm -f "$settings_tmp"' EXIT

          mkdir -p "$settings_dir"

          if [ -r "$settings_path" ]; then
            existing_settings="$settings_path"
          else
            existing_settings="${emptyJsonFile}"
          fi

          if ! ${pkgs.jq}/bin/jq \
            --slurpfile nixSettings ${settingsFile} \
            '. as $existing
            | $nixSettings[0] as $nix
            | ($existing * $nix)' \
            "$existing_settings" > "$settings_tmp"; then
            echo "ERROR: jq failed to merge 1Password settings" >&2
            exit 1
          fi

          if ! ${pkgs.jq}/bin/jq empty "$settings_tmp" 2>/dev/null; then
            echo "ERROR: resulting 1Password settings are not valid JSON" >&2
            exit 1
          fi

          mv "$settings_tmp" "$settings_path"
          chmod 600 "$settings_path"
        '';
      };
    };
}
