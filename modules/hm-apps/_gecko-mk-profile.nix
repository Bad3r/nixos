/*
  Internal: shared per-profile builder for Gecko browsers
  Description: Composes commonSettings/extensions/bookmarks into a
  Home Manager `programs.<browser>.profiles.<name>` value so firefox.nix and
  librewolf.nix can stay symmetric.

  Arguments:
    pkgs, lib, config: standard module args from the caller.
  Returns:
    mkProfile, policies, nativeMessagingHosts, profile packages, and helpers.
*/

{
  pkgs,
  lib,
  config,
}:
let
  geckoPrefs = import ./_gecko-prefs.nix {
    inherit lib;
    fonts = if (config.stylix.enable or false) then config.stylix.fonts else null;
  };
  geckoBookmarks = import ./_gecko-bookmarks.nix { inherit lib; };
  geckoExtensions = import ./_gecko-extensions.nix {
    inherit
      config
      lib
      pkgs
      ;
  };
  geckoChrome = import ./_gecko-chrome.nix { };
  geckoPolicies = import ./_gecko-policies.nix { };
  geckoShortcuts = import ./_gecko-mk-shortcuts.nix { inherit lib; };

  bookmarksFile = lib.attrByPath [
    "sops"
    "templates"
    "gecko/bookmarks"
    "path"
  ] null config;

  policies = lib.recursiveUpdate (lib.recursiveUpdate geckoPolicies.policies geckoBookmarks.policies) geckoExtensions.extensionPolicies;

  mkProfile =
    {
      id,
      packages,
      extraSettings ? { },
    }:
    {
      inherit id;
      settings =
        geckoPrefs.commonSettings
        // geckoExtensions.sidebarSettings
        // geckoExtensions.toolbarSettings
        // (geckoBookmarks.settings bookmarksFile)
        // extraSettings;
      # Imported dotfiles chrome first; the extension fragment appends so its
      # widget-specific icon override wins the cascade.
      userChrome = geckoChrome.userChrome + geckoExtensions.userChrome;
      extensions = {
        force = true;
        inherit packages;
        settings = geckoExtensions.extensionStorage;
      };
    };

  mkXdgProfileRoot =
    {
      browserName,
      legacyProfilesPath,
      xdgProfilesPath,
    }:
    let
      legacyProfilesRoot = "${config.home.homeDirectory}/${legacyProfilesPath}";
      xdgProfilesRoot = "${config.home.homeDirectory}/${xdgProfilesPath}";
      readlink = lib.getExe' pkgs.coreutils "readlink";
    in
    {
      activation = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
        browser_name=${lib.escapeShellArg browserName}
        xdg_root=${lib.escapeShellArg xdgProfilesRoot}
        legacy_root=${lib.escapeShellArg legacyProfilesRoot}

        if [ -e "$xdg_root" ] || [ -L "$xdg_root" ]; then
          if [ ! -L "$xdg_root" ]; then
            echo "$browser_name XDG profile root must be a symlink to $legacy_root: $xdg_root" >&2
            echo "Move the existing path recoverably with: rip $xdg_root" >&2
            exit 1
          fi

          xdg_resolved="$(${readlink} -m "$xdg_root")"
          legacy_resolved="$(${readlink} -m "$legacy_root")"

          if [ "$xdg_resolved" != "$legacy_resolved" ]; then
            echo "$browser_name XDG profile root resolves to $xdg_resolved, expected $legacy_resolved" >&2
            echo "Move or relink $xdg_root so it points at $legacy_root" >&2
            exit 1
          fi
        fi
      '';
      file = {
        "${xdgProfilesPath}" = {
          source = config.lib.file.mkOutOfStoreSymlink legacyProfilesRoot;
          force = true;
        };
      };
    };

  # Seed Dark Reader's storage.js once per profile as a writable file. Home
  # Manager's extensions.settings would force-rewrite it on every activation
  # and discard the extension's runtime state, so the seed is skipped whenever a
  # real storage.js already exists. `addon@darkreader.org` is the extension ID
  # (the browser-extension-data directory name); see _gecko-extensions.nix.
  mkDarkreaderSeed =
    {
      profilesPath,
      profiles,
    }:
    lib.hm.dag.entryAfter [ "writeBoundary" ] (
      lib.concatMapStringsSep "\n" (profileName: ''
        dr_dir="${config.home.homeDirectory}/${profilesPath}/${profileName}/browser-extension-data/addon@darkreader.org"
        dr_file="$dr_dir/storage.js"
        if [ -L "$dr_file" ] || [ ! -e "$dr_file" ]; then
          $DRY_RUN_CMD rm -f "$dr_file"
          $DRY_RUN_CMD mkdir -p "$dr_dir"
          $DRY_RUN_CMD install -m644 ${geckoExtensions.darkreaderStorageSeed} "$dr_file"
        fi
      '') profiles
    );
in
{
  inherit
    mkProfile
    mkXdgProfileRoot
    mkDarkreaderSeed
    policies
    ;
  inherit (geckoShortcuts) mkCustomKeysFiles;
  inherit (geckoExtensions)
    nativeMessagingHosts
    primaryPackages
    pentestingPackages
    workPackages
    ;
}
